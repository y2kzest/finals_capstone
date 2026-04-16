-- =============================================================
-- Fix seller_profiles + Create Storage Buckets
-- =============================================================
-- Run this in the Supabase SQL Editor (Dashboard → SQL Editor).
-- =============================================================

-- ─────────────────────────────────────────────
-- 1. Make full_name nullable (it's set later in fill_profile)
-- ─────────────────────────────────────────────
ALTER TABLE seller_profiles ALTER COLUMN full_name DROP NOT NULL;

-- ─────────────────────────────────────────────
-- 2. Add ALL missing columns used by the Flutter app
-- ─────────────────────────────────────────────
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS category               text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS has_bank_account       boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS permit_count           integer DEFAULT 0;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS logo_url               text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS products_added         boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS contact_info_set       boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS is_info_complete       boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS store_information_final text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS stall_number           text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS store_address          text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS official_contact_email text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS is_profile_finalized   boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS approval_email_sent_at timestamptz;

-- ─────────────────────────────────────────────
-- 3. Create storage buckets for logo and permits
-- ─────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('logos', 'logos', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('Permits', 'Permits', true)
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────
-- 4. Storage RLS: authenticated users can upload to their own folder
-- ─────────────────────────────────────────────

-- logos bucket policies
CREATE POLICY "Users upload own logos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'logos' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users update own logos"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'logos' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'logos' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Public read logos"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'logos');

-- Permits bucket policies
CREATE POLICY "Users upload own permits"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'Permits' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users update own permits"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'Permits' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'Permits' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Public read permits"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'Permits');

-- ─────────────────────────────────────────────
-- 5. RLS policies for seller_profiles (idempotent)
-- ─────────────────────────────────────────────
ALTER TABLE seller_profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  BEGIN DROP POLICY "Sellers read own profile" ON seller_profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Sellers upsert own profile" ON seller_profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Sellers update own profile" ON seller_profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
END;
$$;

CREATE POLICY "Sellers read own profile"
  ON seller_profiles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Sellers upsert own profile"
  ON seller_profiles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Sellers update own profile"
  ON seller_profiles FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- =============================================================
-- Done! This fixes:
--   • full_name NOT NULL violation
--   • All missing columns for the seller flow
--   • Storage buckets for logo + permit uploads
--   • RLS policies for storage and seller_profiles
-- =============================================================
