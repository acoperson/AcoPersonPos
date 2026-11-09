-- Harden the initial tenant schema: keep authorization helpers in a non-exposed schema,
-- enforce role-specific writes, and move the signup trigger out of public.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

drop trigger if exists on_auth_user_created_acopos on auth.users;
drop function if exists public.bootstrap_new_user();

create or replace function private.bootstrap_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_business_id uuid;
  business_label text;
  base_slug text;
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(coalesce(new.email, 'owner'), '@', 1))
  )
  on conflict (id) do nothing;

  business_label := coalesce(nullif(new.raw_user_meta_data ->> 'business_name', ''), 'Bisnis ' || coalesce(split_part(new.email, '@', 1), 'Baru'));
  base_slug := lower(regexp_replace(business_label, '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(replace(new.id::text, '-', ''), 1, 8);

  insert into public.businesses (owner_id, name, slug)
  values (new.id, business_label, base_slug)
  returning id into new_business_id;

  insert into public.branches (business_id, name)
  values (new_business_id, 'Toko Utama');

  insert into public.business_members (business_id, user_id, role, is_active)
  values (new_business_id, new.id, 'OWNER BISNIS', true)
  on conflict (business_id, user_id) do nothing;

  insert into public.business_subscriptions (business_id, plan_id, starts_at, ends_at, is_active)
  select new_business_id, p.id, now(), null, true
  from public.plans p
  where p.code = 'FREE'
  limit 1;

  return new;
end;
$$;

revoke all on function private.bootstrap_new_user() from public, anon, authenticated;
create trigger on_auth_user_created_acopos
after insert on auth.users
for each row execute procedure private.bootstrap_new_user();

create or replace function private.is_business_member(target_business uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_members m
    where m.business_id = target_business
      and m.user_id = (select auth.uid())
      and m.is_active
  ) or exists (
    select 1
    from public.businesses b
    where b.id = target_business
      and b.owner_id = (select auth.uid())
  );
$$;

create or replace function private.has_business_role(target_business uuid, allowed_roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_members m
    where m.business_id = target_business
      and m.user_id = (select auth.uid())
      and m.is_active
      and m.role = any(allowed_roles)
  );
$$;

revoke all on function private.is_business_member(uuid) from public, anon;
revoke all on function private.has_business_role(uuid, public.app_role[]) from public, anon;
grant execute on function private.is_business_member(uuid) to authenticated;
grant execute on function private.has_business_role(uuid, public.app_role[]) to authenticated;

-- Remove the original public SECURITY DEFINER helpers after dependent policies are dropped.
drop policy if exists "profiles self read" on public.profiles;
drop policy if exists "profiles self insert" on public.profiles;
drop policy if exists "profiles self update" on public.profiles;
drop policy if exists "business owner or member read" on public.businesses;
drop policy if exists "authenticated create business" on public.businesses;
drop policy if exists "business owner update" on public.businesses;
drop policy if exists "branch member read" on public.branches;
drop policy if exists "owner manager branch writes" on public.branches;
drop policy if exists "members read same business" on public.business_members;
drop policy if exists "owner manage members" on public.business_members;
drop policy if exists "plans visible active" on public.plans;
drop policy if exists "activation code owner read" on public.activation_codes;
drop policy if exists "subscription business read" on public.business_subscriptions;
drop policy if exists "categories business access" on public.categories;
drop policy if exists "products business access" on public.products;
drop policy if exists "customers business access" on public.customers;
drop policy if exists "orders business access" on public.orders;
drop policy if exists "order items access via order" on public.order_items;
drop policy if exists "stock movement business access" on public.stock_movements;
drop policy if exists "expenses business access" on public.expenses;
drop policy if exists "reservations business access" on public.reservations;
drop policy if exists "qr menu business access" on public.qr_menus;
drop policy if exists "customer tabs business access" on public.customer_tabs;
drop policy if exists "attendance business access" on public.attendance;

drop function if exists public.is_business_member(uuid);
drop function if exists public.has_business_role(uuid, public.app_role[]);

create policy "profiles self read" on public.profiles
for select to authenticated using (id = (select auth.uid()));
create policy "profiles self insert" on public.profiles
for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles self update" on public.profiles
for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "business owner or member read" on public.businesses
for select to authenticated using (owner_id = (select auth.uid()) or private.is_business_member(id));
create policy "authenticated create business" on public.businesses
for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "business owner update" on public.businesses
for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy "branch member read" on public.branches
for select to authenticated using (private.is_business_member(business_id));
create policy "owner manager branch insert" on public.branches
for insert to authenticated with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "owner manager branch update" on public.branches
for update to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]))
with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "owner manager branch delete" on public.branches
for delete to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));

create policy "members read same business" on public.business_members
for select to authenticated using (private.is_business_member(business_id));
create policy "owner manage members" on public.business_members
for all to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[]))
with check (private.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[]));

