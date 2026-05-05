-- Require a completed purchase before buyers can create or edit a product review.
-- Safe to run after the earlier review compatibility migrations.

ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS order_id uuid;

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Reviews: buyers can insert" ON public.reviews;
DROP POLICY IF EXISTS "Reviews: buyers can update" ON public.reviews;

CREATE POLICY "Reviews: buyers can insert"
  ON public.reviews
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = COALESCE(buyer_id, reviewer_id)
    AND order_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.id = order_id
        AND o.buyer_id = auth.uid()
        AND o.product_id = product_id
        AND lower(COALESCE(o.status, '')) IN ('completed', 'delivered')
    )
  );

CREATE POLICY "Reviews: buyers can update"
  ON public.reviews
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = COALESCE(buyer_id, reviewer_id))
  WITH CHECK (
    auth.uid() = COALESCE(buyer_id, reviewer_id)
    AND order_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.id = order_id
        AND o.buyer_id = auth.uid()
        AND o.product_id = product_id
        AND lower(COALESCE(o.status, '')) IN ('completed', 'delivered')
    )
  );