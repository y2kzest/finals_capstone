-- qty was bigint but the app stores decimal quantities (e.g. 0.5 kg).
-- Change to numeric so both whole and fractional values are accepted.
ALTER TABLE orders
  ALTER COLUMN qty TYPE numeric(10, 3) USING qty::numeric;
