alter table public.customers
  add constraint customers_id_organization_unique unique (id, organization_id);
alter table public.customer_tabs
  add constraint customer_tabs_id_org_store_unique unique (id, organization_id, store_id);

alter table public.customer_tabs drop constraint if exists customer_tabs_customer_id_fkey;
alter table public.customer_tabs add constraint customer_tabs_customer_tenant_fk
  foreign key (customer_id, organization_id)
  references public.customers(id, organization_id)
  on delete set null (customer_id);

alter table public.customer_tab_payments drop constraint if exists customer_tab_payments_customer_tab_id_fkey;
alter table public.customer_tab_payments add constraint customer_tab_payments_tab_tenant_fk
  foreign key (customer_tab_id, organization_id, store_id)
  references public.customer_tabs(id, organization_id, store_id)
  on delete cascade;

create index if not exists customer_tabs_customer_tenant_idx on public.customer_tabs(customer_id, organization_id);
create index if not exists customer_tab_payments_tab_tenant_idx on public.customer_tab_payments(customer_tab_id, organization_id, store_id);
