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
