-- ============================================================
-- Run this in Supabase SQL Editor to add missing columns
-- needed by the seller pages.
-- ============================================================

-- 1. Product table: add seller ownership and timestamp
ALTER TABLE public.product
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS seller_id uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- 2. Orders table: add seller/buyer linkage and order status
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS seller_id uuid,
  ADD COLUMN IF NOT EXISTS buyer_id uuid,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending';

-- 3. Enable RLS (safe to re-run)
ALTER TABLE public.product ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders  ENABLE ROW LEVEL SECURITY;

-- 4. RLS policies for product table
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'product'
      AND policyname = 'Anyone can read products'
  ) THEN
    CREATE POLICY "Anyone can read products"
      ON public.product FOR SELECT
      USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'product'
      AND policyname = 'Sellers manage own products'
  ) THEN
    CREATE POLICY "Sellers manage own products"
      ON public.product FOR ALL
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- 5. RLS policies for orders table
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders'
      AND policyname = 'Buyers see own orders'
  ) THEN
    CREATE POLICY "Buyers see own orders"
      ON public.orders FOR SELECT
      USING (auth.uid() = buyer_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders'
      AND policyname = 'Sellers see orders for their products'
  ) THEN
    CREATE POLICY "Sellers see orders for their products"
      ON public.orders FOR SELECT
      USING (auth.uid() = seller_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders'
      AND policyname = 'Sellers update own orders'
  ) THEN
    CREATE POLICY "Sellers update own orders"
      ON public.orders FOR UPDATE
      USING (auth.uid() = seller_id)
      WITH CHECK (auth.uid() = seller_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders'
      AND policyname = 'Authenticated users insert orders'
  ) THEN
    CREATE POLICY "Authenticated users insert orders"
      ON public.orders FOR INSERT
      WITH CHECK (auth.uid() = buyer_id);
  END IF;
END $$;
