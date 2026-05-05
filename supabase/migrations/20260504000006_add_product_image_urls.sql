-- Add image_urls array column to product table for multiple product images.
-- image_url (single) is kept for backward compatibility; image_urls stores all images.
ALTER TABLE product ADD COLUMN IF NOT EXISTS image_urls text[] DEFAULT '{}';

-- Backfill existing rows: if image_url is set and image_urls is empty, copy it in.
UPDATE product
  SET image_urls = ARRAY[image_url]
  WHERE image_url IS NOT NULL
    AND image_url <> ''
    AND (image_urls IS NULL OR image_urls = '{}');
