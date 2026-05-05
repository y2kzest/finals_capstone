-- Normalize review ownership across legacy reviewer_id rows and newer buyer_id rows.
-- Safe to run even if the earlier review RLS migration already executed.

UPDATE public.reviews
SET buyer_id = reviewer_id
WHERE buyer_id IS NULL AND reviewer_id IS NOT NULL;

UPDATE public.reviews
SET reviewer_id = buyer_id
WHERE reviewer_id IS NULL AND buyer_id IS NOT NULL;

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users read reviews" ON public.reviews;
DROP POLICY IF EXISTS "Buyers insert own review" ON public.reviews;
DROP POLICY IF EXISTS "Buyers delete own review" ON public.reviews;
DROP POLICY IF EXISTS "Reviews: buyers can insert" ON public.reviews;
DROP POLICY IF EXISTS "Reviews: public read" ON public.reviews;
DROP POLICY IF EXISTS "Reviews: buyers manage own" ON public.reviews;
DROP POLICY IF EXISTS "Reviews: buyers can update" ON public.reviews;
DROP POLICY IF EXISTS "Reviews: buyers can delete" ON public.reviews;

CREATE POLICY "Reviews: public read"
  ON public.reviews
  FOR SELECT
  USING (true);

CREATE POLICY "Reviews: buyers can insert"
  ON public.reviews
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = COALESCE(buyer_id, reviewer_id));

CREATE POLICY "Reviews: buyers can update"
  ON public.reviews
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = COALESCE(buyer_id, reviewer_id))
  WITH CHECK (auth.uid() = COALESCE(buyer_id, reviewer_id));

CREATE POLICY "Reviews: buyers can delete"
  ON public.reviews
  FOR DELETE
  TO authenticated
  USING (auth.uid() = COALESCE(buyer_id, reviewer_id));