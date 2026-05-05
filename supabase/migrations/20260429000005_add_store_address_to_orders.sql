-- Add store address columns to orders table so pickup location is
-- recorded at time of order and consistently displayed to buyers.
ALTER TABLE orders ADD COLUMN IF NOT EXISTS store_address text;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS stall_number  text;
