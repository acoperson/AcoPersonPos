alter table public.subscription_plans
  add column if not exists duration_days integer not null default 30 check (duration_days > 0),
  add column if not exists branch_limit integer not null default 1 check (branch_limit > 0),
  add column if not exists features jsonb not null default '{}'::jsonb;

insert into public.subscription_plans
  (code, name, price_idr, billing_period, is_paid, is_active, description, duration_days, branch_limit, features)
values
  ('free', 'Free Store', 0, 'gratis', false, true, 'Paket awal untuk satu toko. Harga dan fitur dapat disesuaikan admin.', 30, 1, '{"pos":true,"inventory":true,"basic_reports":true}'::jsonb),
  ('regular', 'Reguler', 149000, '30 hari', true, true, 'Paket untuk bisnis yang sedang berkembang. Harga awal dapat disesuaikan admin.', 30, 5, '{"multi_branch":true,"business_control":true}'::jsonb),
  ('professional', 'Professional', 299000, '30 hari', true, true, 'Paket untuk operasional multi-cabang. Harga awal dapat disesuaikan admin.', 30, 15, '{"multi_branch":true,"analytics":true,"team_control":true}'::jsonb),
  ('enterprise', 'Enterprise', 599000, '30 hari', true, true, 'Paket untuk bisnis skala besar. Harga awal dapat disesuaikan admin.', 30, 50, '{"multi_branch":true,"analytics":true,"centralized_control":true}'::jsonb)
on conflict (code) do nothing;

create table if not exists public.activation_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  plan_code text not null references public.subscription_plans(code),
  duration_days integer not null check (duration_days > 0),
  status text not null default 'available' check (status in ('available','redeemed','revoked')),
  expires_at timestamptz,
  issued_by uuid references auth.users(id),
  redeemed_by uuid references auth.users(id),
  organization_id uuid references public.organizations(id),
  redeemed_at timestamptz,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists activation_codes_status_expiry_idx
  on public.activation_codes(status, expires_at);

alter table public.activation_codes enable row level security;
drop policy if exists activation_codes_admin_read on public.activation_codes;
create policy activation_codes_admin_read on public.activation_codes
for select to authenticated
using (public.is_platform_admin());

grant select on public.activation_codes to authenticated;
grant select on public.subscription_plans to anon, authenticated;

create or replace function public.admin_generate_activation_codes(
  p_plan_code text,
  p_quantity integer default 1,
  p_expires_at timestamptz default null,
  p_note text default null
)
returns table(code text, plan_code text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_plan public.subscription_plans%rowtype;
  v_code text;
  v_i integer;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'Platform admin access required';
  end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 100 then
    raise exception 'Jumlah kode harus antara 1 dan 100';
  end if;

  select * into v_plan
  from public.subscription_plans
  where code = lower(trim(p_plan_code)) and is_active = true;
  if not found then raise exception 'Paket tidak ditemukan atau tidak aktif'; end if;

  for v_i in 1..p_quantity loop
    v_code := 'ACO-' ||
      upper(substr(encode(extensions.gen_random_bytes(10), 'hex'), 1, 10)) || '-' ||
      upper(substr(encode(extensions.gen_random_bytes(10), 'hex'), 1, 10));

    insert into public.activation_codes(code_hash, plan_code, duration_days, expires_at, issued_by, note)
    values (
      encode(extensions.digest(convert_to(v_code, 'UTF8'), 'sha256'), 'hex'),
      v_plan.code,
      v_plan.duration_days,
      p_expires_at,
      auth.uid(),
      nullif(trim(coalesce(p_note, '')), '')
    );

    code := v_code;
    plan_code := v_plan.code;
    expires_at := p_expires_at;
    return next;
  end loop;
end;
$function$;

create or replace function public.redeem_activation_code(
  p_code text,
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_code public.activation_codes%rowtype;
  v_plan public.subscription_plans%rowtype;
  v_store_count integer;
  v_ends_at timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.has_org_role(p_organization_id, array['owner','admin']) then
    raise exception 'Hanya pemilik bisnis yang dapat mengaktifkan paket';
  end if;
  if length(trim(coalesce(p_code, ''))) < 8 then raise exception 'Kode aktivasi tidak valid'; end if;

  select * into v_code
  from public.activation_codes
  where code_hash = encode(extensions.digest(convert_to(upper(trim(p_code)), 'UTF8'), 'sha256'), 'hex')
  for update;

  if not found then raise exception 'Kode aktivasi tidak ditemukan'; end if;
  if v_code.status <> 'available' then raise exception 'Kode aktivasi sudah digunakan atau dicabut'; end if;
  if v_code.expires_at is not null and v_code.expires_at <= now() then
    raise exception 'Kode aktivasi sudah kedaluwarsa';
  end if;

  select * into v_plan from public.subscription_plans
  where code = v_code.plan_code and is_active = true;
  if not found then raise exception 'Paket sudah tidak tersedia'; end if;

  select count(*) into v_store_count
  from public.stores where organization_id = p_organization_id;
  if v_store_count > v_plan.branch_limit then
    raise exception 'Jumlah cabang melebihi batas paket. Sesuaikan cabang sebelum aktivasi.';
  end if;

  v_ends_at := now() + make_interval(days => v_code.duration_days);

  update public.subscriptions
  set plan_name = v_plan.code,
      status = 'active',
      starts_at = now(),
      ends_at = v_ends_at
  where organization_id = p_organization_id;

  if not found then
    insert into public.subscriptions(organization_id, plan_name, status, starts_at, ends_at)
    values (p_organization_id, v_plan.code, 'active', now(), v_ends_at);
  end if;

  update public.activation_codes
  set status = 'redeemed',
      redeemed_by = auth.uid(),
      organization_id = p_organization_id,
      redeemed_at = now()
  where id = v_code.id;

  return jsonb_build_object(
    'result', 'activated',
    'plan_code', v_plan.code,
    'plan_name', v_plan.name,
    'branch_limit', v_plan.branch_limit,
    'starts_at', now(),
    'ends_at', v_ends_at
  );
end;
$function$;

revoke all on function public.admin_generate_activation_codes(text, integer, timestamptz, text) from public, anon;
revoke all on function public.redeem_activation_code(text, uuid) from public, anon;
grant execute on function public.admin_generate_activation_codes(text, integer, timestamptz, text) to authenticated;
grant execute on function public.redeem_activation_code(text, uuid) to authenticated;
