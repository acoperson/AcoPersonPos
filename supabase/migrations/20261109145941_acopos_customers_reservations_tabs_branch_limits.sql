do $$
begin
  if not exists (select 1 from pg_constraint where conname='stores_id_organization_unique' and conrelid='public.stores'::regclass) then
    alter table public.stores add constraint stores_id_organization_unique unique (id, organization_id);
  end if;
end $$;

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  store_id uuid,
  full_name text not null,
  phone text,
  email text,
  member_code text,
  points integer not null default 0 check (points >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customers_store_tenant_fk foreign key (store_id, organization_id)
    references public.stores(id, organization_id) on delete cascade,
  constraint customers_member_code_unique unique (organization_id, member_code)
);

create table if not exists public.customer_tabs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  store_id uuid not null,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name text not null,
  amount numeric(14,2) not null check (amount > 0),
  paid_amount numeric(14,2) not null default 0 check (paid_amount >= 0),
  due_date date,
  status text not null default 'open' check (status in ('open','partial','paid','void')),
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customer_tabs_store_tenant_fk foreign key (store_id, organization_id)
    references public.stores(id, organization_id) on delete cascade,
  constraint customer_tabs_paid_not_over_amount check (paid_amount <= amount)
);

create table if not exists public.customer_tab_payments (
  id uuid primary key default gen_random_uuid(),
  customer_tab_id uuid not null references public.customer_tabs(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  store_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text not null default 'cash',
  received_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint customer_tab_payments_store_tenant_fk foreign key (store_id, organization_id)
    references public.stores(id, organization_id) on delete cascade
);

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  store_id uuid not null,
  customer_name text not null,
  customer_phone text,
  reservation_at timestamptz not null,
  party_size integer not null default 1 check (party_size > 0),
  status text not null default 'pending' check (status in ('pending','confirmed','arrived','completed','cancelled','no_show')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reservations_store_tenant_fk foreign key (store_id, organization_id)
    references public.stores(id, organization_id) on delete cascade
);

create index if not exists customers_org_store_idx on public.customers(organization_id, store_id);
create index if not exists customer_tabs_store_status_idx on public.customer_tabs(store_id, status, due_date);
create index if not exists customer_tab_payments_tab_idx on public.customer_tab_payments(customer_tab_id, created_at desc);
create index if not exists reservations_store_time_idx on public.reservations(store_id, reservation_at);

alter table public.customers enable row level security;
alter table public.customer_tabs enable row level security;
alter table public.customer_tab_payments enable row level security;
alter table public.reservations enable row level security;

drop policy if exists customers_read_assigned on public.customers;
drop policy if exists customers_insert_assigned on public.customers;
drop policy if exists customers_update_assigned on public.customers;
drop policy if exists customers_delete_managers on public.customers;
create policy customers_read_assigned on public.customers
for select to authenticated
using (
  private.has_org_role(organization_id, array['owner','admin'])
  or (store_id is not null and private.can_access_store(store_id))
);
create policy customers_insert_assigned on public.customers
for insert to authenticated
with check (
  (store_id is not null and private.can_access_store(store_id)
   and private.has_org_role(organization_id, array['owner','admin','manager','cashier']))
  or (store_id is null and private.has_org_role(organization_id, array['owner','admin']))
);
create policy customers_update_assigned on public.customers
for update to authenticated
using (
  (store_id is not null and private.can_access_store(store_id)
   and private.has_org_role(organization_id, array['owner','admin','manager']))
  or (store_id is null and private.has_org_role(organization_id, array['owner','admin']))
)
with check (
  (store_id is not null and private.can_access_store(store_id)
   and private.has_org_role(organization_id, array['owner','admin','manager']))
  or (store_id is null and private.has_org_role(organization_id, array['owner','admin']))
);
create policy customers_delete_managers on public.customers
for delete to authenticated
using (private.has_org_role(organization_id, array['owner','admin','manager']) and (store_id is null or private.can_access_store(store_id)));

create policy customer_tabs_read_assigned on public.customer_tabs
for select to authenticated using (private.can_access_store(store_id));
create policy customer_tabs_insert_assigned on public.customer_tabs
for insert to authenticated with check (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager','cashier']));
create policy customer_tabs_update_assigned on public.customer_tabs
for update to authenticated using (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager','cashier']))
with check (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager','cashier']));
create policy customer_tabs_delete_managers on public.customer_tabs
for delete to authenticated using (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager']));

create policy customer_tab_payments_read_assigned on public.customer_tab_payments
for select to authenticated using (private.can_access_store(store_id));
create policy customer_tab_payments_insert_assigned on public.customer_tab_payments
for insert to authenticated with check (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager','cashier']));

create policy reservations_read_assigned on public.reservations
for select to authenticated using (private.can_access_store(store_id));
create policy reservations_insert_assigned on public.reservations
for insert to authenticated with check (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager','cashier']));
create policy reservations_update_assigned on public.reservations
for update to authenticated using (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager','cashier']))
with check (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager','cashier']));
create policy reservations_delete_managers on public.reservations
for delete to authenticated using (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager']));

create or replace function public.record_customer_tab_payment(
  p_customer_tab_id uuid,
  p_amount numeric,
  p_payment_method text default 'cash'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tab public.customer_tabs%rowtype;
  v_new_paid numeric(14,2);
  v_new_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'Nominal pembayaran harus lebih dari nol'; end if;

  select * into v_tab from public.customer_tabs where id=p_customer_tab_id for update;
  if not found then raise exception 'Catatan kasbon tidak ditemukan'; end if;
  if not private.can_access_store(v_tab.store_id)
     or not private.has_org_role(v_tab.organization_id, array['owner','admin','manager','cashier']) then
    raise exception 'Akses kasbon ditolak';
  end if;
  if v_tab.status in ('paid','void') then raise exception 'Kasbon sudah ditutup'; end if;

  v_new_paid := v_tab.paid_amount + p_amount;
  if v_new_paid > v_tab.amount then raise exception 'Pembayaran melebihi sisa kasbon'; end if;
  v_new_status := case when v_new_paid = v_tab.amount then 'paid' else 'partial' end;

  insert into public.customer_tab_payments(customer_tab_id,organization_id,store_id,amount,payment_method,received_by)
  values(v_tab.id,v_tab.organization_id,v_tab.store_id,p_amount,coalesce(nullif(trim(p_payment_method),''),'cash'),auth.uid());

  update public.customer_tabs
  set paid_amount=v_new_paid,status=v_new_status,updated_at=now()
  where id=v_tab.id;

  return jsonb_build_object('customer_tab_id',v_tab.id,'amount',v_tab.amount,'paid_amount',v_new_paid,'remaining',v_tab.amount-v_new_paid,'status',v_new_status);
end;
$function$;

revoke all on function public.record_customer_tab_payment(uuid,numeric,text) from public, anon;
grant execute on function public.record_customer_tab_payment(uuid,numeric,text) to authenticated;

create or replace function private.enforce_store_branch_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_plan_code text;
  v_branch_limit integer;
  v_current_count integer;
begin
  select plan_name into v_plan_code
  from public.subscriptions
  where organization_id = new.organization_id
  order by created_at desc
  limit 1;

  select branch_limit into v_branch_limit
  from public.subscription_plans
  where code = coalesce(v_plan_code, 'free') and is_active = true;

  if v_branch_limit is null then v_branch_limit := 1; end if;

  select count(*) into v_current_count
  from public.stores
  where organization_id = new.organization_id;

  if v_current_count >= v_branch_limit then
    raise exception 'Batas cabang paket Anda adalah %', v_branch_limit;
  end if;
  return new;
end;
$function$;

revoke all on function private.enforce_store_branch_limit() from public, anon, authenticated;
drop trigger if exists enforce_store_branch_limit_before_insert on public.stores;
create trigger enforce_store_branch_limit_before_insert
before insert on public.stores
for each row execute procedure private.enforce_store_branch_limit();

grant select, insert, update, delete on
  public.customers, public.customer_tabs, public.customer_tab_payments, public.reservations
to authenticated;
