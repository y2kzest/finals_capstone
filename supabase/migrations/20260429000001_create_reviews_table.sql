-- Create reviews table for product ratings and comments
CREATE TABLE IF NOT EXISTS reviews (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id      uuid NOT NULL,
  reviewer_id     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewer_name   text NOT NULL DEFAULT 'Buyer',
  rating          integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment         text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Index for fast per-product lookups (used in productdet.dart query)
CREATE INDEX IF NOT EXISTS reviews_product_id_idx ON reviews (product_id);

-- Enable RLS
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read reviews
CREATE POLICY "Authenticated users read reviews"
  ON reviews FOR SELECT
  TO authenticated
  USING (true);

-- A buyer can insert their own review
CREATE POLICY "Buyers insert own review"
  ON reviews FOR INSERT
  TO authenticated
  WITH CHECK (reviewer_id = auth.uid());

-- A buyer can delete their own review
CREATE POLICY "Buyers delete own review"
  ON reviews FOR DELETE
  TO authenticated
  USING (reviewer_id = auth.uid());
