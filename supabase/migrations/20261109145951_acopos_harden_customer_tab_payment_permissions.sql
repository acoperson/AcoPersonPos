drop policy if exists customer_tabs_update_assigned on public.customer_tabs;
create policy customer_tabs_update_assigned on public.customer_tabs
for update to authenticated
using (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager']))
with check (private.can_access_store(store_id) and private.has_org_role(organization_id, array['owner','admin','manager']));

drop policy if exists customer_tab_payments_insert_assigned on public.customer_tab_payments;
revoke insert, update, delete on public.customer_tab_payments from authenticated;
grant select on public.customer_tab_payments to authenticated;
