-- RELIO v0.7 hardening. Drift/SQLite remains the offline source of truth.
-- This migration makes owner conversations valid message roots and narrows
-- Storage policies to the private RELIO bucket.

create or replace function public.is_conversation_owner(target_conversation uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.conversations
    where id = target_conversation and owner_user_id = auth.uid()
  );
$$;

drop policy if exists messages_member_read on public.messages;
create policy messages_member_read on public.messages
for select using (
  sender_id = auth.uid()
  or public.is_conversation_owner(conversation_id)
  or public.is_conversation_member(conversation_id)
);

drop policy if exists messages_member_insert on public.messages;
create policy messages_member_insert on public.messages
for insert with check (
  sender_id = auth.uid()
  and (
    public.is_conversation_owner(conversation_id)
    or public.is_conversation_member(conversation_id)
  )
);

drop policy if exists attachments_member_read on public.attachments;
create policy attachments_member_read on public.attachments
for select using (
  owner_user_id = auth.uid()
  or exists (
    select 1
    from public.messages m
    where m.id = message_id
      and (
        m.sender_id = auth.uid()
        or public.is_conversation_owner(m.conversation_id)
        or public.is_conversation_member(m.conversation_id)
      )
  )
);

drop policy if exists relio_media_read on storage.objects;
create policy relio_media_read on storage.objects
for select to authenticated
using (
  bucket_id = 'relio-media'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists relio_media_insert on storage.objects;
create policy relio_media_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'relio-media'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists relio_media_update on storage.objects;
create policy relio_media_update on storage.objects
for update to authenticated
using (
  bucket_id = 'relio-media'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
)
with check (
  bucket_id = 'relio-media'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists relio_media_delete on storage.objects;
create policy relio_media_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'relio-media'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
);
