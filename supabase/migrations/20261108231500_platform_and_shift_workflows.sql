-- ACOPOS platform administration and cashier attendance workflows.
-- Applied to the connected Supabase project on 2026-11-08.

create or replace function public.platform_admin_overview()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'Platform admin access required';
  end if;

  select jsonb_build_object(
    'stats', jsonb_build_object(
      'organizations', (select count(*) from public.organizations),
      'stores', (select count(*) from public.stores),
      'users', (select count(*) from auth.users),
      'sales', (select count(*) from public.sales),
      'qr_orders', (select count(*) from public.qr_orders),
      'subscriptions', (select count(*) from public.subscriptions),
      'active_subscriptions', (select count(*) from public.subscriptions where status = 'active')
    ),
    'organizations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', o.id, 'name', o.name, 'slug', o.slug, 'owner_email', u.email,
          'created_at', o.created_at,
          'store_count', (select count(*) from public.stores s where s.organization_id = o.id),
          'member_count', (select count(*) from public.memberships m where m.organization_id = o.id),
          'plan_name', (select sub.plan_name from public.subscriptions sub where sub.organization_id = o.id limit 1),
          'subscription_status', (select sub.status from public.subscriptions sub where sub.organization_id = o.id limit 1)
        ) order by o.created_at desc
      )
      from public.organizations o
      left join auth.users u on u.id = o.owner_user_id
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', recent.id, 'email', recent.email, 'full_name', recent.full_name,
        'created_at', recent.created_at, 'last_sign_in_at', recent.last_sign_in_at
      ) order by recent.created_at desc)
      from (
        select u.id, u.email, p.full_name, u.created_at, u.last_sign_in_at
        from auth.users u
        left join public.profiles p on p.id = u.id
        order by u.created_at desc
        limit 100
      ) recent
    ), '[]'::jsonb),
    'subscriptions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organization_id', o.id, 'organization_name', o.name, 'owner_email', u.email,
        'plan_name', sub.plan_name, 'status', sub.status,
        'starts_at', sub.starts_at, 'ends_at', sub.ends_at
      ) order by sub.created_at desc)
      from public.subscriptions sub
      join public.organizations o on o.id = sub.organization_id
      left join auth.users u on u.id = o.owner_user_id
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$function$;

revoke all on function public.platform_admin_overview() from public;
revoke all on function public.platform_admin_overview() from anon;
grant execute on function public.platform_admin_overview() to authenticated;

create or replace function public.open_cashier_shift(p_store_id uuid, p_opening_cash numeric default 0)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_org_id uuid;
  v_shift_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce(p_opening_cash, 0) < 0 then raise exception 'Modal awal tidak boleh negatif'; end if;

  select s.organization_id into v_org_id
  from public.stores s where s.id = p_store_id and s.is_active = true;

  if v_org_id is null
     or not private.can_access_store(p_store_id)
     or not private.has_org_role(v_org_id, array['owner','admin','manager','cashier']) then
    raise exception 'Akses toko ditolak';
  end if;

  if exists (
    select 1 from public.shifts sh
    where sh.store_id = p_store_id and sh.cashier_user_id = auth.uid() and sh.status = 'open'
  ) then raise exception 'Masih ada shift kasir yang terbuka'; end if;

  if not exists (
    select 1 from public.attendance a
    where a.store_id = p_store_id and a.employee_user_id = auth.uid() and a.clock_out is null
  ) then
    insert into public.attendance(organization_id, store_id, employee_user_id, status)
    values (v_org_id, p_store_id, auth.uid(), 'present');
  end if;

  insert into public.shifts(organization_id, store_id, cashier_user_id, opening_cash, status)
  values (v_org_id, p_store_id, auth.uid(), coalesce(p_opening_cash,0), 'open')
  returning id into v_shift_id;
  return v_shift_id;
end;
$function$;

create or replace function public.close_cashier_shift(p_shift_id uuid, p_closing_cash numeric)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_shift public.shifts%rowtype;
  v_cash_sales numeric(14,2);
  v_expected_cash numeric(14,2);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce(p_closing_cash, -1) < 0 then raise exception 'Kas akhir tidak boleh negatif'; end if;

  select * into v_shift from public.shifts where id = p_shift_id for update;
  if not found then raise exception 'Shift tidak ditemukan'; end if;
  if v_shift.status <> 'open' then raise exception 'Shift sudah ditutup'; end if;
  if not private.can_access_store(v_shift.store_id)
     or (v_shift.cashier_user_id <> auth.uid()
         and not private.has_org_role(v_shift.organization_id, array['owner','admin','manager'])) then
    raise exception 'Akses shift ditolak';
  end if;

  select coalesce(sum(s.total),0) into v_cash_sales
  from public.sales s
  where s.shift_id = v_shift.id and s.payment_method = 'cash' and s.payment_status = 'paid';

  v_expected_cash := v_shift.opening_cash + v_cash_sales;
  update public.shifts
  set closing_cash = p_closing_cash, expected_cash = v_expected_cash, status = 'closed', closed_at = now()
  where id = v_shift.id;

  update public.attendance
  set clock_out = now()
  where store_id = v_shift.store_id and employee_user_id = v_shift.cashier_user_id and clock_out is null;

  return jsonb_build_object(
    'shift_id', v_shift.id, 'opening_cash', v_shift.opening_cash,
    'cash_sales', v_cash_sales, 'expected_cash', v_expected_cash,
    'closing_cash', p_closing_cash, 'closed_at', now()
  );
