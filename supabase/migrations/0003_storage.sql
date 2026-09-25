insert into storage.buckets (id, name, public)
values ('relio-media', 'relio-media', false)
on conflict (id) do update set public = excluded.public;

create policy relio_media_read on storage.objects
for select to authenticated
using ((storage.foldername(name))[1] = 'users' and (storage.foldername(name))[2] = auth.uid()::text);

create policy relio_media_insert on storage.objects
for insert to authenticated
with check ((bucket_id = 'relio-media') and (storage.foldername(name))[1] = 'users' and (storage.foldername(name))[2] = auth.uid()::text);

create policy relio_media_update on storage.objects
for update to authenticated
using (bucket_id = 'relio-media' and (storage.foldername(name))[1] = 'users' and (storage.foldername(name))[2] = auth.uid()::text)
with check (bucket_id = 'relio-media' and (storage.foldername(name))[1] = 'users' and (storage.foldername(name))[2] = auth.uid()::text);

create policy relio_media_delete on storage.objects
for delete to authenticated
using (bucket_id = 'relio-media' and (storage.foldername(name))[1] = 'users' and (storage.foldername(name))[2] = auth.uid()::text);
