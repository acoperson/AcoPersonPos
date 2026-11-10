-- AcoPos registration, team activation codes, and account PIN challenge.
-- This migration is additive: historical applications and memberships are preserved.

alter table public.employee_invites
  add column if not exists code_hash text,
  add column if not exists expires_at timestamptz,
  add column if not exists redeemed_at timestamptz;

create unique index if not exists employee_invites_code_hash_uidx
  on public.employee_invites(code_hash)
  where code_hash is not null;

create table if not exists public.user_security_pins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  pin_salt text not null,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_security_pins enable row level security;
revoke all on public.user_security_pins from anon, authenticated;

create or replace function public.register_owner_with_activation_code(
  p_store_name text,
  p_activation_code text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_email text;
  v_code public.activation_codes%rowtype;
  v_plan public.subscription_plans%rowtype;
  v_org uuid;
  v_store uuid;
  v_slug text;
  v_ends timestamptz;
begin
  if v_user is null then raise exception 'Silakan masuk kembali setelah membuat akun'; end if;
  if length(trim(coalesce(p_store_name,''))) < 2 then raise exception 'Nama toko minimal 2 karakter'; end if;
  select lower(email) into v_email from auth.users where id = v_user;
  if v_email is null then raise exception 'Email akun tidak ditemukan'; end if;
  if exists(select 1 from public.memberships where user_id = v_user) then
    raise exception 'Akun ini sudah terhubung ke bisnis';
  end if;

  select * into v_code
  from public.activation_codes
  where code_hash = encode(extensions.digest(convert_to(upper(trim(coalesce(p_activation_code,''))), 'UTF8'),'sha256'),'hex')
  for update;
  if not found then raise exception 'Kode aktivasi tidak valid'; end if;
  if v_code.status <> 'available' then raise exception 'Kode aktivasi sudah digunakan atau dicabut'; end if;
  if v_code.expires_at is not null and v_code.expires_at <= now() then raise exception 'Kode aktivasi sudah kedaluwarsa'; end if;

  select * into v_plan from public.subscription_plans
  where code = v_code.plan_code and is_active = true;
  if not found then raise exception 'Paket pada kode aktivasi tidak tersedia'; end if;

  v_org := gen_random_uuid();
  v_store := gen_random_uuid();
  v_slug := trim(both '-' from regexp_replace(lower(trim(p_store_name)), '[^a-z0-9]+', '-', 'g')) || '-' || substr(replace(v_org::text,'-',''),1,8);

  insert into public.organizations(id,name,slug,owner_user_id)
  values(v_org,trim(p_store_name),v_slug,v_user);

  insert into public.stores(id,organization_id,name,code)
  values(v_store,v_org,trim(p_store_name),'STORE-' || upper(substr(replace(v_store::text,'-',''),1,8)));

  insert into public.memberships(organization_id,user_id,role,store_id)
  values(v_org,v_user,'owner',null);

  update public.profiles
  set full_name = coalesce(nullif(trim((select raw_user_meta_data->>'full_name' from auth.users where id=v_user)),''),full_name),
      active_organization_id = v_org,
      updated_at = now()
  where id = v_user;

  v_ends := now() + make_interval(days => v_code.duration_days);
  insert into public.subscriptions(organization_id,plan_name,status,starts_at,ends_at)
  values(v_org,v_plan.code,'active',now(),v_ends);

  update public.activation_codes
  set status='redeemed', redeemed_by=v_user, organization_id=v_org, redeemed_at=now()
  where id=v_code.id;

  return jsonb_build_object('organization_id',v_org,'store_id',v_store,'plan_code',v_plan.code,'plan_name',v_plan.name,'ends_at',v_ends);
end;
$function$;

create or replace function public.issue_employee_activation_code(
  p_organization_id uuid,
  p_store_id uuid,
  p_email text,
  p_role text,
  p_expires_at timestamptz default (now() + interval '7 days')
) returns table(code text, email text, role text, store_id uuid, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_code text;
  v_email text := lower(trim(coalesce(p_email,'')));
begin
  if auth.uid() is null or not private.has_org_role(p_organization_id,array['owner','admin']) then
    raise exception 'Hanya owner/admin bisnis yang dapat menerbitkan kode anggota';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Email anggota tidak valid'; end if;
  if p_role not in ('manager','cashier','employee') then raise exception 'Peran anggota tidak valid'; end if;
  if not exists(select 1 from public.stores where id=p_store_id and organization_id=p_organization_id) then
    raise exception 'Cabang tidak ditemukan pada bisnis ini';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then raise exception 'Masa berlaku kode harus di masa depan'; end if;

  v_code := 'TEAM-' || upper(substr(encode(extensions.gen_random_bytes(12),'hex'),1,16));
  insert into public.employee_invites(organization_id,store_id,email,role,status,invited_by,code_hash,expires_at)
  values(p_organization_id,p_store_id,v_email,p_role,'pending',auth.uid(),
    encode(extensions.digest(convert_to(v_code,'UTF8'),'sha256'),'hex'),p_expires_at);
  return query select v_code,v_email,p_role,p_store_id,p_expires_at;
end;
$function$;

create or replace function public.claim_employee_activation_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_email text;
  v_invite public.employee_invites%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select lower(email) into v_email from auth.users where id=v_user;
  if v_email is null then raise exception 'Email akun tidak ditemukan'; end if;

  select * into v_invite
  from public.employee_invites
  where code_hash = encode(extensions.digest(convert_to(upper(trim(coalesce(p_code,''))),'UTF8'),'sha256'),'hex')
  for update;
  if not found then raise exception 'Kode aktivasi anggota tidak ditemukan'; end if;
  if v_invite.status <> 'pending' or v_invite.redeemed_at is not null then raise exception 'Kode anggota sudah digunakan atau dicabut'; end if;
  if v_invite.expires_at is not null and v_invite.expires_at <= now() then raise exception 'Kode anggota sudah kedaluwarsa'; end if;
  if lower(v_invite.email) <> v_email then raise exception 'Kode ini diterbitkan untuk email yang berbeda'; end if;

  insert into public.memberships(organization_id,user_id,role,store_id)
  values(v_invite.organization_id,v_user,v_invite.role,v_invite.store_id)
  on conflict(organization_id,user_id) do update set role=excluded.role,store_id=excluded.store_id;

  update public.employee_invites set status='accepted',redeemed_at=now() where id=v_invite.id;
  update public.profiles set active_organization_id=v_invite.organization_id,updated_at=now() where id=v_user;

  return jsonb_build_object('organization_id',v_invite.organization_id,'store_id',v_invite.store_id,'role',v_invite.role);
end;
$function$;

-- Legacy email-only invitations are no longer auto-claimed. New members must redeem a code.
create or replace function public.claim_employee_invites()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
begin
  return 0;
end;
$function$;

create or replace function public.has_security_pin()
returns boolean
language sql
security definer
set search_path = ''
as $function$
  select exists(select 1 from public.user_security_pins where user_id=auth.uid());
$function$;

create or replace function public.set_security_pin(p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_salt text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'PIN harus terdiri dari 4 sampai 8 angka'; end if;
  v_salt := encode(extensions.gen_random_bytes(16),'hex');
  insert into public.user_security_pins(user_id,pin_hash,pin_salt,failed_attempts,locked_until,updated_at)
  values(auth.uid(),encode(extensions.digest(convert_to(v_salt || ':' || p_pin,'UTF8'),'sha256'),'hex'),v_salt,0,null,now())
  on conflict(user_id) do update set pin_hash=excluded.pin_hash,pin_salt=excluded.pin_salt,failed_attempts=0,locked_until=null,updated_at=now();
end;
$function$;

create or replace function public.verify_security_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.user_security_pins%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_row from public.user_security_pins where user_id=auth.uid() for update;
  if not found then raise exception 'PIN belum dibuat'; end if;
  if v_row.locked_until is not null and v_row.locked_until > now() then
    raise exception using message = 'Terlalu banyak percobaan. Coba lagi setelah ' || to_char(v_row.locked_until,'HH24:MI');
  end if;
  if v_row.pin_hash = encode(extensions.digest(convert_to(v_row.pin_salt || ':' || coalesce(p_pin,''),'UTF8'),'sha256'),'hex') then
    update public.user_security_pins set failed_attempts=0,locked_until=null,updated_at=now() where user_id=auth.uid();
    return true;
  end if;
  update public.user_security_pins
  set failed_attempts=failed_attempts+1,
      locked_until=case when failed_attempts+1 >= 5 then now()+interval '15 minutes' else null end,
      updated_at=now()
  where user_id=auth.uid();
  return false;
end;
$function$;

revoke all on function public.register_owner_with_activation_code(text,text) from public,anon;
revoke all on function public.issue_employee_activation_code(uuid,uuid,text,text,timestamptz) from public,anon;
revoke all on function public.claim_employee_activation_code(text) from public,anon;
revoke all on function public.claim_employee_invites() from public,anon;
revoke all on function public.has_security_pin() from public,anon;
revoke all on function public.set_security_pin(text) from public,anon;
revoke all on function public.verify_security_pin(text) from public,anon;
grant execute on function public.register_owner_with_activation_code(text,text) to authenticated;
grant execute on function public.issue_employee_activation_code(uuid,uuid,text,text,timestamptz) to authenticated;
grant execute on function public.claim_employee_activation_code(text) to authenticated;
grant execute on function public.claim_employee_invites() to authenticated;
grant execute on function public.has_security_pin() to authenticated;
grant execute on function public.set_security_pin(text) to authenticated;
grant execute on function public.verify_security_pin(text) to authenticated;
