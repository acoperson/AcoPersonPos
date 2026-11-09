create index if not exists business_applications_organization_idx on public.business_applications(organization_id);
create index if not exists business_applications_reviewed_by_idx on public.business_applications(reviewed_by);

drop policy if exists profiles_read_org_members on public.profiles;
create policy profiles_read_org_members on public.profiles
for select to authenticated
using (
  id = (select auth.uid())
  or exists (
    select 1
    from public.memberships mine
    join public.memberships theirs on theirs.organization_id = mine.organization_id
    where mine.user_id = (select auth.uid())
      and mine.role = any(array['owner','admin']::text[])
      and theirs.user_id = profiles.id
  )
  or exists (
    select 1
    from public.memberships mine
    join public.memberships theirs on theirs.organization_id = mine.organization_id
    where mine.user_id = (select auth.uid())
      and mine.role = 'manager'
      and (mine.store_id is null or mine.store_id = theirs.store_id)
      and theirs.user_id = profiles.id
  )
);

drop policy if exists memberships_select_org on public.memberships;
create policy memberships_select_org on public.memberships
for select to authenticated
using (
  user_id = (select auth.uid())
  or private.has_org_role(organization_id, array['owner','admin'])
  or (store_id is not null and private.can_access_store(store_id))
);

drop policy if exists shifts_insert_assigned_cashiers on public.shifts;
create policy shifts_insert_assigned_cashiers on public.shifts
for insert to authenticated
with check (
  private.can_access_store(store_id)
  and cashier_user_id = (select auth.uid())
  and private.has_org_role(organization_id, array['owner','admin','manager','cashier'])
);

drop policy if exists shifts_update_assigned_self_or_managers on public.shifts;
create policy shifts_update_assigned_self_or_managers on public.shifts
for update to authenticated
using (
  private.can_access_store(store_id)
  and (cashier_user_id = (select auth.uid()) or private.has_org_role(organization_id, array['owner','admin','manager']))
)
with check (
  private.can_access_store(store_id)
  and (cashier_user_id = (select auth.uid()) or private.has_org_role(organization_id, array['owner','admin','manager']))
);

drop policy if exists sales_update_assigned_owner_or_cashier on public.sales;
create policy sales_update_assigned_owner_or_cashier on public.sales
for update to authenticated
using (
  private.can_access_store(store_id)
  and (private.has_org_role(organization_id, array['owner','admin','manager']) or cashier_user_id = (select auth.uid()))
)
with check (
  private.can_access_store(store_id)
  and (private.has_org_role(organization_id, array['owner','admin','manager']) or cashier_user_id = (select auth.uid()))
);

drop policy if exists attendance_insert_assigned on public.attendance;
create policy attendance_insert_assigned on public.attendance
for insert to authenticated
with check (
  private.can_access_store(store_id)
  and (employee_user_id = (select auth.uid()) or private.has_org_role(organization_id, array['owner','admin','manager']))
);

drop policy if exists attendance_read_assigned on public.attendance;
create policy attendance_read_assigned on public.attendance
for select to authenticated
using (
  private.can_access_store(store_id)
  and (employee_user_id = (select auth.uid()) or private.has_org_role(organization_id, array['owner','admin','manager']))
);

drop policy if exists attendance_update_assigned on public.attendance;
create policy attendance_update_assigned on public.attendance
for update to authenticated
using (
  private.can_access_store(store_id)
  and (employee_user_id = (select auth.uid()) or private.has_org_role(organization_id, array['owner','admin','manager']))
)
with check (
  private.can_access_store(store_id)
  and (employee_user_id = (select auth.uid()) or private.has_org_role(organization_id, array['owner','admin','manager']))
);

drop policy if exists platform_admins_read_self on public.platform_admins;
create policy platform_admins_read_self on public.platform_admins
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists business_applications_read_own_or_admin on public.business_applications;
create policy business_applications_read_own_or_admin on public.business_applications
for select to authenticated
using (user_id = (select auth.uid()) or public.is_platform_admin());
