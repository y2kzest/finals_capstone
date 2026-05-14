-- Add selected_variant and buyer_note to cart rows
-- so option choices survive from cart → order promotion.

ALTER TABLE public.cart
  ADD COLUMN IF NOT EXISTS selected_variant TEXT,
  ADD COLUMN IF NOT EXISTS buyer_note TEXT;

-- Add selected_variant to orders so the seller can see what option was chosen.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS selected_variant TEXT;
