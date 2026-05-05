-- Messaging feature: conversations + messages tables

-- 1. conversations: one row per buyer<->seller pair (optionally tied to a product)
CREATE TABLE IF NOT EXISTS conversations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seller_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id     uuid,
  last_message   text,
  last_message_at timestamptz DEFAULT now(),
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (buyer_id, seller_id, product_id)
);

CREATE INDEX IF NOT EXISTS conversations_buyer_id_idx  ON conversations (buyer_id);
CREATE INDEX IF NOT EXISTS conversations_seller_id_idx ON conversations (seller_id);

-- 2. messages: individual chat messages
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

-- 3. RLS
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages      ENABLE ROW LEVEL SECURITY;

-- Participants can read their own conversations
CREATE POLICY "Participants read conversations"
  ON conversations FOR SELECT
  TO authenticated
  USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

-- Buyers can start a conversation
CREATE POLICY "Buyers insert conversations"
  ON conversations FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = buyer_id);

-- Participants can update last_message / last_message_at
CREATE POLICY "Participants update conversations"
  ON conversations FOR UPDATE
  TO authenticated
  USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

-- Participants can read messages in their conversations
CREATE POLICY "Participants read messages"
  ON messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
  );

-- Participants can send messages
CREATE POLICY "Participants insert messages"
  ON messages FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
  );

-- Mark messages as read
CREATE POLICY "Participants update messages"
  ON messages FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
  );

-- 4. Add store_address column to seller_profiles if it doesn't exist yet
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS store_address   text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS stall_number    text;
ALTER TABLE seller_profiles ADD COLUMN IF NOT EXISTS banner_url      text;

-- 5. Enable Realtime for messaging tables
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
