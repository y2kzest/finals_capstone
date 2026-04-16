-- ============================================================
-- Step 1: Create storage buckets (safe to re-run)
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('products', 'products', true)
ON CONFLICT (id) DO UPDATE SET public = true;

INSERT INTO storage.buckets (id, name, public)
VALUES ('logos', 'logos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

INSERT INTO storage.buckets (id, name, public)
VALUES ('Permits', 'Permits', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- ============================================================
-- Step 2: Drop ALL existing policies on storage.objects
--         that we manage (safe if they don't exist)
-- ============================================================
DROP POLICY IF EXISTS "Public read access on products bucket" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated upload to products bucket" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own product images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own product images" ON storage.objects;
DROP POLICY IF EXISTS "Public read access on logos bucket" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated upload to logos bucket" ON storage.objects;
DROP POLICY IF EXISTS "Public read access on Permits bucket" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated upload to Permits bucket" ON storage.objects;

-- ============================================================
-- Step 3: Recreate all policies
-- ============================================================

-- products: public read
CREATE POLICY "Public read access on products bucket"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'products');

-- products: authenticated upload
CREATE POLICY "Authenticated upload to products bucket"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'products');

-- products: authenticated update
CREATE POLICY "Users can update own product images"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'products')
WITH CHECK (bucket_id = 'products');

-- products: authenticated delete
CREATE POLICY "Users can delete own product images"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'products');

-- logos: public read
CREATE POLICY "Public read access on logos bucket"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'logos');

-- logos: authenticated upload
CREATE POLICY "Authenticated upload to logos bucket"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'logos');

-- Permits: public read
CREATE POLICY "Public read access on Permits bucket"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'Permits');

-- Permits: authenticated upload
CREATE POLICY "Authenticated upload to Permits bucket"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'Permits');
