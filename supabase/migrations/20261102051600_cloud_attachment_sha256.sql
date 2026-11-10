-- Keep the checksum optional for older metadata while validating new hashes.
alter table public.attachments
  add column if not exists sha256 text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'attachments_sha256_format'
      and conrelid = 'public.attachments'::regclass
  ) then
    alter table public.attachments
      add constraint attachments_sha256_format
      check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$');
  end if;
end
$$;
