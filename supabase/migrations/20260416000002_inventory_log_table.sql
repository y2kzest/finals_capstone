-- Inventory log table for tracking stock adjustments and sales
CREATE TABLE IF NOT EXISTS inventory_log (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id text NOT NULL,
  product_name text NOT NULL,
  type text NOT NULL CHECK (type IN ('sale', 'restock', 'adjustment', 'removal')),
  quantity integer NOT NULL,
  price_per_unit numeric(10,2) DEFAULT 0,
  total_amount numeric(10,2) DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
);

-- Index for fast lookups by seller
CREATE INDEX IF NOT EXISTS idx_inventory_log_user_id ON inventory_log(user_id);
CREATE INDEX IF NOT EXISTS idx_inventory_log_created_at ON inventory_log(created_at DESC);

-- Enable RLS
ALTER TABLE inventory_log ENABLE ROW LEVEL SECURITY;

-- Sellers can only see and insert their own logs
DROP POLICY IF EXISTS "Sellers can view own inventory logs" ON inventory_log;
CREATE POLICY "Sellers can view own inventory logs"
  ON inventory_log FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Sellers can insert own inventory logs" ON inventory_log;
CREATE POLICY "Sellers can insert own inventory logs"
  ON inventory_log FOR INSERT
  WITH CHECK (auth.uid() = user_id);
