create or replace function public.issue_employee_activation_code(
  p_organization_id uuid,
  p_store_id uuid,
  p_email text,
  p_role text,
  p_expires_at timestamptz default (now()+interval '7 days')
) returns table(code text,email text,role text,store_id uuid,expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_code text;
  v_email text := lower(trim(coalesce(p_email,'')));
  v_domain text;
begin
  if auth.uid() is null or not private.is_security_pin_verified() then
    raise exception 'PIN security verification required';
  end if;
  if not private.has_org_role(p_organization_id,array['owner','admin']) then
    raise exception 'Hanya owner/admin bisnis yang dapat menerbitkan kode anggota';
  end if;
  v_domain:=split_part(v_email,'@',2);
  if position('@' in v_email)<=1 or position('@' in v_domain)>0 or position('.' in v_domain)<=1 or position(' ' in v_email)>0 then
    raise exception 'Email anggota tidak valid';
  end if;
  if p_role not in ('manager','cashier','employee') then raise exception 'Peran anggota tidak valid'; end if;
  if not exists(select 1 from public.stores where id=p_store_id and organization_id=p_organization_id) then
    raise exception 'Cabang tidak ditemukan pada bisnis ini';
  end if;
  if p_expires_at is not null and p_expires_at<=now() then raise exception 'Masa berlaku kode harus di masa depan'; end if;
  v_code:='TEAM-'||upper(substr(encode(extensions.gen_random_bytes(12),'hex'),1,16));
  insert into public.employee_invites(organization_id,store_id,email,role,status,invited_by,code_hash,expires_at)
  values(p_organization_id,p_store_id,v_email,p_role,'pending',auth.uid(),
    encode(extensions.digest(convert_to(v_code,'UTF8'),'sha256'),'hex'),p_expires_at);
  return query select v_code,v_email,p_role,p_store_id,p_expires_at;
end;
$function$;
revoke all on function public.issue_employee_activation_code(uuid,uuid,text,text,timestamptz) from public,anon;
grant execute on function public.issue_employee_activation_code(uuid,uuid,text,text,timestamptz) to authenticated;