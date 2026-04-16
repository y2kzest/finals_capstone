-- Add banner_url column to seller_profiles
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS banner_url text;
