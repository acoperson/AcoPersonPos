-- acoPos initial multi-tenant schema
-- Apply with Supabase SQL editor or Supabase CLI migrations.

create extension if not exists pgcrypto;

create type public.app_role as enum ('ADMIN', 'OWNER BISNIS', 'MANAJER', 'KARYAWAN');
create type public.activation_status as enum ('available', 'redeemed', 'revoked');
create type public.order_status as enum ('pending', 'processing', 'completed', 'cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id),
  name text not null,
  slug text unique,
  timezone text not null default 'Asia/Jakarta',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  address text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null default 'KARYAWAN',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, user_id)
);

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  price_idr bigint not null default 0 check (price_idr >= 0),
  duration_days integer not null default 30 check (duration_days > 0),
  branch_limit integer not null default 1 check (branch_limit > 0),
  features jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.activation_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  plan_id uuid not null references public.plans(id),
  business_id uuid references public.businesses(id) on delete cascade,
  status public.activation_status not null default 'available',
  expires_at timestamptz,
  redeemed_by uuid references public.profiles(id),
  redeemed_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.business_subscriptions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  plan_id uuid not null references public.plans(id),
  activation_code_id uuid references public.activation_codes(id),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique (business_id, name)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  sku text,
  name text not null,
  description text,
  price numeric(14,2) not null default 0 check (price >= 0),
  cost numeric(14,2) not null default 0 check (cost >= 0),
  stock numeric(14,3) not null default 0,
  min_stock numeric(14,3) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  full_name text not null,
  phone text,
  email text,
  member_code text,
  points bigint not null default 0,
  created_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  order_number text not null,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name text,
  status public.order_status not null default 'pending',
  subtotal numeric(14,2) not null default 0,
  discount numeric(14,2) not null default 0,
  tax numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  payment_method text,
  payment_reference text,
  notes text,
  cashier_id uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (branch_id, order_number)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  line_total numeric(14,2) not null check (line_total >= 0)
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  product_id uuid not null references public.products(id) on delete cascade,
  movement_type text not null check (movement_type in ('in','out','adjustment','transfer')),
  quantity numeric(14,3) not null,
  note text,
  reference_id uuid,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  description text not null,
  amount numeric(14,2) not null check (amount >= 0),
  category text,
  expense_date date not null default current_date,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  customer_name text not null,
  customer_phone text,
  reservation_at timestamptz not null,
  party_size integer not null default 1 check (party_size > 0),
  status text not null default 'pending',
  notes text,
  created_at timestamptz not null default now()
);

create table public.qr_menus (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  slug text not null unique,
  is_active boolean not null default true,
  allow_ordering boolean not null default true,
  pay_at_cashier boolean not null default true,
  allow_qris boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.customer_tabs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  customer_id uuid references public.customers(id) on delete set null,
  customer_name text not null,
  amount numeric(14,2) not null check (amount > 0),
  paid_amount numeric(14,2) not null default 0,
  due_date date,
  status text not null default 'open',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  user_id uuid not null references public.profiles(id),
  check_in timestamptz not null default now(),
  check_out timestamptz,
  note text
);

create index idx_members_user on public.business_members(user_id, business_id);
create index idx_branches_business on public.branches(business_id);
create index idx_products_business_branch on public.products(business_id, branch_id);
create index idx_orders_business_created on public.orders(business_id, created_at desc);
create index idx_orders_branch_created on public.orders(branch_id, created_at desc);
create index idx_stock_product_created on public.stock_movements(product_id, created_at desc);
create index idx_expenses_business_date on public.expenses(business_id, expense_date desc);

create or replace function public.is_business_member(target_business uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.business_members m
    where m.business_id = target_business and m.user_id = auth.uid() and m.is_active
  ) or exists (
    select 1 from public.businesses b where b.id = target_business and b.owner_id = auth.uid()
  );
$$;

create or replace function public.has_business_role(target_business uuid, allowed_roles public.app_role[])
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.business_members m
    where m.business_id = target_business and m.user_id = auth.uid()
      and m.is_active and m.role = any(allowed_roles)
  ) or exists (
    select 1 from public.businesses b where b.id = target_business and b.owner_id = auth.uid()
      and 'OWNER BISNIS' = any(allowed_roles)
  );
$$;

alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.branches enable row level security;
alter table public.business_members enable row level security;
alter table public.plans enable row level security;
alter table public.activation_codes enable row level security;
alter table public.business_subscriptions enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.expenses enable row level security;
alter table public.reservations enable row level security;
alter table public.qr_menus enable row level security;
alter table public.customer_tabs enable row level security;
alter table public.attendance enable row level security;

create policy "profiles self read" on public.profiles for select using (id = auth.uid());
create policy "profiles self insert" on public.profiles for insert with check (id = auth.uid());
create policy "profiles self update" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy "business owner or member read" on public.businesses for select using (owner_id = auth.uid() or public.is_business_member(id));
create policy "authenticated create business" on public.businesses for insert to authenticated with check (owner_id = auth.uid());
create policy "business owner update" on public.businesses for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "branch member read" on public.branches for select using (public.is_business_member(business_id));
create policy "owner manager branch writes" on public.branches for all using (public.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[])) with check (public.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));

create policy "members read same business" on public.business_members for select using (public.is_business_member(business_id));
create policy "owner manage members" on public.business_members for all using (public.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[])) with check (public.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[]));

create policy "plans visible active" on public.plans for select using (is_active);
create policy "activation code owner read" on public.activation_codes for select using (business_id is not null and public.is_business_member(business_id));
create policy "subscription business read" on public.business_subscriptions for select using (public.is_business_member(business_id));

create policy "categories business access" on public.categories for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy "products business access" on public.products for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy "customers business access" on public.customers for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy "orders business access" on public.orders for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy "order items access via order" on public.order_items for all using (exists (select 1 from public.orders o where o.id = order_id and public.is_business_member(o.business_id))) with check (exists (select 1 from public.orders o where o.id = order_id and public.is_business_member(o.business_id)));
create policy "stock movement business access" on public.stock_movements for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy "expenses business access" on public.expenses for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy "reservations business access" on public.reservations for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy "qr menu business access" on public.qr_menus for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy "customer tabs business access" on public.customer_tabs for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));
create policy "attendance business access" on public.attendance for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

insert into public.plans (code,name,price_idr,duration_days,branch_limit,features) values
('FREE','Free Store',0,30,1,'{"pos":true,"inventory":true,"basic_reports":true}'::jsonb),
('REGULER','Reguler',149000,30,5,'{"business_control":true,"advanced_reports":true}'::jsonb),
('PRO','Professional',299000,30,15,'{"multi_branch_analytics":true,"team_control":true}'::jsonb),
('ENTERPRISE','Enterprise',599000,30,50,'{"centralized_operations":true,"implementation_support":true}'::jsonb)
on conflict (code) do nothing;

-- Important: activation-code creation and redemption must be performed by a trusted
-- server/Edge Function. Never expose the Supabase service-role key in browser code.
