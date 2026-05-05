-- Add saved delivery address to buyer profile
ALTER TABLE public.profile
  ADD COLUMN IF NOT EXISTS delivery_address text;
