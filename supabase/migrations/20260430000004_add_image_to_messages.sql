-- Allow image-only messages (content can be empty)
ALTER TABLE messages ALTER COLUMN content DROP NOT NULL;
ALTER TABLE messages ALTER COLUMN content SET DEFAULT '';

-- Store image URL on a message
ALTER TABLE messages ADD COLUMN IF NOT EXISTS image_url text;

-- Create chat_images storage bucket (public so images can be displayed inline)
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat_images', 'chat_images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Storage policies for chat_images
DROP POLICY IF EXISTS "Public read chat images" ON storage.objects;
CREATE POLICY "Public read chat images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'chat_images');

DROP POLICY IF EXISTS "Authenticated upload chat images" ON storage.objects;
CREATE POLICY "Authenticated upload chat images"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'chat_images' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Owner delete chat images" ON storage.objects;
CREATE POLICY "Owner delete chat images"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'chat_images' AND owner = auth.uid());
