-- PayMongo payment integration columns.
--
-- payment_method:  'cod' | 'gcash' | 'maya' | 'grab_pay' | 'card'
-- payment_status:  'pending' | 'paid' | 'failed' | 'refunded'
--   Defaults to 'paid' so existing COD/pickup orders remain visible to sellers
--   without backfill. Online payment orders insert with 'pending' explicitly.

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'cod',
  ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'paid',
  ADD COLUMN IF NOT EXISTS paymongo_source_id TEXT,
  ADD COLUMN IF NOT EXISTS paymongo_payment_intent_id TEXT,
  ADD COLUMN IF NOT EXISTS paymongo_payment_id TEXT,
  ADD COLUMN IF NOT EXISTS paymongo_checkout_url TEXT,
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS orders_paymongo_source_idx
  ON orders (paymongo_source_id)
  WHERE paymongo_source_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS orders_paymongo_intent_idx
  ON orders (paymongo_payment_intent_id)
  WHERE paymongo_payment_intent_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS orders_payment_status_idx
  ON orders (payment_status);
