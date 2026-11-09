drop policy if exists public_upload_qr_payment_proof on storage.objects;
create policy public_upload_qr_payment_proof on storage.objects
for insert to anon
with check (
  bucket_id = 'payment-proofs'
  and (storage.foldername(name))[1] is not null
  and (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
  and exists (
    select 1
    from public.qr_orders o
    join public.stores s on s.id = o.store_id and s.organization_id = o.organization_id
    where o.id = ((storage.foldername(name))[2])::uuid
      and s.qr_slug = (storage.foldername(name))[1]
      and s.is_active = true
      and o.status = 'awaiting_payment_confirmation'
  )
);

drop policy if exists managers_read_qr_payment_proofs on storage.objects;
create policy managers_read_qr_payment_proofs on storage.objects
for select to authenticated
using (
  bucket_id = 'payment-proofs'
  and (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
  and exists (
    select 1
    from public.qr_orders o
    join public.stores s on s.id = o.store_id and s.organization_id = o.organization_id
    where o.id = ((storage.foldername(name))[2])::uuid
      and s.qr_slug = (storage.foldername(name))[1]
      and private.can_access_store(s.id)
  )
);

grant execute on function public.attach_public_qr_payment_proof(text,uuid,text) to anon, authenticated;
