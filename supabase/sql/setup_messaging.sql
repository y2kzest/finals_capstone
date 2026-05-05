-- ============================================================
-- MESSAGING SETUP — Safe to run multiple times (idempotent)
-- Paste this entire script into Supabase SQL Editor and run it.
-- ============================================================

-- 1. Create conversations table
CREATE TABLE IF NOT EXISTS conversations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seller_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id      uuid,
  last_message    text,
  last_message_at timestamptz DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Drop old inline UNIQUE(buyer_id, seller_id, product_id) constraint if it exists
-- (it doesn't enforce uniqueness when product_id IS NULL, so we replace it)
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'conversations'::regclass AND contype = 'u'
  LOOP
    EXECUTE 'ALTER TABLE conversations DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
  END LOOP;
EXCEPTION WHEN others THEN NULL;
END $$;

-- 2. Create messages table
CREATE TABLE IF NOT EXISTS messages (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content         text NOT NULL,
  is_read         boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON messages (conversation_id);
CREATE INDEX IF NOT EXISTS messages_sender_id_idx       ON messages (sender_id);

-- Collapse any legacy duplicates to a single buyer+seller conversation.
-- Keep the most recently active conversation and move its messages over.
WITH ranked AS (
  SELECT
    id,
    FIRST_VALUE(id) OVER (
      PARTITION BY buyer_id, seller_id
      ORDER BY COALESCE(last_message_at, created_at) DESC, created_at DESC, id DESC
    ) AS keep_id
  FROM conversations
), duplicates AS (
  SELECT id, keep_id
  FROM ranked
  WHERE id <> keep_id
)
UPDATE messages m
SET conversation_id = d.keep_id
FROM duplicates d
WHERE m.conversation_id = d.id;

WITH ranked AS (
  SELECT
    id,
    FIRST_VALUE(id) OVER (
      PARTITION BY buyer_id, seller_id
      ORDER BY COALESCE(last_message_at, created_at) DESC, created_at DESC, id DESC
    ) AS keep_id
  FROM conversations
), duplicates AS (
  SELECT id
  FROM ranked
  WHERE id <> keep_id
)
DELETE FROM conversations c
USING duplicates d
WHERE c.id = d.id;

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS conversations_buyer_id_idx  ON conversations (buyer_id);
CREATE INDEX IF NOT EXISTS conversations_seller_id_idx ON conversations (seller_id);

-- One conversation per buyer+seller pair (product_id is always NULL in app code)
CREATE UNIQUE INDEX IF NOT EXISTS conversations_buyer_seller_idx
  ON conversations (buyer_id, seller_id);

-- 3. Enable Row Level Security
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages      ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies (drop first so script is re-runnable)
DROP POLICY IF EXISTS "Participants read conversations"  ON conversations;
DROP POLICY IF EXISTS "Buyers insert conversations"      ON conversations;
DROP POLICY IF EXISTS "Participants update conversations" ON conversations;
DROP POLICY IF EXISTS "Participants read messages"       ON messages;
DROP POLICY IF EXISTS "Participants insert messages"     ON messages;
DROP POLICY IF EXISTS "Participants update messages"     ON messages;

CREATE POLICY "Participants read conversations"
  ON conversations FOR SELECT TO authenticated
  USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

CREATE POLICY "Buyers insert conversations"
  ON conversations FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "Participants update conversations"
  ON conversations FOR UPDATE TO authenticated
  USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

CREATE POLICY "Participants read messages"
  ON messages FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
  );

CREATE POLICY "Participants insert messages"
  ON messages FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
  );

CREATE POLICY "Participants update messages"
  ON messages FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
  );

-- 5. Required for Realtime filtered subscriptions
--    (allows filtering by conversation_id in Flutter)
ALTER TABLE messages      REPLICA IDENTITY FULL;
ALTER TABLE conversations REPLICA IDENTITY FULL;

-- 6. Add tables to Realtime publication (safe — checks first)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE messages;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
  END IF;
END $$;

-- 7. Ensure store_address column exists on seller_profiles
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS store_address text;

-- 8. Ensure store_address column exists on orders
ALTER TABLE orders ADD COLUMN IF NOT EXISTS store_address text;

-- Done! Messaging is now fully set up.
