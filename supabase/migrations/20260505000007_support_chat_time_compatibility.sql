-- ============================================================
-- Support chat compatibility for the admin website
-- The web support page expects conversations.last_message_time,
-- while the Flutter app writes conversations.last_message_at.
-- Keep both columns in sync so either client can work.
-- ============================================================

alter table public.conversations
  add column if not exists last_message_time timestamptz;

update public.conversations
set last_message_time = coalesce(last_message_time, last_message_at)
where last_message_at is not null;

create or replace function public.fn_sync_conversation_message_time()
returns trigger
language plpgsql
as $$
begin
  if new.last_message_time is null and new.last_message_at is not null then
    new.last_message_time := new.last_message_at;
  elsif new.last_message_at is null and new.last_message_time is not null then
    new.last_message_at := new.last_message_time;
  elsif new.last_message_at is distinct from old.last_message_at then
    new.last_message_time := new.last_message_at;
  elsif new.last_message_time is distinct from old.last_message_time then
    new.last_message_at := new.last_message_time;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_conversation_message_time on public.conversations;
create trigger trg_sync_conversation_message_time
before insert or update on public.conversations
for each row
execute function public.fn_sync_conversation_message_time();
