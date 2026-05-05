-- Add shop hours and open/closed toggle columns to seller_profiles
ALTER TABLE seller_profiles
  ADD COLUMN IF NOT EXISTS opening_time text DEFAULT '05:00',
  ADD COLUMN IF NOT EXISTS closing_time text DEFAULT '19:00',
  ADD COLUMN IF NOT EXISTS is_open boolean DEFAULT false;
