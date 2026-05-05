-- Add scheduled pickup time to orders (selected by buyer on homepage)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS pickup_time text;

-- Add preferred pickup window to profile (buyer's default pickup preference)
ALTER TABLE public.profile
  ADD COLUMN IF NOT EXISTS preferred_pickup_window text;
