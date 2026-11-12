create index if not exists activation_codes_issued_by_idx on public.activation_codes(issued_by);
create index if not exists activation_codes_org_idx on public.activation_codes(organization_id);
create index if not exists activation_codes_plan_code_idx on public.activation_codes(plan_code);
create index if not exists activation_codes_redeemed_by_idx on public.activation_codes(redeemed_by);

create index if not exists attendance_store_tenant_idx on public.attendance(store_id, organization_id);
create index if not exists customer_tab_payments_org_idx on public.customer_tab_payments(organization_id);
create index if not exists customer_tab_payments_received_by_idx on public.customer_tab_payments(received_by);
create index if not exists customer_tab_payments_store_tenant_idx on public.customer_tab_payments(store_id, organization_id);
create index if not exists customer_tabs_created_by_idx on public.customer_tabs(created_by);
create index if not exists customer_tabs_customer_idx on public.customer_tabs(customer_id);
create index if not exists customer_tabs_org_idx on public.customer_tabs(organization_id);
create index if not exists customer_tabs_store_tenant_idx on public.customer_tabs(store_id, organization_id);
create index if not exists customers_store_tenant_idx on public.customers(store_id, organization_id);

create index if not exists employee_invites_invited_by_idx on public.employee_invites(invited_by);
create index if not exists employee_invites_store_tenant_idx on public.employee_invites(store_id, organization_id);

create index if not exists inventory_movements_created_by_idx on public.inventory_movements(created_by);
create index if not exists inventory_movements_product_tenant_idx on public.inventory_movements(product_id, organization_id);
create index if not exists inventory_movements_store_tenant_idx on public.inventory_movements(store_id, organization_id);

create index if not exists memberships_store_tenant_idx on public.memberships(store_id, organization_id);
create index if not exists payment_confirmations_order_tenant_idx on public.payment_confirmations(order_id, organization_id, store_id);
create index if not exists payment_confirmations_reviewed_by_idx on public.payment_confirmations(reviewed_by);
create index if not exists payment_confirmations_store_tenant_idx on public.payment_confirmations(store_id, organization_id);

create index if not exists qr_orders_store_tenant_idx on public.qr_orders(store_id, organization_id);
create index if not exists reservations_created_by_idx on public.reservations(created_by);
create index if not exists reservations_org_idx on public.reservations(organization_id);
create index if not exists reservations_store_tenant_idx on public.reservations(store_id, organization_id);

create index if not exists sale_items_sale_id_idx on public.sale_items(sale_id);
create index if not exists sales_shift_tenant_idx on public.sales(shift_id, organization_id, store_id);
create index if not exists sales_store_tenant_idx on public.sales(store_id, organization_id);
create index if not exists schedules_store_tenant_idx on public.schedules(store_id, organization_id);
create index if not exists shifts_store_tenant_idx on public.shifts(store_id, organization_id);
create index if not exists store_inventory_product_tenant_idx on public.store_inventory(product_id, organization_id);
create index if not exists store_inventory_store_tenant_idx on public.store_inventory(store_id, organization_id);
