-- Fix QR customer proof upload/read policies.
-- The previous policies accidentally used stores.name instead of storage.objects.name,
-- so the object path was never checked against the QR slug and order id.
drop policy if exists public_upload_qr_payment_proof on storage.objects;
create policy public_upload_qr_payment_proof
on storage.objects
for insert
to anon, authenticated
with check (
  bucket_id = 'payment-proofs'
  and (storage.foldername(storage.objects.name))[1] is not null
  and (storage.foldername(storage.objects.name))[2] ~* '^[0-9a-f-]{36}$'
  and exists (
    select 1
    from public.qr_orders o
    join public.stores s on s.id = o.store_id
    where o.id::text = (storage.foldername(storage.objects.name))[2]
      and s.qr_slug = (storage.foldername(storage.objects.name))[1]
      and s.is_active = true
      and o.status = 'awaiting_payment_confirmation'
  )
);

drop policy if exists managers_read_qr_payment_proofs on storage.objects;
create policy managers_read_qr_payment_proofs
on storage.objects
for select
to authenticated
using (
  bucket_id = 'payment-proofs'
  and (storage.foldername(storage.objects.name))[1] is not null
  and (storage.foldername(storage.objects.name))[2] ~* '^[0-9a-f-]{36}$'
  and exists (
    select 1
    from public.stores s
    where s.qr_slug = (storage.foldername(storage.objects.name))[1]
      and private.can_access_store(s.id)
  )
);

-- Claiming an employee invite must also select the employee's active workspace.
-- Without this, the membership is created but the frontend still sees no active organization.
create or replace function public.claim_employee_invites()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_email text;
  v_count integer := 0;
  v_active_org uuid;
  r record;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select lower(u.email) into v_email
  from auth.users u
  where u.id = auth.uid();

  if v_email is null then
    raise exception 'Akun tidak memiliki email';
  end if;

  for r in
    select *
    from public.employee_invites
    where lower(email) = v_email
      and status = 'pending'
    order by created_at asc
  loop
    insert into public.memberships(organization_id,user_id,role,store_id)
    values(r.organization_id,auth.uid(),r.role,r.store_id)
    on conflict(organization_id,user_id)
    do update set role=excluded.role,store_id=excluded.store_id;

    update public.employee_invites
    set status='accepted'
    where id=r.id;

    if v_active_org is null then
      v_active_org := r.organization_id;
    end if;

    v_count := v_count + 1;
  end loop;

  if v_active_org is not null then
    insert into public.profiles(id,active_organization_id)
    values(auth.uid(),v_active_org)
    on conflict(id) do update
      set active_organization_id = coalesce(public.profiles.active_organization_id,excluded.active_organization_id),
          updated_at = now();
  end if;

  return v_count;
end;
$function$;

revoke all on function public.claim_employee_invites() from public, anon;
grant execute on function public.claim_employee_invites() to authenticated;

-- Prevent duplicate open shifts/check-ins during rapid or concurrent requests.
create unique index if not exists shifts_one_open_per_cashier_store_idx
  on public.shifts(store_id,cashier_user_id)
  where status = 'open';

create unique index if not exists attendance_one_open_per_employee_store_idx
  on public.attendance(store_id,employee_user_id)
  where clock_out is null;

-- Enforce one pending application per user/business to close concurrent-submit races.
create unique index if not exists business_applications_one_pending_new_business_per_user_idx
  on public.business_applications(user_id)
  where application_type = 'new_business' and status = 'pending';

create unique index if not exists business_applications_one_pending_upgrade_per_org_idx
  on public.business_applications(organization_id)
  where application_type = 'upgrade' and status = 'pending';

