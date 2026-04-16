-- ============================================================
-- Full database setup for roles, seller applications, and
-- admin approval. Run in Supabase SQL Editor.
-- ============================================================

-- 1. user_roles table
CREATE TABLE IF NOT EXISTS public.user_roles (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL UNIQUE,
  role text NOT NULL DEFAULT 'buyer',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Users can read their own role
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='user_roles'
      AND policyname='Users read own role'
  ) THEN
    CREATE POLICY "Users read own role"
      ON public.user_roles FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- Users can insert their own role (signup)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='user_roles'
      AND policyname='Users insert own role'
  ) THEN
    CREATE POLICY "Users insert own role"
      ON public.user_roles FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Admins can read all roles
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='user_roles'
      AND policyname='Admins read all roles'
  ) THEN
    CREATE POLICY "Admins read all roles"
      ON public.user_roles FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          WHERE ur.user_id = auth.uid() AND ur.role = 'admin'
        )
      );
  END IF;
END $$;

-- Admins can update any role (for approving sellers)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='user_roles'
      AND policyname='Admins update roles'
  ) THEN
    CREATE POLICY "Admins update roles"
      ON public.user_roles FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          WHERE ur.user_id = auth.uid() AND ur.role = 'admin'
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          WHERE ur.user_id = auth.uid() AND ur.role = 'admin'
        )
      );
  END IF;
END $$;


-- 2. seller_profiles table
CREATE TABLE IF NOT EXISTS public.seller_profiles (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL UNIQUE,
  full_name text,
  store_name text,
  category text,
  has_bank_account boolean DEFAULT false,
  permit_count int DEFAULT 0,
  logo_url text,
  products_added boolean DEFAULT false,
  contact_info_set boolean DEFAULT false,
  is_info_complete boolean DEFAULT false,
  store_information_final text,
  stall_number text,
  store_address text,
  official_contact_email text,
  is_profile_finalized boolean DEFAULT false,
  approval_status text NOT NULL DEFAULT 'pending',
  approval_email_sent_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Constraint for valid statuses
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'seller_profiles_approval_status_check'
  ) THEN
    ALTER TABLE public.seller_profiles
      ADD CONSTRAINT seller_profiles_approval_status_check
      CHECK (approval_status IN ('pending', 'approved', 'rejected'));
  END IF;
END $$;

ALTER TABLE public.seller_profiles ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_seller_profiles_user_id
  ON public.seller_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_seller_profiles_approval_status
  ON public.seller_profiles(approval_status);

-- Sellers can read and update their own profile
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='seller_profiles'
      AND policyname='Users manage own seller profile'
  ) THEN
    CREATE POLICY "Users manage own seller profile"
      ON public.seller_profiles FOR ALL
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Admins can read all seller profiles
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='seller_profiles'
      AND policyname='Admins read all seller profiles'
  ) THEN
    CREATE POLICY "Admins read all seller profiles"
      ON public.seller_profiles FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          WHERE ur.user_id = auth.uid() AND ur.role = 'admin'
        )
      );
  END IF;
END $$;

-- Admins can update seller profiles (approve/reject)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='seller_profiles'
      AND policyname='Admins update seller profiles'
  ) THEN
    CREATE POLICY "Admins update seller profiles"
      ON public.seller_profiles FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          WHERE ur.user_id = auth.uid() AND ur.role = 'admin'
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          WHERE ur.user_id = auth.uid() AND ur.role = 'admin'
        )
      );
  END IF;
END $$;
