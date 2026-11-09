alter table public.products
  add constraint products_id_organization_unique unique (id, organization_id);
alter table public.shifts
  add constraint shifts_id_org_store_unique unique (id, organization_id, store_id);
alter table public.qr_orders
  add constraint qr_orders_id_org_store_unique unique (id, organization_id, store_id);

alter table public.memberships drop constraint if exists memberships_store_id_fkey;
alter table public.memberships add constraint memberships_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete set null (store_id);

alter table public.employee_invites drop constraint if exists employee_invites_store_id_fkey;
alter table public.employee_invites add constraint employee_invites_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete set null (store_id);

alter table public.store_inventory drop constraint if exists store_inventory_store_id_fkey;
alter table public.store_inventory add constraint store_inventory_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete cascade;
alter table public.store_inventory drop constraint if exists store_inventory_product_id_fkey;
alter table public.store_inventory add constraint store_inventory_product_tenant_fk
  foreign key (product_id, organization_id) references public.products(id, organization_id)
  on delete cascade;

alter table public.inventory_movements drop constraint if exists inventory_movements_store_id_fkey;
alter table public.inventory_movements add constraint inventory_movements_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete cascade;
alter table public.inventory_movements drop constraint if exists inventory_movements_product_id_fkey;
alter table public.inventory_movements add constraint inventory_movements_product_tenant_fk
  foreign key (product_id, organization_id) references public.products(id, organization_id)
  on delete restrict;

alter table public.sales drop constraint if exists sales_store_id_fkey;
alter table public.sales add constraint sales_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete cascade;
alter table public.sales drop constraint if exists sales_shift_id_fkey;
alter table public.sales add constraint sales_shift_tenant_fk
  foreign key (shift_id, organization_id, store_id) references public.shifts(id, organization_id, store_id)
  on delete restrict;

alter table public.shifts drop constraint if exists shifts_store_id_fkey;
alter table public.shifts add constraint shifts_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete cascade;

alter table public.attendance drop constraint if exists attendance_store_id_fkey;
alter table public.attendance add constraint attendance_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete cascade;

alter table public.schedules drop constraint if exists schedules_store_id_fkey;
alter table public.schedules add constraint schedules_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete cascade;

alter table public.qr_orders drop constraint if exists qr_orders_store_id_fkey;
alter table public.qr_orders add constraint qr_orders_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete cascade;

alter table public.payment_confirmations drop constraint if exists payment_confirmations_store_id_fkey;
alter table public.payment_confirmations add constraint payment_confirmations_store_tenant_fk
  foreign key (store_id, organization_id) references public.stores(id, organization_id)
  on delete cascade;
alter table public.payment_confirmations drop constraint if exists payment_confirmations_order_id_fkey;
alter table public.payment_confirmations add constraint payment_confirmations_order_tenant_fk
  foreign key (order_id, organization_id, store_id)
  references public.qr_orders(id, organization_id, store_id)
  on delete cascade;

create or replace function private.validate_sale_item_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sale_org uuid;
  v_product_org uuid;
begin
  select organization_id into v_sale_org from public.sales where id = new.sale_id;
  select organization_id into v_product_org from public.products where id = new.product_id;
  if v_sale_org is null or v_product_org is null or v_sale_org <> v_product_org then
    raise exception 'Produk dan transaksi harus berasal dari organisasi yang sama';
  end if;
  return new;
end;
$function$;

create or replace function private.validate_qr_order_item_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order_org uuid;
  v_product_org uuid;
begin
  select organization_id into v_order_org from public.qr_orders where id = new.order_id;
  select organization_id into v_product_org from public.products where id = new.product_id;
  if v_order_org is null or v_product_org is null or v_order_org <> v_product_org then
    raise exception 'Produk dan pesanan QR harus berasal dari organisasi yang sama';
  end if;
  return new;
end;
$function$;

revoke all on function private.validate_sale_item_tenant() from public, anon, authenticated;
revoke all on function private.validate_qr_order_item_tenant() from public, anon, authenticated;
drop trigger if exists validate_sale_item_tenant_before_write on public.sale_items;
create trigger validate_sale_item_tenant_before_write
before insert or update on public.sale_items
for each row execute procedure private.validate_sale_item_tenant();
drop trigger if exists validate_qr_order_item_tenant_before_write on public.qr_order_items;
create trigger validate_qr_order_item_tenant_before_write
before insert or update on public.qr_order_items
for each row execute procedure private.validate_qr_order_item_tenant();
