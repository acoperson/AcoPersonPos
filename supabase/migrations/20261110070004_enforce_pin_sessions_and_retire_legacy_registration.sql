-- Enforce PIN verification at the database boundary for every authenticated business session.
create table if not exists public.user_security_pin_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id text not null,
  verified_at timestamptz not null default now(),
  primary key(user_id,session_id)
);
alter table public.user_security_pin_sessions enable row level security;
revoke all on public.user_security_pin_sessions from anon,authenticated;
drop policy if exists user_security_pin_sessions_deny_all on public.user_security_pin_sessions;
create policy user_security_pin_sessions_deny_all on public.user_security_pin_sessions
for all to anon,authenticated using(false) with check(false);

create or replace function private.is_security_pin_verified()
returns boolean
language sql
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and coalesce(auth.jwt()->>'session_id','') <> ''
    and exists(
      select 1 from public.user_security_pin_sessions s
      where s.user_id=auth.uid()
        and s.session_id=auth.jwt()->>'session_id'
        and s.verified_at > now()-interval '12 hours'
    );
$function$;
revoke all on function private.is_security_pin_verified() from public,anon;
grant execute on function private.is_security_pin_verified() to authenticated;

create or replace function public.set_security_pin(p_pin text)
returns void language plpgsql security definer set search_path = '' as $function$
declare v_salt text; v_rows integer; v_session text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_pin !~ '^[0-9]{4,8}$' then raise exception 'PIN harus terdiri dari 4 sampai 8 angka'; end if;
 v_session:=coalesce(auth.jwt()->>'session_id','');
 if v_session='' then raise exception 'Sesi keamanan tidak valid. Silakan login ulang.'; end if;
 v_salt:=encode(extensions.gen_random_bytes(16),'hex');
 insert into public.user_security_pins(user_id,pin_hash,pin_salt,failed_attempts,locked_until,updated_at)
 values(auth.uid(),encode(extensions.digest(convert_to(v_salt||':'||p_pin,'UTF8'),'sha256'),'hex'),v_salt,0,null,now())
 on conflict(user_id) do nothing;
 get diagnostics v_rows = row_count;
 if v_rows=0 then raise exception 'PIN sudah dibuat. Gunakan verifikasi PIN untuk masuk; reset harus melalui proses pemulihan akun.'; end if;
 insert into public.user_security_pin_sessions(user_id,session_id,verified_at)
 values(auth.uid(),v_session,now())
 on conflict(user_id,session_id) do update set verified_at=excluded.verified_at;
end;$function$;

create or replace function public.verify_security_pin(p_pin text)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare v_row public.user_security_pins%rowtype; v_session text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 v_session:=coalesce(auth.jwt()->>'session_id','');
 if v_session='' then raise exception 'Sesi keamanan tidak valid. Silakan login ulang.'; end if;
 select * into v_row from public.user_security_pins where user_id=auth.uid() for update;
 if not found then raise exception 'PIN belum dibuat'; end if;
 if v_row.locked_until is not null and v_row.locked_until>now() then raise exception using message='Terlalu banyak percobaan. Coba lagi setelah '||to_char(v_row.locked_until,'HH24:MI'); end if;
 if v_row.pin_hash=encode(extensions.digest(convert_to(v_row.pin_salt||':'||coalesce(p_pin,''),'UTF8'),'sha256'),'hex') then
   update public.user_security_pins set failed_attempts=0,locked_until=null,updated_at=now() where user_id=auth.uid();
   insert into public.user_security_pin_sessions(user_id,session_id,verified_at)
   values(auth.uid(),v_session,now())
   on conflict(user_id,session_id) do update set verified_at=excluded.verified_at;
   delete from public.user_security_pin_sessions where user_id=auth.uid() and verified_at<now()-interval '12 hours';
   return true;
 end if;
 update public.user_security_pins set failed_attempts=failed_attempts+1,
   locked_until=case when failed_attempts+1>=5 then now()+interval '15 minutes' else null end,
   updated_at=now() where user_id=auth.uid();
 return false;
end;$function$;

-- All direct authenticated table access requires a verified PIN session.
do $guard$
declare t record;
begin
 for t in select tablename from pg_tables where schemaname='public'
   and tablename not in ('user_security_pins','user_security_pin_sessions')
 loop
   execute format('drop policy if exists pin_verified_guard on public.%I',t.tablename);
   execute format('create policy pin_verified_guard on public.%I as restrictive for all to authenticated using (private.is_security_pin_verified()) with check (private.is_security_pin_verified())',t.tablename);
 end loop;
end;
$guard$;

-- Guard all authenticated SECURITY DEFINER business RPCs. Registration and PIN setup
-- are intentionally excluded because they run before the first successful PIN challenge.
do $guard$
declare r record; v_def text; v_new text;
begin
 for r in
   select p.oid,p.proname
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   join pg_language l on l.oid=p.prolang
   where n.nspname='public' and p.prosecdef and l.lanname='plpgsql'
     and p.proname not in (
       'attach_public_qr_payment_proof','claim_employee_activation_code','claim_employee_invites',
       'get_public_order_queue','get_public_store_catalog','register_owner_with_activation_code',
       'set_security_pin','submit_public_qr_order','verify_security_pin'
     )
 loop
   v_def:=pg_get_functiondef(r.oid);
   v_new:=replace(v_def,E'\nbegin\n',E'\nbegin\n  if auth.uid() is null or not private.is_security_pin_verified() then raise exception ''PIN security verification required''; end if;\n');
   if v_new=v_def then
     raise exception 'Could not add PIN guard to function %',r.proname;
   end if;
   execute v_new;
 end loop;
end;
$guard$;

-- Disable the legacy no-code business creation endpoints permanently.
create or replace function public.create_business(p_business_name text,p_store_name text)
returns uuid language plpgsql security definer set search_path = '' as $function$
begin
 raise exception 'Pendaftaran lama dinonaktifkan. Gunakan formulir pendaftaran dengan kode aktivasi.';
end;$function$;
create or replace function public.submit_business_application(
 p_business_name text,p_store_name text,p_requested_plan text default 'free',p_applicant_note text default null
) returns jsonb language plpgsql security definer set search_path = '' as $function$
begin
 raise exception 'Pendaftaran lama dinonaktifkan. Gunakan formulir pendaftaran dengan kode aktivasi.';
end;$function$;
revoke all on function public.create_business(text,text) from public,anon;
grant execute on function public.create_business(text,text) to authenticated;
revoke all on function public.submit_business_application(text,text,text,text) from public,anon;
grant execute on function public.submit_business_application(text,text,text,text) to authenticated;

-- PIN session helpers and enrollment remain callable before the guard is satisfied.
revoke all on function public.set_security_pin(text) from public,anon;
revoke all on function public.verify_security_pin(text) from public,anon;
grant execute on function public.set_security_pin(text) to authenticated;
grant execute on function public.verify_security_pin(text) to authenticated;