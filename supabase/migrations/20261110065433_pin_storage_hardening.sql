-- Tighten PIN storage and prevent resetting an existing PIN through the setup RPC.
drop policy if exists user_security_pins_deny_all on public.user_security_pins;
create policy user_security_pins_deny_all
on public.user_security_pins
for all to anon, authenticated
using (false)
with check (false);

create or replace function public.set_security_pin(p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_salt text;
  v_rows integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'PIN harus terdiri dari 4 sampai 8 angka'; end if;
  v_salt := encode(extensions.gen_random_bytes(16),'hex');
  insert into public.user_security_pins(user_id,pin_hash,pin_salt,failed_attempts,locked_until,updated_at)
  values(auth.uid(),encode(extensions.digest(convert_to(v_salt || ':' || p_pin,'UTF8'),'sha256'),'hex'),v_salt,0,null,now())
  on conflict(user_id) do nothing;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'PIN sudah dibuat. Gunakan verifikasi PIN untuk masuk; reset harus melalui proses pemulihan akun.'; end if;
end;
$function$;

revoke all on function public.set_security_pin(text) from public, anon;
grant execute on function public.set_security_pin(text) to authenticated;