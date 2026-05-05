-- Add karinderya / flexible product fields to the product table
ALTER TABLE public.product
  ADD COLUMN IF NOT EXISTS product_type text DEFAULT 'retail',
  ADD COLUMN IF NOT EXISTS pricing_basis text,
  ADD COLUMN IF NOT EXISTS variants text,
  ADD COLUMN IF NOT EXISTS prep_time text,
  ADD COLUMN IF NOT EXISTS daily_available boolean DEFAULT true;