-- Reject duplicate product rows so the same stock is not validated twice and deducted twice.
CREATE OR REPLACE FUNCTION public.complete_pos_sale(p_store_id uuid, p_shift_id uuid, p_items jsonb, p_discount numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_org uuid;v_receipt text;v_sale uuid;v_subtotal numeric(14,2):=0;v_discount numeric(14,2);v_item jsonb;v_product public.products%rowtype;v_qty numeric;v_price numeric;v_line numeric;v_stock numeric;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>100 then raise exception 'Keranjang tidak valid'; end if;
 if exists (
  select 1
  from jsonb_array_elements(p_items) as line(item)
  group by lower(coalesce(line.item->>'product_id',''))
  having count(*) > 1
 ) then
  raise exception 'Produk duplikat tidak diperbolehkan dalam keranjang';
 end if;

 select organization_id into v_org from public.stores where id=p_store_id and is_active=true;
 if v_org is null or not private.can_access_store(p_store_id) or not private.has_org_role(v_org,array['owner','admin','manager','cashier']) then raise exception 'Akses toko ditolak'; end if;
 if not exists(select 1 from public.shifts where id=p_shift_id and store_id=p_store_id and status='open' and (cashier_user_id=auth.uid() or (private.has_org_role(v_org,array['owner','admin','manager']) and private.can_access_store(p_store_id)))) then raise exception 'Buka shift kasir sebelum transaksi'; end if;
 for v_item in select * from jsonb_array_elements(p_items) loop
  select * into v_product from public.products where id=(v_item->>'product_id')::uuid and organization_id=v_org and is_available=true;
  if not found then raise exception 'Produk tidak tersedia'; end if;
  v_qty:=(v_item->>'quantity')::numeric;
  if v_qty<=0 then raise exception 'Jumlah produk tidak valid'; end if;
  select quantity into v_stock from public.store_inventory where store_id=p_store_id and product_id=v_product.id for update;
  if not found or v_qty>v_stock then raise exception 'Stok tidak mencukupi untuk %',v_product.name; end if;
  v_subtotal:=v_subtotal+(v_qty*v_product.selling_price);
 end loop;
 v_discount:=greatest(0,coalesce(p_discount,0));if v_discount>v_subtotal then raise exception 'Diskon melebihi subtotal'; end if;
 v_receipt:='AC-'||upper(substr(encode(gen_random_bytes(6),'hex'),1,10));
 insert into public.sales(organization_id,store_id,shift_id,cashier_user_id,receipt_number,subtotal,discount,tax,total,payment_method,payment_status,note)
 values(v_org,p_store_id,p_shift_id,auth.uid(),v_receipt,v_subtotal,v_discount,0,v_subtotal-v_discount,p_payment_method,'paid',p_note) returning id into v_sale;
 for v_item in select * from jsonb_array_elements(p_items) loop
  select * into v_product from public.products where id=(v_item->>'product_id')::uuid and organization_id=v_org;
  v_qty:=(v_item->>'quantity')::numeric;v_price:=v_product.selling_price;v_line:=v_qty*v_price;
  insert into public.sale_items(sale_id,product_id,product_name,quantity,unit_price,discount,line_total) values(v_sale,v_product.id,v_product.name,v_qty,v_price,0,v_line);
  update public.store_inventory set quantity=quantity-v_qty,updated_at=now() where store_id=p_store_id and product_id=v_product.id;
  insert into public.inventory_movements(organization_id,store_id,product_id,movement_type,quantity,note,created_by) values(v_org,p_store_id,v_product.id,'out',v_qty,'Penjualan '||v_receipt,auth.uid());
 end loop;
 return jsonb_build_object('sale_id',v_sale,'receipt_number',v_receipt,'subtotal',v_subtotal,'discount',v_discount,'total',v_subtotal-v_discount);
end; $function$


CREATE OR REPLACE FUNCTION public.submit_public_qr_order(p_qr_slug text, p_customer_name text, p_customer_note text, p_items jsonb, p_proof_image_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_store public.stores%rowtype; v_order_id uuid; v_order_number text; v_subtotal numeric(14,2):=0; v_item jsonb; v_product public.products%rowtype; v_qty numeric; v_price numeric; v_line numeric; v_stock numeric;
begin
 if length(trim(coalesce(p_customer_name,'')))<2 then raise exception 'Nama pelanggan minimal 2 karakter'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>50 then raise exception 'Keranjang pesanan tidak valid'; end if;
 if exists (
  select 1
  from jsonb_array_elements(p_items) as line(item)
  group by lower(coalesce(line.item->>'product_id',''))
  having count(*) > 1
 ) then
  raise exception 'Produk duplikat tidak diperbolehkan dalam keranjang';
 end if;

 select * into v_store from public.stores where qr_slug=p_qr_slug and is_active=true limit 1;
 if not found then raise exception 'Toko tidak ditemukan atau tidak aktif'; end if;
 for v_item in select * from jsonb_array_elements(p_items) loop
  select p.* into v_product from public.products p join public.store_inventory si on si.product_id=p.id and si.store_id=v_store.id
   where p.id=(v_item->>'product_id')::uuid and p.organization_id=v_store.organization_id and p.is_available=true for update of p;
  if not found then raise exception 'Salah satu produk tidak tersedia di cabang ini'; end if;
  select quantity into v_stock from public.store_inventory where product_id=v_product.id and store_id=v_store.id for update;
  v_qty:=(v_item->>'quantity')::numeric;
  if v_qty<=0 or v_qty>1000 or v_qty>v_stock then raise exception 'Stok tidak mencukupi untuk %',v_product.name; end if;
  v_price:=v_product.selling_price;v_line:=v_qty*v_price;v_subtotal:=v_subtotal+v_line;
 end loop;
 v_order_number:='QR-'||upper(substr(encode(gen_random_bytes(4),'hex'),1,8));
 insert into public.qr_orders(organization_id,store_id,customer_name,customer_note,order_number,status,subtotal,total)
 values(v_store.organization_id,v_store.id,trim(p_customer_name),nullif(trim(coalesce(p_customer_note,'')),''),v_order_number,'awaiting_payment_confirmation',v_subtotal,v_subtotal)
 returning id into v_order_id;
 for v_item in select * from jsonb_array_elements(p_items) loop
  select p.* into v_product from public.products p where p.id=(v_item->>'product_id')::uuid and p.organization_id=v_store.organization_id;
  v_qty:=(v_item->>'quantity')::numeric;v_price:=v_product.selling_price;v_line:=v_qty*v_price;
  insert into public.qr_order_items(order_id,product_id,product_name,quantity,unit_price,line_total,note)
  values(v_order_id,v_product.id,v_product.name,v_qty,v_price,v_line,nullif(trim(coalesce(v_item->>'note','')),''));
  update public.store_inventory set quantity=quantity-v_qty,updated_at=now() where store_id=v_store.id and product_id=v_product.id;
  insert into public.inventory_movements(organization_id,store_id,product_id,movement_type,quantity,note)
  values(v_store.organization_id,v_store.id,v_product.id,'out',v_qty,'Pesanan QR '||v_order_number);
 end loop;
 return jsonb_build_object('order_id',v_order_id,'order_number',v_order_number,'status','awaiting_payment_confirmation','total',v_subtotal);
end; $function$

