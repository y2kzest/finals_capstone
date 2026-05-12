-- Phase 2: Buyer-side map address picker
-- Adds lat/lng to delivery_addresses so a buyer's address has an exact pin
-- (used by the cart map preview and rider routing).
-- Run this once in the Supabase SQL editor.

ALTER TABLE public.delivery_addresses
  ADD COLUMN IF NOT EXISTS lat double precision,
  ADD COLUMN IF NOT EXISTS lng double precision;

-- Sanity check:
-- SELECT column_name, data_type
-- FROM information_schema.columns
-- WHERE table_name = 'delivery_addresses'
--   AND column_name IN ('lat','lng');
