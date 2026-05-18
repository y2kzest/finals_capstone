-- Ensure the buyer notifications table exists with all required columns,
-- enable RLS, and wire up Realtime so the buyer overlay receives live events.

-- ── 1. Create table if it was never migrated ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notifications (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL,
  type        text        NOT NULL DEFAULT 'general',
  title       text        NOT NULL,
  message     text,
  order_id    uuid,
  is_read     boolean     NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ── 2. Add order_id column in case the table pre-dates this migration ─────────
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS order_id uuid;

-- ── 3. Enable RLS ─────────────────────────────────────────────────────────────
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- ── 4. RLS policies ───────────────────────────────────────────────────────────

-- Buyers can read only their own notifications (required for Realtime delivery)
DROP POLICY IF EXISTS "Users can read own notifications" ON public.notifications;
CREATE POLICY "Users can read own notifications"
ON public.notifications FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Buyers can mark their own notifications as read
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications"
ON public.notifications FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Allow any authenticated user to insert (seller inserting for buyer on status change,
-- or service-role webhook inserting for payment events).
DROP POLICY IF EXISTS "Allow insert into notifications" ON public.notifications;
CREATE POLICY "Allow insert into notifications"
ON public.notifications FOR INSERT
TO authenticated
WITH CHECK (true);

-- ── 5. Realtime: REPLICA IDENTITY FULL + publication ─────────────────────────
-- REPLICA IDENTITY FULL is required so the eq.<column> filter works for
-- Supabase Realtime filtered subscriptions.
ALTER TABLE public.notifications REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;
