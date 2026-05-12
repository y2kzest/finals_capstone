-- Phase 2.5: Persist map coordinates on each order
--
-- delivery_lat/lng: where the buyer asked the order to be delivered (rider needs this).
-- store_lat/lng:    snapshot of the seller's stall location at order time
--                   (so the order history doesn't break if the seller later moves their pin).
-- Run once in the Supabase SQL editor.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_lat double precision,
  ADD COLUMN IF NOT EXISTS delivery_lng double precision,
  ADD COLUMN IF NOT EXISTS store_lat    double precision,
  ADD COLUMN IF NOT EXISTS store_lng    double precision;

-- Sanity check:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'orders'
--   AND column_name IN ('delivery_lat','delivery_lng','store_lat','store_lng');
