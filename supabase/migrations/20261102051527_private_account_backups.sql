-- Account-private recovery copies. These rows never join shared conversations.
create table public.private_backup_records (
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  record_type text not null check (record_type in ('conversation', 'message')),
  source_id text not null check (length(source_id) between 1 and 200),
  payload jsonb not null check (
    jsonb_typeof(payload) = 'object' and pg_column_size(payload) <= 2097152
  ),
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (owner_user_id, record_type, source_id)
);

alter table public.private_backup_records enable row level security;
revoke all on public.private_backup_records from public, anon, authenticated;
grant select, insert, update on public.private_backup_records to authenticated;

create policy private_backup_records_owner_read
  on public.private_backup_records for select to authenticated
  using ((select auth.uid()) = owner_user_id);
create policy private_backup_records_owner_insert
  on public.private_backup_records for insert to authenticated
  with check ((select auth.uid()) = owner_user_id);
create policy private_backup_records_owner_update
  on public.private_backup_records for update to authenticated
  using ((select auth.uid()) = owner_user_id)
  with check ((select auth.uid()) = owner_user_id);

-- Private backup media shares the existing private bucket and owner folder.
-- The insert/update/read predicates are already restricted to users/<auth.uid()>.
-- Its separate private-backups path is intentionally excluded from shared-chat
-- membership access in the separate shared-media migration cannot read these
-- paths because there is no public.attachments metadata row for them.
