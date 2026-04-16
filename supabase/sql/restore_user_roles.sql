-- Restore role table used by middleware/authService.
-- Run this in Supabase SQL Editor.

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'seller', 'buyer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_roles enable row level security;

-- Keep policies idempotent
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_roles'
      AND policyname = 'Users can read own role'
  ) THEN
    CREATE POLICY "Users can read own role"
      ON public.user_roles
      FOR SELECT
      TO authenticated
      USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_roles'
      AND policyname = 'Service role can manage all roles'
  ) THEN
    CREATE POLICY "Service role can manage all roles"
      ON public.user_roles
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

create or replace function public.set_updated_at_user_roles()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_user_roles_updated_at on public.user_roles;
create trigger trg_user_roles_updated_at
before update on public.user_roles
for each row
execute function public.set_updated_at_user_roles();

-- Replace this email with your admin account email in Supabase Auth.
-- If the user exists, this creates/updates a single admin row.
insert into public.user_roles (user_id, role)
select id, 'admin'
from auth.users
where email = 'maicasulla13@gmail.com'
on conflict (user_id) do update
set role = excluded.role,
    updated_at = now();