end;
$function$;

revoke all on function public.open_cashier_shift(uuid,numeric) from public;
revoke all on function public.open_cashier_shift(uuid,numeric) from anon;
grant execute on function public.open_cashier_shift(uuid,numeric) to authenticated;

revoke all on function public.close_cashier_shift(uuid,numeric) from public;
revoke all on function public.close_cashier_shift(uuid,numeric) from anon;
grant execute on function public.close_cashier_shift(uuid,numeric) to authenticated;


create or replace function public.review_qr_payment(p_order_id uuid, p_approved boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.qr_orders%rowtype;
  v_confirmation_id uuid;
  v_next_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_order from public.qr_orders where id = p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if v_order.status <> 'awaiting_payment_confirmation' then
    raise exception 'Pesanan tidak sedang menunggu konfirmasi pembayaran';
  end if;
  if not private.can_access_store(v_order.store_id)
     or not private.has_org_role(v_order.organization_id, array['owner','admin','manager','cashier']) then
    raise exception 'Akses konfirmasi pembayaran ditolak';
  end if;

  select pc.id into v_confirmation_id
  from public.payment_confirmations pc
  where pc.order_id = p_order_id
  order by pc.created_at desc
  limit 1
  for update;

  v_next_status := case when p_approved then 'approved' else 'rejected' end;
  if v_confirmation_id is null then
    insert into public.payment_confirmations(
      organization_id, store_id, order_id, status, reviewed_by, reviewed_at
    ) values (
      v_order.organization_id, v_order.store_id, v_order.id,
      v_next_status, auth.uid(), now()
    );
  else
    update public.payment_confirmations
    set status = v_next_status, reviewed_by = auth.uid(), reviewed_at = now()
    where id = v_confirmation_id;
  end if;

  if p_approved then
    update public.qr_orders set status = 'payment_confirmed' where id = p_order_id;
  end if;

  return jsonb_build_object('order_id', p_order_id, 'payment_status', v_next_status,
    'order_status', case when p_approved then 'payment_confirmed' else 'awaiting_payment_confirmation' end);
end;
$function$;

create or replace function public.update_qr_order_status(p_order_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.qr_orders%rowtype;
  v_item record;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_status not in ('preparing','ready','completed','cancelled') then
    raise exception 'Status pesanan tidak valid';
  end if;

  select * into v_order from public.qr_orders where id = p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if not private.can_access_store(v_order.store_id)
     or not private.has_org_role(v_order.organization_id, array['owner','admin','manager','cashier']) then
    raise exception 'Akses pesanan ditolak';
  end if;

  if p_status = 'preparing' and v_order.status <> 'payment_confirmed' then
    raise exception 'Pembayaran harus dikonfirmasi sebelum pesanan diproses';
  elsif p_status = 'ready' and v_order.status <> 'preparing' then
    raise exception 'Pesanan harus diproses sebelum ditandai siap';
  elsif p_status = 'completed' and v_order.status <> 'ready' then
    raise exception 'Pesanan harus siap sebelum diselesaikan';
  elsif p_status = 'cancelled' and v_order.status in ('completed','cancelled') then
    raise exception 'Pesanan yang sudah selesai atau dibatalkan tidak dapat dibatalkan lagi';
  end if;

  if p_status = 'cancelled' then
    for v_item in
      select qi.product_id, sum(qi.quantity) as quantity
      from public.qr_order_items qi
      where qi.order_id = p_order_id and qi.product_id is not null
      group by qi.product_id
    loop
      insert into public.store_inventory(
        organization_id, store_id, product_id, quantity, low_stock_threshold
      )
      select v_order.organization_id, v_order.store_id, v_item.product_id,
             v_item.quantity, coalesce(p.low_stock_threshold,0)
      from public.products p
      where p.id = v_item.product_id
      on conflict (store_id, product_id)
      do update set quantity = public.store_inventory.quantity + excluded.quantity,
                    updated_at = now();

      insert into public.inventory_movements(
        organization_id, store_id, product_id, movement_type, quantity, note, created_by
      ) values (
        v_order.organization_id, v_order.store_id, v_item.product_id, 'in',
        v_item.quantity, 'Restock pembatalan pesanan QR ' || v_order.order_number, auth.uid()
      );
    end loop;
  end if;

  update public.qr_orders set status = p_status where id = p_order_id;
  return jsonb_build_object('order_id', p_order_id, 'status', p_status);
end;
$function$;

revoke all on function public.review_qr_payment(uuid,boolean) from public;
revoke all on function public.review_qr_payment(uuid,boolean) from anon;
grant execute on function public.review_qr_payment(uuid,boolean) to authenticated;

revoke all on function public.update_qr_order_status(uuid,text) from public;
revoke all on function public.update_qr_order_status(uuid,text) from anon;
grant execute on function public.update_qr_order_status(uuid,text) to authenticated;
