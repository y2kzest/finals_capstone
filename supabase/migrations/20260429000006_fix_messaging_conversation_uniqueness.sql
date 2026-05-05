-- Align messaging with the app's one-conversation-per-buyer-seller behavior.
-- Safe to rerun.

-- Remove legacy unique constraints created by older messaging setups.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'conversations'::regclass
      AND contype = 'u'
  LOOP
    EXECUTE 'ALTER TABLE conversations DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
  END LOOP;
EXCEPTION WHEN others THEN NULL;
END $$;

DROP INDEX IF EXISTS conversations_buyer_seller_noproduct_idx;
DROP INDEX IF EXISTS conversations_buyer_seller_product_idx;

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

CREATE INDEX IF NOT EXISTS conversations_buyer_id_idx
  ON conversations (buyer_id);

CREATE INDEX IF NOT EXISTS conversations_seller_id_idx
  ON conversations (seller_id);

CREATE UNIQUE INDEX IF NOT EXISTS conversations_buyer_seller_idx
  ON conversations (buyer_id, seller_id);

ALTER TABLE messages REPLICA IDENTITY FULL;
ALTER TABLE conversations REPLICA IDENTITY FULL;

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