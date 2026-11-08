create or replace function public.adjust_store_stock(
  p_store_id uuid,
  p_product_id uuid,
  p_delta numeric,
  p_note text default null
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_org_id uuid;
  v_quantity numeric;
  v_threshold numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_delta is null or p_delta = 0 then
    raise exception 'Perubahan stok harus lebih dari nol';
  end if;

  select s.organization_id
    into v_org_id
  from public.stores s
  where s.id = p_store_id and s.is_active = true;

  if v_org_id is null
     or not private.can_access_store(p_store_id)
     or not private.has_org_role(v_org_id, array['owner','admin','manager']) then
    raise exception 'Akses pengelolaan stok ditolak';
  end if;

  select p.low_stock_threshold
    into v_threshold
  from public.products p
  where p.id = p_product_id
    and p.organization_id = v_org_id;

  if not found then
    raise exception 'Produk tidak ditemukan pada bisnis ini';
  end if;

  insert into public.store_inventory(
    organization_id, store_id, product_id, quantity, low_stock_threshold
  )
  values (v_org_id, p_store_id, p_product_id, 0, coalesce(v_threshold, 0))
  on conflict (store_id, product_id) do nothing;

  select si.quantity
    into v_quantity
  from public.store_inventory si
  where si.store_id = p_store_id
    and si.product_id = p_product_id
  for update;

  if v_quantity + p_delta < 0 then
    raise exception 'Stok tidak mencukupi';
  end if;

  update public.store_inventory
  set quantity = v_quantity + p_delta,
      updated_at = now()
  where store_id = p_store_id
    and product_id = p_product_id;

  insert into public.inventory_movements(
    organization_id, store_id, product_id, movement_type,
    quantity, note, created_by
  )
  values (
    v_org_id, p_store_id, p_product_id,
    case when p_delta > 0 then 'in' else 'out' end,
    abs(p_delta), nullif(trim(coalesce(p_note, '')), ''), auth.uid()
  );

  return jsonb_build_object(
    'store_id', p_store_id,
    'product_id', p_product_id,
    'quantity', v_quantity + p_delta
  );
end;
$function$;

revoke all on function public.adjust_store_stock(uuid,uuid,numeric,text) from public;
revoke all on function public.adjust_store_stock(uuid,uuid,numeric,text) from anon;
grant execute on function public.adjust_store_stock(uuid,uuid,numeric,text) to authenticated;
