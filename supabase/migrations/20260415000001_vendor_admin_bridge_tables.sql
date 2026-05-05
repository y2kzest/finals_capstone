-- Creates bridge tables used by seller approval function to feed external admin queues.
-- Run in Supabase SQL Editor.

create table if not exists public.vendor_applications (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  vendor_name text not null,
  email text not null,
  stall_no text,
  business_type text,
  contact text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vendor_profiles (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  vendor_name text not null,
  email text not null,
  stall_no text,
  business_type text,
  contact text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vendors (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  vendor_name text not null,
  email text not null,
  stall_no text,
  business_type text,
  contact text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ux_vendor_applications_user_id
  on public.vendor_applications(user_id);

create unique index if not exists ux_vendor_profiles_user_id
  on public.vendor_profiles(user_id);

create unique index if not exists ux_vendors_user_id
  on public.vendors(user_id);

create index if not exists ix_vendor_applications_status
  on public.vendor_applications(status);

create index if not exists ix_vendor_profiles_status
  on public.vendor_profiles(status);

create index if not exists ix_vendors_status
  on public.vendors(status);

create or replace function public.set_updated_at_vendor_admin_bridge()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_vendor_applications_updated_at on public.vendor_applications;
create trigger trg_vendor_applications_updated_at
before update on public.vendor_applications
for each row execute function public.set_updated_at_vendor_admin_bridge();

drop trigger if exists trg_vendor_profiles_updated_at on public.vendor_profiles;
create trigger trg_vendor_profiles_updated_at
before update on public.vendor_profiles
for each row execute function public.set_updated_at_vendor_admin_bridge();

drop trigger if exists trg_vendors_updated_at on public.vendors;
create trigger trg_vendors_updated_at
before update on public.vendors
for each row execute function public.set_updated_at_vendor_admin_bridge();

alter table public.vendor_applications enable row level security;
alter table public.vendor_profiles enable row level security;
alter table public.vendors enable row level security;

-- Service role can read and write all rows.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'vendor_applications'
      and policyname = 'Service role full access vendor_applications'
  ) then
    create policy "Service role full access vendor_applications"
      on public.vendor_applications
      for all
      to service_role
      using (true)
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'vendor_profiles'
      and policyname = 'Service role full access vendor_profiles'
  ) then
    create policy "Service role full access vendor_profiles"
      on public.vendor_profiles
      for all
      to service_role
      using (true)
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'vendors'
      and policyname = 'Service role full access vendors'
  ) then
    create policy "Service role full access vendors"
      on public.vendors
      for all
      to service_role
      using (true)
      with check (true);
  end if;
end $$;
