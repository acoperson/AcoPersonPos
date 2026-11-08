-- ACOPOS business registration, free activation, and paid-plan approval workflow.
create table if not exists public.business_applications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 application_type text not null check (application_type in ('new_business','upgrade')),
 organization_id uuid references public.organizations(id) on delete cascade,
 business_name text not null,
 store_name text,
 requested_plan text not null check (requested_plan in ('free','business')),
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 applicant_note text,
 admin_note text,
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint business_application_target_check check (
  (application_type='new_business' and organization_id is null and store_name is not null)
  or (application_type='upgrade' and organization_id is not null)
 )
);
create index if not exists business_applications_user_status_idx on public.business_applications(user_id,status);
create index if not exists business_applications_status_created_idx on public.business_applications(status,created_at desc);
alter table public.business_applications enable row level security;
drop policy if exists business_applications_read_own_or_admin on public.business_applications;
create policy business_applications_read_own_or_admin on public.business_applications
 for select to authenticated using (user_id=auth.uid() or public.is_platform_admin());
revoke all on public.business_applications from anon, public;
grant select on public.business_applications to authenticated;

create table if not exists public.subscription_plans (
 code text primary key,
 name text not null,
 price_idr numeric(14,2),
 billing_period text,
 is_paid boolean not null default false,
 is_active boolean not null default true,
 description text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.subscription_plans enable row level security;
drop policy if exists subscription_plans_read_active on public.subscription_plans;
create policy subscription_plans_read_active on public.subscription_plans
 for select to anon, authenticated using (is_active=true);
revoke all on public.subscription_plans from public;
grant select on public.subscription_plans to anon, authenticated;
insert into public.subscription_plans(code,name,price_idr,billing_period,is_paid,description)
values
 ('free','Gratis',0,'unlimited',false,'Paket gratis ACOPOS yang aktif otomatis setelah pendaftaran bisnis.'),
 ('business','Bisnis',null,null,true,'Paket berbayar yang memerlukan persetujuan Platform Owner.')
on conflict (code) do update set name=excluded.name,is_paid=excluded.is_paid,description=excluded.description,updated_at=now();

create or replace function public.submit_business_application(p_business_name text,p_store_name text,p_requested_plan text default 'free',p_applicant_note text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=auth.uid(); v_org uuid; v_app uuid;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if length(trim(coalesce(p_business_name,'')))<2 or length(trim(coalesce(p_store_name,'')))<2 then raise exception 'Nama bisnis dan toko minimal 2 karakter'; end if;
 if p_requested_plan not in ('free','business') then raise exception 'Paket tidak valid'; end if;
 if exists(select 1 from public.memberships where user_id=v_user) then raise exception 'Akun ini sudah memiliki bisnis. Gunakan menu upgrade paket.'; end if;
 if exists(select 1 from public.business_applications where user_id=v_user and status='pending' and application_type='new_business') then raise exception 'Pengajuan bisnis kamu masih menunggu persetujuan.'; end if;
 if p_requested_plan='free' then
  insert into public.organizations(name,owner_user_id) values(trim(p_business_name),v_user) returning id into v_org;
  insert into public.memberships(organization_id,user_id,role) values(v_org,v_user,'owner');
  insert into public.stores(organization_id,name,code) values(v_org,trim(p_store_name),'STORE-001');
  insert into public.subscriptions(organization_id,plan_name,status,starts_at,ends_at) values(v_org,'free','active',now(),null);
  insert into public.profiles(id,active_organization_id) values(v_user,v_org)
   on conflict(id) do update set active_organization_id=excluded.active_organization_id,updated_at=now();
  return jsonb_build_object('result','activated','organization_id',v_org,'plan','free','status','active');
 end if;
 insert into public.business_applications(user_id,application_type,business_name,store_name,requested_plan,status,applicant_note)
 values(v_user,'new_business',trim(p_business_name),trim(p_store_name),'business','pending',nullif(trim(coalesce(p_applicant_note,'')),''))
 returning id into v_app;
 return jsonb_build_object('result','pending','application_id',v_app,'plan','business','status','pending');
end;
$function$;
revoke all on function public.submit_business_application(text,text,text,text) from public,anon;
grant execute on function public.submit_business_application(text,text,text,text) to authenticated;

create or replace function public.request_business_upgrade(p_organization_id uuid,p_requested_plan text default 'business',p_applicant_note text default null)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=auth.uid(); v_app uuid; v_plan text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if p_requested_plan<>'business' then raise exception 'Target upgrade tidak valid'; end if;
 if not private.has_org_role(p_organization_id,array['owner']) then raise exception 'Hanya pemilik bisnis yang dapat mengajukan upgrade'; end if;
 select plan_name into v_plan from public.subscriptions where organization_id=p_organization_id order by created_at desc limit 1;
 if v_plan is null then raise exception 'Langganan bisnis tidak ditemukan'; end if;
 if lower(v_plan)='business' then raise exception 'Bisnis sudah menggunakan paket Bisnis'; end if;
 if exists(select 1 from public.business_applications where organization_id=p_organization_id and application_type='upgrade' and status='pending') then raise exception 'Pengajuan upgrade masih menunggu persetujuan.'; end if;
 insert into public.business_applications(user_id,application_type,organization_id,business_name,requested_plan,status,applicant_note)
 select v_user,'upgrade',o.id,o.name,'business','pending',nullif(trim(coalesce(p_applicant_note,'')),'') from public.organizations o where o.id=p_organization_id returning id into v_app;
 return v_app;
end;
$function$;
revoke all on function public.request_business_upgrade(uuid,text,text) from public,anon;
grant execute on function public.request_business_upgrade(uuid,text,text) to authenticated;

create or replace function public.review_business_application(p_application_id uuid,p_approved boolean,p_admin_note text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_app public.business_applications%rowtype; v_org uuid;
begin
 if auth.uid() is null or not public.is_platform_admin() then raise exception 'Platform admin access required'; end if;
 select * into v_app from public.business_applications where id=p_application_id for update;
 if not found then raise exception 'Pengajuan tidak ditemukan'; end if;
 if v_app.status<>'pending' then raise exception 'Pengajuan sudah diproses'; end if;
 if p_approved then
  if v_app.application_type='new_business' then
   insert into public.organizations(name,owner_user_id) values(v_app.business_name,v_app.user_id) returning id into v_org;
   insert into public.memberships(organization_id,user_id,role) values(v_org,v_app.user_id,'owner');
   insert into public.stores(organization_id,name,code) values(v_org,v_app.store_name,'STORE-001');
   insert into public.subscriptions(organization_id,plan_name,status,starts_at,ends_at) values(v_org,'business','active',now(),null);
   update public.profiles set active_organization_id=v_org,updated_at=now() where id=v_app.user_id;
  else
   v_org:=v_app.organization_id;
   update public.subscriptions set plan_name='business',status='active',starts_at=now(),ends_at=null where organization_id=v_org;
   if not found then raise exception 'Langganan bisnis tidak ditemukan'; end if;
  end if;
  update public.business_applications set status='approved',admin_note=nullif(trim(coalesce(p_admin_note,'')),''),
   reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=p_application_id;
  return jsonb_build_object('status','approved','organization_id',v_org);
 else
  update public.business_applications set status='rejected',admin_note=nullif(trim(coalesce(p_admin_note,'')),''),
   reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=p_application_id;
  return jsonb_build_object('status','rejected','organization_id',v_app.organization_id);
 end if;
end;
$function$;
revoke all on function public.review_business_application(uuid,boolean,text) from public,anon;
grant execute on function public.review_business_application(uuid,boolean,text) to authenticated;

create or replace function public.platform_admin_overview()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_result jsonb;
begin
 if auth.uid() is null or not public.is_platform_admin() then raise exception 'Platform admin access required'; end if;
 select jsonb_build_object(
  'stats',jsonb_build_object(
   'organizations',(select count(*) from public.organizations),'stores',(select count(*) from public.stores),
   'users',(select count(*) from auth.users),'sales',(select count(*) from public.sales),
   'qr_orders',(select count(*) from public.qr_orders),'subscriptions',(select count(*) from public.subscriptions),
   'active_subscriptions',(select count(*) from public.subscriptions where status='active'),
   'pending_applications',(select count(*) from public.business_applications where status='pending')
  ),
  'organizations',coalesce((select jsonb_agg(jsonb_build_object(
   'id',o.id,'name',o.name,'slug',o.slug,'owner_email',u.email,'created_at',o.created_at,
   'store_count',(select count(*) from public.stores s where s.organization_id=o.id),
   'member_count',(select count(*) from public.memberships m where m.organization_id=o.id),
   'plan_name',(select sub.plan_name from public.subscriptions sub where sub.organization_id=o.id order by sub.created_at desc limit 1),
   'subscription_status',(select sub.status from public.subscriptions sub where sub.organization_id=o.id order by sub.created_at desc limit 1)
  ) order by o.created_at desc) from public.organizations o left join auth.users u on u.id=o.owner_user_id),'[]'::jsonb),
  'users',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'email',r.email,'full_name',r.full_name,'created_at',r.created_at,'last_sign_in_at',r.last_sign_in_at) order by r.created_at desc)
   from (select u.id,u.email,p.full_name,u.created_at,u.last_sign_in_at from auth.users u left join public.profiles p on p.id=u.id order by u.created_at desc limit 100) r),'[]'::jsonb),
  'subscriptions',coalesce((select jsonb_agg(jsonb_build_object('organization_id',o.id,'organization_name',o.name,'owner_email',u.email,'plan_name',sub.plan_name,'status',sub.status,'starts_at',sub.starts_at,'ends_at',sub.ends_at) order by sub.created_at desc)
   from public.subscriptions sub join public.organizations o on o.id=sub.organization_id left join auth.users u on u.id=o.owner_user_id),'[]'::jsonb),
  'applications',coalesce((select jsonb_agg(jsonb_build_object(
   'id',a.id,'user_id',a.user_id,'owner_email',u.email,'application_type',a.application_type,'organization_id',a.organization_id,
   'business_name',a.business_name,'store_name',a.store_name,'requested_plan',a.requested_plan,'status',a.status,
   'applicant_note',a.applicant_note,'admin_note',a.admin_note,'created_at',a.created_at
  ) order by a.created_at desc) from public.business_applications a left join auth.users u on u.id=a.user_id),'[]'::jsonb)
 ) into v_result;
 return v_result;
end;
$function$;
revoke all on function public.platform_admin_overview() from public,anon;
grant execute on function public.platform_admin_overview() to authenticated;
