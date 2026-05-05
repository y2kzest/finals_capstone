-- Drop redundant storage/profile policies without changing current app behavior.
--
-- Safe assumptions validated before this cleanup:
-- 1. The only storage buckets in use are products, logos, Permits, and avatars.
-- 2. All four buckets already have explicit read/insert policies that cover app behavior.
-- 3. public.profile.user_id is NOT NULL, so older public-role own-row policies do not
--    grant extra anonymous access when auth.uid() is null.

-- public.profile: keep the canonical policies created by the latest migration
-- and remove the older overlapping ones.
DROP POLICY IF EXISTS "Admins can view profile identity" ON public.profile;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profile;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profile;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profile;
DROP POLICY IF EXISTS "profile" ON public.profile;

-- storage.objects: remove exact duplicates and broad legacy policies now
-- superseded by bucket-specific policies.
DROP POLICY IF EXISTS "Authenticated upload to products" ON storage.objects;
DROP POLICY IF EXISTS "Public read from products" ON storage.objects;
DROP POLICY IF EXISTS "Public read logos" ON storage.objects;
DROP POLICY IF EXISTS "Public read permits" ON storage.objects;
DROP POLICY IF EXISTS "Permits gb200o_0" ON storage.objects;
DROP POLICY IF EXISTS "Permits gb200o_1" ON storage.objects;