-- =============================================================
-- Product Table: RLS, FK, and Storage Bucket Setup
-- =============================================================
-- Ensures:
--   1. product table has a FK to seller_profiles via seller_id
--   2. RLS: anyone can READ products, only the seller owner can write
--   3. products storage bucket exists with public read access
-- =============================================================

-- ─────────────────────────────────────────────
-- 1. Ensure product table has required columns
-- ─────────────────────────────────────────────
ALTER TABLE product ADD COLUMN IF NOT EXISTS seller_id  uuid REFERENCES auth.users(id);
ALTER TABLE product ADD COLUMN IF NOT EXISTS user_id    uuid REFERENCES auth.users(id);
ALTER TABLE product ADD COLUMN IF NOT EXISTS category   text;
ALTER TABLE product ADD COLUMN IF NOT EXISTS unit_type  text DEFAULT 'Kg';
ALTER TABLE product ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE product ADD COLUMN IF NOT EXISTS retail_price numeric;
ALTER TABLE product ADD COLUMN IF NOT EXISTS image_url  text;

-- Backfill seller_id from user_id if null
UPDATE product SET seller_id = user_id WHERE seller_id IS NULL AND user_id IS NOT NULL;

-- ─────────────────────────────────────────────
-- 2. RLS: public read, owner write
-- ─────────────────────────────────────────────
ALTER TABLE product ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  BEGIN DROP POLICY "Anyone can read products" ON product; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Sellers insert own products" ON product; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Sellers update own products" ON product; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Sellers delete own products" ON product; EXCEPTION WHEN undefined_object THEN NULL; END;
END;
$$;

-- Anyone (even anonymous) can read products
CREATE POLICY "Anyone can read products"
  ON product FOR SELECT
  USING (true);

-- Only the seller can insert their own products
CREATE POLICY "Sellers insert own products"
  ON product FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id OR auth.uid() = seller_id);

-- Only the seller can update their own products
CREATE POLICY "Sellers update own products"
  ON product FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id OR auth.uid() = seller_id)
  WITH CHECK (auth.uid() = user_id OR auth.uid() = seller_id);

-- Only the seller can delete their own products
CREATE POLICY "Sellers delete own products"
  ON product FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id OR auth.uid() = seller_id);

-- ─────────────────────────────────────────────
-- 3. Products storage bucket (for product images)
-- ─────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('products', 'products', true)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload product images
DO $$
BEGIN
  BEGIN DROP POLICY "Authenticated upload to products" ON storage.objects; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Public read from products" ON storage.objects; EXCEPTION WHEN undefined_object THEN NULL; END;
END;
$$;

CREATE POLICY "Authenticated upload to products"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'products');

CREATE POLICY "Public read from products"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'products');

-- ─────────────────────────────────────────────
-- 4. Create FK from product.seller_id → seller_profiles.user_id
--    (enables the Supabase join in Flutter: product → seller_profiles)
-- ─────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'product_seller_id_fkey'
      AND table_name = 'product'
  ) THEN
    ALTER TABLE product
      ADD CONSTRAINT product_seller_id_fkey
      FOREIGN KEY (seller_id) REFERENCES seller_profiles(user_id);
  END IF;
END;
$$;

-- =============================================================
-- Done! Seller products will now show on the buyer home page.
-- =============================================================
