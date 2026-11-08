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
