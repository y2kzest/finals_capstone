-- Allow any authenticated user to read admin role rows.
-- This is needed so the Flutter buyer app can look up the admin's user_id
-- when tapping the Help button on the profile page.

drop policy if exists "Anyone can read admin role" on public.user_roles;
create policy "Anyone can read admin role"
  on public.user_roles
  for select
  to authenticated
  using (role = 'admin');
