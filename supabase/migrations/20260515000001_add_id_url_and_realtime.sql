-- Government ID submitted during seller onboarding.
ALTER TABLE public.seller_profiles
  ADD COLUMN IF NOT EXISTS id_url text;

-- Force PostgREST to refresh its schema cache so newly added
-- columns are visible to the API immediately.
NOTIFY pgrst, 'reload schema';

-- Make sure every table the app subscribes to in realtime is
-- in the supabase_realtime publication AND has REPLICA IDENTITY
-- FULL so filtered subscriptions (eq.<column>) work.
DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'orders',
    'cart',
    'products',
    'seller_profiles',
    'inventory_log',
    'notifications',
    'seller_notifications',
    'messages',
    'conversations',
    'profile'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    -- Only run if the table actually exists in this schema.
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = t
    ) THEN
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);

      IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = t
      ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      END IF;
    END IF;
  END LOOP;
END $$;
