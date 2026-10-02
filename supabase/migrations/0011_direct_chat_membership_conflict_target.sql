-- `RETURNS TABLE` declares `conversation_id` as a PL/pgSQL output variable.
-- Name the membership primary-key constraint to avoid an ambiguous column
-- reference in `ON CONFLICT (conversation_id, user_id)`.
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
  on conflict on constraint conversation_members_pkey do nothing;

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
