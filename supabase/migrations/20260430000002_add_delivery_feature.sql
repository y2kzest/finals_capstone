-- Add delivery toggle to seller profiles
ALTER TABLE public.seller_profiles
  ADD COLUMN IF NOT EXISTS delivery_enabled boolean NOT NULL DEFAULT false;

-- Add order type and delivery address to orders
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_type text NOT NULL DEFAULT 'pickup',
  ADD COLUMN IF NOT EXISTS delivery_address text;
