-- ── Palengke feature columns ────────────────────────────────
-- Orders: notes, substitution preference, requested/final weight, cancel fields
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS buyer_notes text,
  ADD COLUMN IF NOT EXISTS allow_substitution boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS requested_weight numeric,
  ADD COLUMN IF NOT EXISTS final_weight numeric,
  ADD COLUMN IF NOT EXISTS cancelled_by text,
  ADD COLUMN IF NOT EXISTS cancel_reason text;

-- Reviews: allow buyers to leave product reviews after a completed order
ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS order_id uuid,
  ADD COLUMN IF NOT EXISTS buyer_id uuid,
  ADD COLUMN IF NOT EXISTS comment text,
  ADD COLUMN IF NOT EXISTS reviewer_name text;

-- Products: is_by_weight flag, auto_pause when stock = 0
ALTER TABLE public.product
  ADD COLUMN IF NOT EXISTS is_by_weight boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_paused boolean DEFAULT false;

-- Seller profiles: stall number and section for market navigation
ALTER TABLE public.seller_profiles
  ADD COLUMN IF NOT EXISTS stall_number text,
  ADD COLUMN IF NOT EXISTS market_section text;

-- Wishlist / favourites table
CREATE TABLE IF NOT EXISTS public.wishlist (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id   text NOT NULL,
  product_name text,
  image_url    text,
  price        numeric,
  seller_id    uuid,
  store_name   text,
  created_at   timestamptz DEFAULT now(),
  UNIQUE (user_id, product_id)
);

-- RLS for wishlist
ALTER TABLE public.wishlist ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Wishlist: users manage own rows"
  ON public.wishlist
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Auto-pause trigger: pause product when stock hits 0 after an order is placed
CREATE OR REPLACE FUNCTION public.auto_pause_out_of_stock()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.stock_quantity IS NOT NULL AND NEW.stock_quantity <= 0 THEN
    NEW.is_paused := true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_pause_product ON public.product;
CREATE TRIGGER trg_auto_pause_product
  BEFORE UPDATE OF stock_quantity ON public.product
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_pause_out_of_stock();
