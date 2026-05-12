-- Phase 1: Store locator / map
-- Adds stall coordinates and stall number/label to seller_profiles.
-- Run this once in the Supabase SQL editor.

ALTER TABLE public.seller_profiles
  ADD COLUMN IF NOT EXISTS stall_lat  double precision,
  ADD COLUMN IF NOT EXISTS stall_lng  double precision,
  ADD COLUMN IF NOT EXISTS stall_no   text;

-- Optional: index to speed up "stalls with a location" queries used by the map.
CREATE INDEX IF NOT EXISTS seller_profiles_stall_latlng_idx
  ON public.seller_profiles (stall_lat, stall_lng)
  WHERE stall_lat IS NOT NULL AND stall_lng IS NOT NULL;

-- Sanity check: confirm the columns exist.
-- SELECT column_name, data_type
-- FROM information_schema.columns
-- WHERE table_name = 'seller_profiles'
--   AND column_name IN ('stall_lat','stall_lng','stall_no');
