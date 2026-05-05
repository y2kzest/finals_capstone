-- ============================================================
-- Support chat: add unread_admin to conversations +
-- trigger to auto-increment it when a buyer sends a message.
-- ============================================================

-- 1. Add unread_admin column (admin's unread badge count)
alter table public.conversations
  add column if not exists unread_admin integer not null default 0;

-- 2. Function: increment unread_admin when buyer sends a message
create or replace function public.fn_increment_unread_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only increment if the sender is the buyer (not the seller/admin)
  update public.conversations
  set unread_admin = unread_admin + 1
  where id = new.conversation_id
    and buyer_id = new.sender_id;

  return new;
end;
$$;

-- 3. Attach trigger to messages table
drop trigger if exists trg_increment_unread_admin on public.messages;
create trigger trg_increment_unread_admin
  after insert on public.messages
  for each row
  execute function public.fn_increment_unread_admin();
