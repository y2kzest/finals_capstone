-- Add auto_accept_orders column to seller_profiles
-- When true, incoming pending orders are automatically accepted (moved to 'preparing')

ALTER TABLE seller_profiles
  ADD COLUMN IF NOT EXISTS auto_accept_orders BOOLEAN NOT NULL DEFAULT FALSE;
