create or replace function public.get_public_order_queue(p_qr_slug text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_store public.stores%rowtype;
  v_orders jsonb;
begin
  select * into v_store
  from public.stores
  where qr_slug = p_qr_slug and is_active = true
  limit 1;

  if not found then raise exception 'Toko tidak ditemukan atau tidak aktif'; end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'order_number', q.order_number,
        'status', q.status,
        'created_at', q.created_at
      ) order by q.created_at desc
    ),
    '[]'::jsonb
  )
  into v_orders
  from (
    select order_number, status, created_at
    from public.qr_orders
    where store_id = v_store.id
      and created_at >= now() - interval '24 hours'
      and status not in ('cancelled','rejected')
    order by created_at desc
    limit 40
  ) q;

  return jsonb_build_object(
    'store_name', v_store.name,
    'orders', v_orders,
    'updated_at', now()
  );
end;
$function$;

revoke all on function public.get_public_order_queue(text) from public;
grant execute on function public.get_public_order_queue(text) to anon, authenticated;
