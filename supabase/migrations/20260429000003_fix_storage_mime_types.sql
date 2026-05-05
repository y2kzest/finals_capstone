-- Fix products bucket: allow all common image mime types
-- (Removes the restrictive allowed_mime_types that was blocking image/png)
UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
  'image/svg+xml'
]
WHERE id = 'products';

-- Also fix logos and Permits buckets while we're here
UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
  'image/svg+xml'
]
WHERE id IN ('logos', 'Permits');