create policy "plans visible active" on public.plans
for select to anon, authenticated using (is_active);
create policy "activation code owner read" on public.activation_codes
for select to authenticated using (business_id is not null and private.is_business_member(business_id));
create policy "subscription business read" on public.business_subscriptions
for select to authenticated using (private.is_business_member(business_id));

create policy "categories read" on public.categories
for select to authenticated using (private.is_business_member(business_id));
create policy "categories insert" on public.categories
for insert to authenticated with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "categories update" on public.categories
for update to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]))
with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "categories delete" on public.categories
for delete to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));

create policy "products read" on public.products
for select to authenticated using (private.is_business_member(business_id));
create policy "products insert" on public.products
for insert to authenticated with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "products update" on public.products
for update to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]))
with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "products delete" on public.products
for delete to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));

create policy "customers read" on public.customers
for select to authenticated using (private.is_business_member(business_id));
create policy "customers insert" on public.customers
for insert to authenticated with check (private.is_business_member(business_id));
create policy "customers update" on public.customers
for update to authenticated using (private.is_business_member(business_id)) with check (private.is_business_member(business_id));

create policy "orders read" on public.orders
for select to authenticated using (private.is_business_member(business_id));
create policy "orders insert" on public.orders
for insert to authenticated with check (private.is_business_member(business_id));
create policy "orders update" on public.orders
for update to authenticated using (private.is_business_member(business_id)) with check (private.is_business_member(business_id));
create policy "orders delete" on public.orders
for delete to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));

create policy "order items read" on public.order_items
for select to authenticated using (exists (select 1 from public.orders o where o.id = order_id and private.is_business_member(o.business_id)));
create policy "order items insert" on public.order_items
for insert to authenticated with check (exists (select 1 from public.orders o where o.id = order_id and private.is_business_member(o.business_id)));
create policy "order items update" on public.order_items
for update to authenticated using (exists (select 1 from public.orders o where o.id = order_id and private.is_business_member(o.business_id)))
with check (exists (select 1 from public.orders o where o.id = order_id and private.is_business_member(o.business_id)));
create policy "order items delete" on public.order_items
for delete to authenticated using (exists (select 1 from public.orders o where o.id = order_id and private.has_business_role(o.business_id, array['OWNER BISNIS','MANAJER']::public.app_role[])));

create policy "stock movements read" on public.stock_movements
for select to authenticated using (private.is_business_member(business_id));
create policy "stock movements insert" on public.stock_movements
for insert to authenticated with check (private.is_business_member(business_id));

create policy "expenses read" on public.expenses
for select to authenticated using (private.is_business_member(business_id));
create policy "expenses insert" on public.expenses
for insert to authenticated with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "expenses update" on public.expenses
for update to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]))
with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "expenses delete" on public.expenses
for delete to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[]));

create policy "reservations read" on public.reservations
for select to authenticated using (private.is_business_member(business_id));
create policy "reservations insert" on public.reservations
for insert to authenticated with check (private.is_business_member(business_id));
create policy "reservations update" on public.reservations
for update to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]))
with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "reservations delete" on public.reservations
for delete to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[]));

create policy "qr menus read" on public.qr_menus
for select to authenticated using (private.is_business_member(business_id));
create policy "qr menus insert" on public.qr_menus
for insert to authenticated with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "qr menus update" on public.qr_menus
for update to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]))
with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));
create policy "qr menus delete" on public.qr_menus
for delete to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[]));

create policy "customer tabs read" on public.customer_tabs
for select to authenticated using (private.is_business_member(business_id));
create policy "customer tabs insert" on public.customer_tabs
for insert to authenticated with check (private.is_business_member(business_id));
create policy "customer tabs update" on public.customer_tabs
for update to authenticated using (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]))
with check (private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[]));

create policy "attendance read" on public.attendance
for select to authenticated using (
  user_id = (select auth.uid()) or private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[])
);
create policy "attendance insert self" on public.attendance
for insert to authenticated with check (user_id = (select auth.uid()) and private.is_business_member(business_id));
create policy "attendance update self or manager" on public.attendance
for update to authenticated using (
  user_id = (select auth.uid()) or private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[])
) with check (
  user_id = (select auth.uid()) or private.has_business_role(business_id, array['OWNER BISNIS','MANAJER']::public.app_role[])
);

-- Ensure Data API privileges are explicit; row-level policies remain the actual data boundary.
grant usage on schema public to anon, authenticated;
grant select on public.plans to anon, authenticated;
grant select, insert, update, delete on
  public.profiles, public.businesses, public.branches, public.business_members,
  public.activation_codes, public.business_subscriptions, public.categories,
  public.products, public.customers, public.orders, public.order_items,
  public.stock_movements, public.expenses, public.reservations, public.qr_menus,
  public.customer_tabs, public.attendance
to authenticated;
grant usage, select on all sequences in schema public to authenticated;
