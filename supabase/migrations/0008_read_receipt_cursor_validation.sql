-- Reject malformed cursor tuples and explicit NULL limits before pagination.
-- A partial tuple makes PostgreSQL row comparisons evaluate to NULL, which can
-- silently skip receipts; LIMIT NULL can also remove the page bound entirely.
create or replace function public.fetch_conversation_read_receipts(
  target_conversation_id uuid,
  after_read_at timestamptz default null,
  after_message_id uuid default null,
  after_reader_id uuid default null,
  page_size integer default 100
)
returns table (message_id uuid, reader_id uuid, read_at timestamptz)
language plpgsql
security invoker
set search_path = public
stable
as $$
begin
  if page_size is null or page_size < 1 or page_size > 250 then
    raise exception 'invalid_page_size' using errcode = '22023';
  end if;
  if not (
    (after_read_at is null and after_message_id is null and after_reader_id is null)
    or
    (after_read_at is not null and after_message_id is not null and after_reader_id is not null)
  ) then
    raise exception 'invalid_read_receipt_cursor' using errcode = '22023';
  end if;

  return query
  select r.message_id, r.reader_id, r.read_at
  from public.message_receipts r
  join public.messages m on m.id = r.message_id
  where m.conversation_id = target_conversation_id
    and (after_read_at is null or
      (r.read_at, r.message_id, r.reader_id) >
      (after_read_at, after_message_id, after_reader_id))
  order by r.read_at, r.message_id, r.reader_id
  limit page_size;
end;
$$;

revoke all on function public.fetch_conversation_read_receipts(
  uuid, timestamptz, uuid, uuid, integer
) from public;
grant execute on function public.fetch_conversation_read_receipts(
  uuid, timestamptz, uuid, uuid, integer
) to authenticated;
