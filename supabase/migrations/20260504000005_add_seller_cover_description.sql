-- Add cover photo and store description to seller profiles
ALTER TABLE public.seller_profiles
  ADD COLUMN IF NOT EXISTS cover_url text,
  ADD COLUMN IF NOT EXISTS description text;
