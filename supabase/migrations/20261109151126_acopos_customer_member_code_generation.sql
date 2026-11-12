create or replace function private.assign_customer_member_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.member_code is null or length(trim(new.member_code)) = 0 then
    new.member_code := 'ACO-' || upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 10));
  end if;
  return new;
end;
$function$;

revoke all on function private.assign_customer_member_code() from public, anon, authenticated;
drop trigger if exists assign_customer_member_code_before_insert on public.customers;
create trigger assign_customer_member_code_before_insert
before insert on public.customers
for each row execute procedure private.assign_customer_member_code();
