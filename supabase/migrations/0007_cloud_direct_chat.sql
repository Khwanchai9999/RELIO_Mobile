-- A direct Cloud conversation is shared only after one account explicitly
-- supplies the other account's RELIO Cloud user ID.
alter table public.conversations
  add column if not exists direct_key text;

-- Pull cursors use this database-controlled ordering field, never the sender's
-- device clock, so delayed/fast client clocks cannot poison new-page ordering.
create or replace function public.stamp_cloud_message_server_time()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  last_created_at timestamptz;
  server_created_at timestamptz;
begin
  -- Serialize only this conversation's inserts, then guarantee a strict
  -- per-conversation cursor even if the system clock repeats a microsecond.
  perform 1 from public.conversations
  where id = new.conversation_id
  for update;
  select max(created_at) into last_created_at
  from public.messages
  where conversation_id = new.conversation_id;
  server_created_at := clock_timestamp();
  if last_created_at is not null and server_created_at <= last_created_at then
    server_created_at := last_created_at + interval '1 microsecond';
  end if;
  new.created_at := server_created_at;
  new.updated_at := new.created_at;
  return new;
end;
$$;
drop trigger if exists messages_server_time on public.messages;
create trigger messages_server_time
before insert on public.messages
for each row execute function public.stamp_cloud_message_server_time();

create unique index if not exists conversations_direct_key_unique
  on public.conversations (direct_key)
  where direct_key is not null;

-- Membership writes happen only through this SECURITY DEFINER RPC. Clients
-- cannot add arbitrary accounts to an existing conversation with table INSERT.
drop policy if exists members_owner_write on public.conversation_members;
revoke insert, update, delete on public.conversation_members from authenticated;
grant select on public.conversation_members to authenticated;

-- Conversation identity and membership are server-managed. In particular,
-- clients cannot forge a direct_key to attach unrelated users to old data.
drop policy if exists conversations_member_read on public.conversations;
drop policy if exists conversations_owner_write on public.conversations;
create policy conversations_member_read on public.conversations
  for select to authenticated
  using (public.is_conversation_member(id));
revoke insert, update, delete on public.conversations from authenticated;
grant select on public.conversations to authenticated;

-- Message content is immutable by UUID. Delivery/read state is reconciled
-- through receipts and local state, not client-side mutation of Cloud rows.
drop policy if exists messages_sender_update on public.messages;
revoke update on public.messages from authenticated;

drop policy if exists messages_member_read on public.messages;
create policy messages_member_read on public.messages
  for select to authenticated
  using (public.is_conversation_member(conversation_id));
drop policy if exists messages_member_insert on public.messages;
create policy messages_member_insert on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_conversation_member(conversation_id)
  );

drop policy if exists attachments_member_read on public.attachments;
create policy attachments_member_read on public.attachments
  for select to authenticated
  using (
    exists (
      select 1 from public.messages m
      where m.id = message_id
        and public.is_conversation_member(m.conversation_id)
    )
  );
drop policy if exists attachments_owner_write on public.attachments;
create policy attachments_owner_write on public.attachments
  for all to authenticated
  using (
    owner_user_id = auth.uid()
    and exists (
      select 1 from public.messages m
      where m.id = message_id
        and public.is_conversation_member(m.conversation_id)
    )
  )
  with check (
    owner_user_id = auth.uid()
    and exists (
      select 1 from public.messages m
      where m.id = message_id
        and public.is_conversation_member(m.conversation_id)
    )
  );

-- Preserve access to pre-existing owner conversations after membership becomes
-- the sole message authorization path.
insert into public.conversation_members (conversation_id, user_id)
select id, owner_user_id from public.conversations
on conflict (conversation_id, user_id) do nothing;

create or replace function public.create_or_get_direct_conversation(
  target_user_id uuid
)
returns table (
  conversation_id uuid,
  peer_user_id uuid,
  peer_display_name text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  canonical_key text;
  result_id uuid;
begin
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if target_user_id is null or target_user_id = current_user_id then
    raise exception 'invalid_direct_peer' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = target_user_id) then
    raise exception 'direct_peer_not_found' using errcode = 'P0002';
  end if;

  canonical_key := least(current_user_id::text, target_user_id::text)
    || ':' || greatest(current_user_id::text, target_user_id::text);
  insert into public.conversations (id, owner_user_id, direct_key)
  values (gen_random_uuid(), current_user_id, canonical_key)
  on conflict (direct_key) where direct_key is not null
  do update set updated_at = greatest(
    public.conversations.updated_at, excluded.updated_at
  )
  returning id into result_id;

  insert into public.conversation_members (conversation_id, user_id)
  values (result_id, current_user_id), (result_id, target_user_id)
  on conflict (conversation_id, user_id) do nothing;

  return query
  select result_id, target_user_id,
    coalesce(p.display_name, ''), c.updated_at
  from public.conversations c
  left join public.profiles p on p.id = target_user_id
  where c.id = result_id;
end;
$$;
revoke all on function public.create_or_get_direct_conversation(uuid) from public;
grant execute on function public.create_or_get_direct_conversation(uuid)
  to authenticated;

create or replace function public.list_my_direct_conversations()
returns table (
  conversation_id uuid,
  peer_user_id uuid,
  peer_display_name text,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select c.id, peer.user_id, coalesce(p.display_name, ''), c.updated_at
  from public.conversation_members mine
  join public.conversations c on c.id = mine.conversation_id
  join public.conversation_members peer
    on peer.conversation_id = c.id and peer.user_id <> auth.uid()
  left join public.profiles p on p.id = peer.user_id
  where mine.user_id = auth.uid()
    and auth.uid() is not null
    and c.direct_key is not null;
$$;
revoke all on function public.list_my_direct_conversations() from public;
grant execute on function public.list_my_direct_conversations() to authenticated;

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
  if page_size < 1 or page_size > 250 then
    raise exception 'invalid_page_size' using errcode = '22023';
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

create index if not exists conversation_members_user_conversation_idx
  on public.conversation_members (user_id, conversation_id);
create index if not exists message_receipts_read_cursor_idx
  on public.message_receipts (read_at, message_id, reader_id);
