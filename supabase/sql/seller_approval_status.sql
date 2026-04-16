-- Adds seller approval tracking fields used by the notification function.
alter table if exists public.seller_profiles
  add column if not exists approval_status text not null default 'pending',
  add column if not exists approval_email_sent_at timestamptz;

-- Optional safety check for valid statuses.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'seller_profiles_approval_status_check'
  ) then
    alter table public.seller_profiles
      add constraint seller_profiles_approval_status_check
      check (approval_status in ('pending', 'approved', 'rejected'));
  end if;
end $$;

create index if not exists idx_seller_profiles_user_id on public.seller_profiles(user_id);
