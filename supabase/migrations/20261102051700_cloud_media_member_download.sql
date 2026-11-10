-- Keep relio-media private while allowing authenticated conversation members
-- to download an attachment only when its metadata belongs to that conversation.
drop policy if exists relio_media_read on storage.objects;
create policy relio_media_read on storage.objects
for select to authenticated
using (
  bucket_id = 'relio-media'
  and (storage.foldername(name))[1] = 'users'
  and (
    (storage.foldername(name))[2] = auth.uid()::text
    or exists (
      select 1
      from public.attachments a
      join public.messages m on m.id = a.message_id
      where a.storage_path = storage.objects.name
        and a.owner_user_id::text = (storage.foldername(name))[2]
        and public.is_conversation_member(m.conversation_id)
    )
  )
);
