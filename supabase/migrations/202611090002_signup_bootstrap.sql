-- Bootstrap a profile, business, primary branch and free plan for every new owner.
-- This keeps registration email-confirmation policy in Supabase Auth settings,
-- while ensuring the database creates a tenant only once the auth user exists.

create or replace function public.bootstrap_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_business_id uuid;
  business_label text;
  base_slug text;
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(coalesce(new.email, 'owner'), '@', 1))
  )
  on conflict (id) do nothing;

  business_label := coalesce(nullif(new.raw_user_meta_data ->> 'business_name', ''), 'Bisnis ' || coalesce(split_part(new.email, '@', 1), 'Baru'));
  base_slug := lower(regexp_replace(business_label, '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(replace(new.id::text, '-', ''), 1, 8);

  insert into public.businesses (owner_id, name, slug)
  values (new.id, business_label, base_slug)
  returning id into new_business_id;

  insert into public.branches (business_id, name, address)
  values (new_business_id, 'Toko Utama', null);

  insert into public.business_members (business_id, user_id, role, is_active)
  values (new_business_id, new.id, 'OWNER BISNIS', true)
  on conflict (business_id, user_id) do nothing;

  insert into public.business_subscriptions (business_id, plan_id, starts_at, ends_at, is_active)
  select new_business_id, p.id, now(), null, true
  from public.plans p
  where p.code = 'FREE'
  limit 1;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_acopos on auth.users;
create trigger on_auth_user_created_acopos
after insert on auth.users
for each row execute procedure public.bootstrap_new_user();

-- Do not require email verification if that is the intended onboarding policy:
-- in Supabase Dashboard > Authentication > Providers > Email, turn OFF
-- "Confirm email". This is a project-level Auth setting, not a safe client-side toggle.
