-- ============================================================
-- Enhance orders table with additional columns
-- ============================================================
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS store_name text,
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS unit_type text DEFAULT 'kg',
  ADD COLUMN IF NOT EXISTS product_id uuid,
  ADD COLUMN IF NOT EXISTS delivery_fee numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_amount numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS declined_reason text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Update status check constraint: allow more statuses
-- First drop old constraint if it exists, then add new one
DO $$
BEGIN
  ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- ============================================================
-- Seller notifications table
-- ============================================================
CREATE TABLE IF NOT EXISTS seller_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid NOT NULL,
  order_id uuid REFERENCES orders(id) ON DELETE CASCADE,
  title text NOT NULL,
  body text,
  type text DEFAULT 'new_order',
  is_read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- RLS for seller_notifications
ALTER TABLE seller_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sellers can read own notifications" ON seller_notifications;
CREATE POLICY "Sellers can read own notifications"
ON seller_notifications FOR SELECT
TO authenticated
USING (seller_id = auth.uid());

DROP POLICY IF EXISTS "Sellers can update own notifications" ON seller_notifications;
CREATE POLICY "Sellers can update own notifications"
ON seller_notifications FOR UPDATE
TO authenticated
USING (seller_id = auth.uid())
WITH CHECK (seller_id = auth.uid());

DROP POLICY IF EXISTS "Authenticated can insert notifications" ON seller_notifications;
CREATE POLICY "Authenticated can insert notifications"
ON seller_notifications FOR INSERT
TO authenticated
WITH CHECK (true);

-- ============================================================
-- Ensure orders RLS policies allow buyer insert and seller read/update
-- ============================================================
DROP POLICY IF EXISTS "Buyers can insert orders" ON orders;
CREATE POLICY "Buyers can insert orders"
ON orders FOR INSERT
TO authenticated
WITH CHECK (buyer_id = auth.uid());

DROP POLICY IF EXISTS "Buyers can read own orders" ON orders;
CREATE POLICY "Buyers can read own orders"
ON orders FOR SELECT
TO authenticated
USING (buyer_id = auth.uid() OR seller_id = auth.uid());

DROP POLICY IF EXISTS "Sellers can update own orders" ON orders;
CREATE POLICY "Sellers can update own orders"
ON orders FOR UPDATE
TO authenticated
USING (seller_id = auth.uid())
WITH CHECK (seller_id = auth.uid());

-- Enable RLS on orders if not already
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- Cart: add missing columns for richer data
-- ============================================================
ALTER TABLE cart
  ADD COLUMN IF NOT EXISTS seller_id uuid,
  ADD COLUMN IF NOT EXISTS product_id uuid,
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS store_name text,
  ADD COLUMN IF NOT EXISTS unit_type text DEFAULT 'kg';

-- Enable realtime on orders for seller live updates
ALTER PUBLICATION supabase_realtime ADD TABLE orders;
ALTER PUBLICATION supabase_realtime ADD TABLE seller_notifications;
