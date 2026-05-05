-- Ensure the singular profile table used by the Flutter app is readable
-- by authenticated users and manageable by the row owner.

ALTER TABLE public.profile ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users read profile" ON public.profile;
DROP POLICY IF EXISTS "Users insert own profile row" ON public.profile;
DROP POLICY IF EXISTS "Users update own profile row" ON public.profile;

CREATE POLICY "Authenticated users read profile"
ON public.profile FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Users insert own profile row"
ON public.profile FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own profile row"
ON public.profile FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);