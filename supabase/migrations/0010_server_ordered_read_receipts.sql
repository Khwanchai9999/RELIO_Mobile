-- The read-receipt keyset cursor uses read_at as its leading field. Client
-- clocks can tie or move backwards, so stamp each conversation's receipts
-- strictly after the existing server-ordered cursor while holding its row lock.
create or replace function public.stamp_read_receipt_server_time()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_conversation_id uuid;
  last_read_at timestamptz;
begin
  select m.conversation_id into target_conversation_id
  from public.messages m
  where m.id = new.message_id;
  if target_conversation_id is null then
    raise exception 'read_receipt_message_not_found' using errcode = 'P0002';
  end if;

  perform 1 from public.conversations c
  where c.id = target_conversation_id
  for update;
  select max(r.read_at) into last_read_at
  from public.message_receipts r
  join public.messages m on m.id = r.message_id
  where m.conversation_id = target_conversation_id;

  new.read_at := clock_timestamp();
  if last_read_at is not null and new.read_at <= last_read_at then
    new.read_at := last_read_at + interval '1 microsecond';
  end if;
  return new;
end;
$$;
revoke all on function public.stamp_read_receipt_server_time() from public;

drop trigger if exists message_receipts_server_time on public.message_receipts;
create trigger message_receipts_server_time
before insert on public.message_receipts
for each row execute function public.stamp_read_receipt_server_time();
