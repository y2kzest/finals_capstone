-- =============================================================
-- Vue Admin ↔ Flutter App Compatibility Migration
-- =============================================================
-- Run this in the Supabase SQL Editor (Dashboard → SQL Editor).
--
-- Fixes:
--   1. seller_profiles: adds 13 missing columns the Flutter app writes
--   2. vendor_management_details: creates the table the Vue admin reads
--   3. profiles ↔ seller_profiles sync trigger so the Vue admin sees sellers
--   4. RLS policies for all new/updated tables
-- =============================================================

-- ─────────────────────────────────────────────
-- 1. Add missing columns to seller_profiles
-- ─────────────────────────────────────────────
-- Existing columns: id, user_id, store_name, full_name, approval_status, created_at
-- The Flutter app's fill_business_info.dart and fill_profile.dart upsert many more.

ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS category           text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS has_bank_account   boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS permit_count       integer DEFAULT 0;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS logo_url           text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS products_added     boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS contact_info_set   boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS is_info_complete   boolean DEFAULT false;

-- From fill_profile.dart (BusinessProfileScreen)
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS store_information_final text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS stall_number           text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS store_address          text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS official_contact_email text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS is_profile_finalized   boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS approval_email_sent_at timestamptz;

-- ─────────────────────────────────────────────
-- 2. Create vendor_management_details table
-- ─────────────────────────────────────────────
-- The Vue admin's fetchVendors() does:
--   supabase.from('vendor_management_details').select('*')
-- and upserts on user_id conflict.

CREATE TABLE IF NOT EXISTS vendor_management_details (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  stall_no        text,
  business_type   text,
  contact_number  text,
  operating_hours text,
  product_listed  integer DEFAULT 0,
  permit_count    integer DEFAULT 0,
  created_at      timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE vendor_management_details ENABLE ROW LEVEL SECURITY;

-- Sellers can read their own row
CREATE POLICY "Sellers read own vendor_management_details"
  ON vendor_management_details FOR SELECT
  USING (auth.uid() = user_id);

-- Sellers can upsert their own row
CREATE POLICY "Sellers upsert own vendor_management_details"
  ON vendor_management_details FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Sellers update own vendor_management_details"
  ON vendor_management_details FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Service role / admin can do everything (edge functions use service_role key)
-- Note: service_role bypasses RLS by default, so no explicit policy needed.

-- ─────────────────────────────────────────────
-- 3. Sync trigger: seller_profiles → profiles
-- ─────────────────────────────────────────────
-- The Vue admin reads: profiles.select('id,email,role,status,created_at').eq('role','seller')
-- and updates: profiles.update({ status: nextStatus }).eq('id', targetUserId)
--
-- When the Flutter app inserts/updates seller_profiles, we mirror to profiles
-- so the admin sees the seller rows there too.

-- 3a. Ensure profiles table has the right columns (it already has id, email, role, status, created_at)
-- No changes needed for profiles itself.

-- 3b. Create trigger function
CREATE OR REPLACE FUNCTION sync_seller_to_profiles()
RETURNS trigger AS $$
BEGIN
  INSERT INTO profiles (id, email, role, status, created_at)
  VALUES (
    NEW.user_id,
    COALESCE(NEW.official_contact_email, (SELECT email FROM auth.users WHERE id = NEW.user_id)),
    'seller',
    COALESCE(NEW.approval_status, 'pending'),
    COALESCE(NEW.created_at, now())
  )
  ON CONFLICT (id) DO UPDATE SET
    role   = 'seller',
    status = COALESCE(NEW.approval_status, 'pending');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3c. Create trigger
DROP TRIGGER IF EXISTS trg_sync_seller_to_profiles ON seller_profiles;
CREATE TRIGGER trg_sync_seller_to_profiles
  AFTER INSERT OR UPDATE ON seller_profiles
  FOR EACH ROW
  EXECUTE FUNCTION sync_seller_to_profiles();

-- ─────────────────────────────────────────────
-- 4. Sync trigger: seller_profiles → vendor_management_details
-- ─────────────────────────────────────────────
-- So the Vue admin's vendor_management_details query stays populated
-- when a seller finishes fill_business_info / fill_profile.

CREATE OR REPLACE FUNCTION sync_seller_to_vendor_details()
RETURNS trigger AS $$
BEGIN
  INSERT INTO vendor_management_details (user_id, stall_no, business_type, contact_number, permit_count, product_listed)
  VALUES (
    NEW.user_id,
    NEW.stall_number,
    NEW.category,
    NEW.official_contact_email,
    COALESCE(NEW.permit_count, 0),
    CASE WHEN NEW.products_added THEN 1 ELSE 0 END
  )
  ON CONFLICT (user_id) DO UPDATE SET
    stall_no       = COALESCE(NEW.stall_number, vendor_management_details.stall_no),
    business_type  = COALESCE(NEW.category, vendor_management_details.business_type),
    contact_number = COALESCE(NEW.official_contact_email, vendor_management_details.contact_number),
    permit_count   = COALESCE(NEW.permit_count, vendor_management_details.permit_count),
    product_listed = CASE WHEN NEW.products_added THEN 1 ELSE vendor_management_details.product_listed END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_seller_to_vendor_details ON seller_profiles;
CREATE TRIGGER trg_sync_seller_to_vendor_details
  AFTER INSERT OR UPDATE ON seller_profiles
  FOR EACH ROW
  EXECUTE FUNCTION sync_seller_to_vendor_details();

-- ─────────────────────────────────────────────
-- 5. RLS policies for seller_profiles (if not yet set)
-- ─────────────────────────────────────────────
ALTER TABLE seller_profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies first to avoid conflicts (idempotent)
DO $$
BEGIN
  -- Attempt to drop; ignore if they don't exist
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

-- ─────────────────────────────────────────────
-- 6. RLS for profiles table (ensure sellers & admin can access)
-- ─────────────────────────────────────────────
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  BEGIN DROP POLICY "Users read own profiles row" ON profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
END;
$$;

CREATE POLICY "Users read own profiles row"
  ON profiles FOR SELECT
  USING (auth.uid() = id);

-- The trigger function uses SECURITY DEFINER, so it bypasses RLS when writing.
-- The Vue admin uses the service_role key, which also bypasses RLS.

-- =============================================================
-- Done! After running this:
--   • Flutter seller sign-up flow will succeed (columns exist)
--   • Vue admin will see sellers in profiles + vendor_management_details
--   • Admin approval (seller_profiles.approval_status) syncs to profiles.status
-- =============================================================
