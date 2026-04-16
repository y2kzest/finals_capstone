-- Add permit_urls array column to store actual public URLs of uploaded permits
ALTER TABLE seller_profiles
  ADD COLUMN IF NOT EXISTS permit_urls text[] DEFAULT '{}';
