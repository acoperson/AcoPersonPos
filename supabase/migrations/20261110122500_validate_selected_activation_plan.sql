drop function if exists public.register_owner_with_activation_code(text,text);
create or replace function public.register_owner_with_activation_code(
  p_store_name text,
  p_activation_code text,
  p_expected_plan_code text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_code public.activation_codes%rowtype;
  v_plan public.subscription_plans%rowtype;
  v_org uuid;
  v_store uuid;
  v_slug text;
  v_ends timestamptz;
begin
  if v_user is null then raise exception 'Silakan masuk kembali setelah membuat akun'; end if;
  if length(trim(coalesce(p_store_name,''))) < 2 then raise exception 'Nama toko minimal 2 karakter'; end if;
  if exists(select 1 from public.memberships where user_id=v_user) then raise exception 'Akun ini sudah terhubung ke bisnis'; end if;
  select * into v_code from public.activation_codes
  where code_hash=encode(extensions.digest(convert_to(upper(trim(coalesce(p_activation_code,''))),'UTF8'),'sha256'),'hex')
  for update;
  if not found then raise exception 'Kode aktivasi tidak valid'; end if;
  if v_code.status<>'available' then raise exception 'Kode aktivasi sudah digunakan atau dicabut'; end if;
  if v_code.expires_at is not null and v_code.expires_at<=now() then raise exception 'Kode aktivasi sudah kedaluwarsa'; end if;
  select * into v_plan from public.subscription_plans where code=v_code.plan_code and is_active=true;
  if not found then raise exception 'Paket pada kode aktivasi tidak tersedia'; end if;
  if lower(trim(coalesce(p_expected_plan_code,'')))<>v_plan.code then
    raise exception 'Kode aktivasi tidak sesuai dengan paket yang dipilih: %',v_plan.name;
  end if;
  v_org:=gen_random_uuid(); v_store:=gen_random_uuid();
  v_slug:=trim(both '-' from regexp_replace(lower(trim(p_store_name)),'[^a-z0-9]+','-','g'))||'-'||substr(replace(v_org::text,'-',''),1,8);
  insert into public.organizations(id,name,slug,owner_user_id) values(v_org,trim(p_store_name),v_slug,v_user);
  insert into public.stores(id,organization_id,name,code) values(v_store,v_org,trim(p_store_name),'STORE-'||upper(substr(replace(v_store::text,'-',''),1,8)));
  insert into public.memberships(organization_id,user_id,role,store_id) values(v_org,v_user,'owner',null);
  update public.profiles
  set full_name=coalesce(nullif(trim((select raw_user_meta_data->>'full_name' from auth.users where id=v_user)),''),full_name),
      active_organization_id=v_org,updated_at=now()
  where id=v_user;
  v_ends:=now()+make_interval(days=>v_code.duration_days);
  insert into public.subscriptions(organization_id,plan_name,status,starts_at,ends_at) values(v_org,v_plan.code,'active',now(),v_ends);
  update public.activation_codes set status='redeemed',redeemed_by=v_user,organization_id=v_org,redeemed_at=now() where id=v_code.id;
  return jsonb_build_object('organization_id',v_org,'store_id',v_store,'plan_code',v_plan.code,'plan_name',v_plan.name,'ends_at',v_ends);
end;
$function$;
revoke all on function public.register_owner_with_activation_code(text,text,text) from public,anon;
grant execute on function public.register_owner_with_activation_code(text,text,text) to authenticated;