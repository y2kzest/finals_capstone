-- =============================================================
-- Admin Visibility Fix
-- =============================================================
-- Fixes:
--   1. RLS: allow any authenticated user to READ seller data
--      (admin website uses authenticated session, needs to see all rows)
--   2. Creates vendor_management_details if not exists
--   3. Creates sync triggers: seller_profiles → profiles + vendor_management_details
--   4. Backfills existing seller_profiles rows to profiles + vendor_management_details
-- =============================================================

-- ─────────────────────────────────────────────
-- 1. seller_profiles: open SELECT to all authenticated users
-- ─────────────────────────────────────────────
ALTER TABLE seller_profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  BEGIN DROP POLICY "Sellers read own profile" ON seller_profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Authenticated users read seller_profiles" ON seller_profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Sellers upsert own profile" ON seller_profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Sellers update own profile" ON seller_profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
END;
$$;

-- Any authenticated user can read (admin needs this)
CREATE POLICY "Authenticated users read seller_profiles"
  ON seller_profiles FOR SELECT
  TO authenticated
  USING (true);

-- Only the seller themselves can write their own row
CREATE POLICY "Sellers upsert own profile"
  ON seller_profiles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Sellers update own profile"
  ON seller_profiles FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- 2. profiles: open SELECT to all authenticated users
-- ─────────────────────────────────────────────
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  BEGIN DROP POLICY "Users read own profiles row" ON profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Authenticated users read profiles" ON profiles; EXCEPTION WHEN undefined_object THEN NULL; END;
END;
$$;

CREATE POLICY "Authenticated users read profiles"
  ON profiles FOR SELECT
  TO authenticated
  USING (true);

-- ─────────────────────────────────────────────
-- 3. Create vendor_management_details if not exists
-- ─────────────────────────────────────────────
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

ALTER TABLE vendor_management_details ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  BEGIN DROP POLICY "Sellers read own vendor_management_details" ON vendor_management_details; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Sellers upsert own vendor_management_details" ON vendor_management_details; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Sellers update own vendor_management_details" ON vendor_management_details; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN DROP POLICY "Authenticated users read vendor_management_details" ON vendor_management_details; EXCEPTION WHEN undefined_object THEN NULL; END;
END;
$$;

-- Any authenticated user can read
CREATE POLICY "Authenticated users read vendor_management_details"
  ON vendor_management_details FOR SELECT
  TO authenticated
  USING (true);

-- Only the owner can write
CREATE POLICY "Sellers upsert own vendor_management_details"
  ON vendor_management_details FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Sellers update own vendor_management_details"
  ON vendor_management_details FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- 4. Ensure seller_profiles has all needed columns
-- ─────────────────────────────────────────────
ALTER TABLE seller_profiles ALTER COLUMN full_name DROP NOT NULL;

ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS category               text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS has_bank_account       boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS permit_count           integer DEFAULT 0;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS logo_url               text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS is_info_complete       boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS store_information_final text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS stall_number           text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS store_address          text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS official_contact_email text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS is_profile_finalized   boolean DEFAULT false;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS approval_email_sent_at timestamptz;

-- ─────────────────────────────────────────────
-- 5. Sync trigger: seller_profiles → profiles
-- ─────────────────────────────────────────────
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
    status = COALESCE(NEW.approval_status, profiles.status, 'pending');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_seller_to_profiles ON seller_profiles;
CREATE TRIGGER trg_sync_seller_to_profiles
  AFTER INSERT OR UPDATE ON seller_profiles
  FOR EACH ROW EXECUTE FUNCTION sync_seller_to_profiles();

-- ─────────────────────────────────────────────
-- 6. Sync trigger: seller_profiles → vendor_management_details
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION sync_seller_to_vendor_details()
RETURNS trigger AS $$
BEGIN
  INSERT INTO vendor_management_details (user_id, stall_no, business_type, contact_number, permit_count)
  VALUES (
    NEW.user_id,
    NEW.stall_number,
    NEW.category,
    NEW.official_contact_email,
    COALESCE(NEW.permit_count, 0)
  )
  ON CONFLICT (user_id) DO UPDATE SET
    stall_no       = COALESCE(NEW.stall_number, vendor_management_details.stall_no),
    business_type  = COALESCE(NEW.category,     vendor_management_details.business_type),
    contact_number = COALESCE(NEW.official_contact_email, vendor_management_details.contact_number),
    permit_count   = COALESCE(NEW.permit_count, vendor_management_details.permit_count);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_seller_to_vendor_details ON seller_profiles;
CREATE TRIGGER trg_sync_seller_to_vendor_details
  AFTER INSERT OR UPDATE ON seller_profiles
  FOR EACH ROW EXECUTE FUNCTION sync_seller_to_vendor_details();

-- ─────────────────────────────────────────────
-- 7. Backfill: sync ALL existing seller_profiles rows
--    (triggers only fire on future inserts/updates)
-- ─────────────────────────────────────────────

-- Backfill profiles table
INSERT INTO profiles (id, email, role, status, created_at)
SELECT
  sp.user_id,
  COALESCE(sp.official_contact_email, au.email),
  'seller',
  COALESCE(sp.approval_status, 'pending'),
  COALESCE(sp.created_at, now())
FROM seller_profiles sp
LEFT JOIN auth.users au ON au.id = sp.user_id
ON CONFLICT (id) DO UPDATE SET
  role   = 'seller',
  status = COALESCE(EXCLUDED.status, profiles.status, 'pending');

-- Backfill vendor_management_details table
INSERT INTO vendor_management_details (user_id, stall_no, business_type, contact_number, permit_count)
SELECT
  sp.user_id,
  sp.stall_number,
  sp.category,
  sp.official_contact_email,
  COALESCE(sp.permit_count, 0)
FROM seller_profiles sp
ON CONFLICT (user_id) DO UPDATE SET
  stall_no       = COALESCE(EXCLUDED.stall_no,       vendor_management_details.stall_no),
  business_type  = COALESCE(EXCLUDED.business_type,  vendor_management_details.business_type),
  contact_number = COALESCE(EXCLUDED.contact_number, vendor_management_details.contact_number),
  permit_count   = COALESCE(EXCLUDED.permit_count,   vendor_management_details.permit_count);

-- =============================================================
-- Done! Refresh the admin website after running this.
-- Sellers who already applied will now appear in the pending table.
-- =============================================================
