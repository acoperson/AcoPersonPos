-- Enforce that branch references always belong to the same tenant.
-- Prevent business owners from assigning global ADMIN or another OWNER role to staff.

alter table public.branches
  add constraint branches_id_business_unique unique (id, business_id);

alter table public.business_members
  drop constraint if exists business_members_branch_id_fkey;
alter table public.business_members
  add constraint business_members_branch_tenant_fk
  foreign key (branch_id, business_id)
  references public.branches (id, business_id)
  on delete set null (branch_id);

alter table public.products
  drop constraint if exists products_branch_id_fkey;
alter table public.products
  add constraint products_branch_tenant_fk
  foreign key (branch_id, business_id)
  references public.branches (id, business_id)
  on delete cascade;

alter table public.orders
  drop constraint if exists orders_branch_id_fkey;
alter table public.orders
  add constraint orders_branch_tenant_fk
  foreign key (branch_id, business_id)
  references public.branches (id, business_id)
  on delete restrict;

alter table public.stock_movements
  drop constraint if exists stock_movements_branch_id_fkey;
alter table public.stock_movements
  add constraint stock_movements_branch_tenant_fk
  foreign key (branch_id, business_id)
  references public.branches (id, business_id)
  on delete restrict;

alter table public.expenses
  drop constraint if exists expenses_branch_id_fkey;
alter table public.expenses
  add constraint expenses_branch_tenant_fk
  foreign key (branch_id, business_id)
  references public.branches (id, business_id)
  on delete restrict;

alter table public.reservations
  drop constraint if exists reservations_branch_id_fkey;
alter table public.reservations
  add constraint reservations_branch_tenant_fk
  foreign key (branch_id, business_id)
  references public.branches (id, business_id)
  on delete restrict;

alter table public.qr_menus
  drop constraint if exists qr_menus_branch_id_fkey;
alter table public.qr_menus
  add constraint qr_menus_branch_tenant_fk
  foreign key (branch_id, business_id)
  references public.branches (id, business_id)
  on delete cascade;

alter table public.customer_tabs
  drop constraint if exists customer_tabs_branch_id_fkey;
alter table public.customer_tabs
  add constraint customer_tabs_branch_tenant_fk
  foreign key (branch_id, business_id)
  references public.branches (id, business_id)
  on delete restrict;

alter table public.attendance
  drop constraint if exists attendance_branch_id_fkey;
alter table public.attendance
  add constraint attendance_branch_tenant_fk
  foreign key (branch_id, business_id)
  references public.branches (id, business_id)
  on delete restrict;

drop policy if exists "owner manage members" on public.business_members;
create policy "owner add staff members" on public.business_members
for insert to authenticated
with check (
  private.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[])
  and role in ('MANAJER','KARYAWAN')
);
create policy "owner update staff members" on public.business_members
for update to authenticated
using (
  private.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[])
  and role in ('MANAJER','KARYAWAN')
)
with check (
  private.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[])
  and role in ('MANAJER','KARYAWAN')
);
create policy "owner remove staff members" on public.business_members
for delete to authenticated
using (
  private.has_business_role(business_id, array['OWNER BISNIS']::public.app_role[])
  and role in ('MANAJER','KARYAWAN')
);
