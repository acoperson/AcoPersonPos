-- Retire the old RPC that created a Starter business without the new approval rules.
revoke all on function public.create_business(text,text) from public,anon,authenticated;
