-- RELIO v0.9 communication/admin metadata. Message bodies stay member-only.

alter table public.profiles
  add column if not exists role text not null default 'user'
    check (role in ('user', 'rescuer', 'admin'));

-- The earlier owner-wide UPDATE policy would otherwise allow self-promotion.
drop policy if exists profiles_owner on public.profiles;
create policy profiles_owner_read on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_owner_insert on public.profiles
  for insert to authenticated with check (id = auth.uid() and role = 'user');
create policy profiles_owner_update on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Column grants make the role field immutable to ordinary authenticated users.
revoke update on public.profiles from authenticated;
grant update (display_name, updated_at) on public.profiles to authenticated;
create policy profiles_admin_read on public.profiles
  for select to authenticated using (public.is_admin());
create policy devices_admin_read on public.devices
  for select to authenticated using (public.is_admin());
create policy sos_admin_read on public.sos_events
  for select to authenticated using (public.is_admin());
create policy sos_admin_update on public.sos_events
  for update to authenticated using (public.is_admin())
  with check (public.is_admin());

create table public.message_receipts (
  message_id uuid not null references public.messages(id) on delete cascade,
  reader_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, reader_id)
);
create index message_receipts_reader_idx on public.message_receipts(reader_id, read_at desc);
alter table public.message_receipts enable row level security;
create policy message_receipts_member_read on public.message_receipts
  for select to authenticated using (
    reader_id = auth.uid()
    or exists (
      select 1 from public.messages m
      where m.id = message_id
        and (m.sender_id = auth.uid()
          or public.is_conversation_owner(m.conversation_id)
          or public.is_conversation_member(m.conversation_id))
    )
  );
create policy message_receipts_reader_insert on public.message_receipts
  for insert to authenticated with check (
    reader_id = auth.uid()
    and exists (
      select 1 from public.messages m
      where m.id = message_id
        and (public.is_conversation_owner(m.conversation_id)
          or public.is_conversation_member(m.conversation_id))
    )
  );

-- Server-only idempotency ledger for generic push events. No push body/content is stored.
create table public.push_delivery_dedup (
  event_id uuid not null,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  delivered_at timestamptz not null default now(),
  primary key (event_id, recipient_id)
);
alter table public.push_delivery_dedup enable row level security;
revoke all on public.push_delivery_dedup from anon, authenticated;

create table public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_user_id, device_id)
);
alter table public.device_push_tokens enable row level security;
create policy push_tokens_owner on public.device_push_tokens
  for all to authenticated using (owner_user_id = auth.uid())
  with check (owner_user_id = auth.uid());

create table public.rescue_status (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('available', 'responding', 'unavailable')),
  service_area text,
  updated_at timestamptz not null default now(),
  unique (user_id)
);
alter table public.rescue_status enable row level security;
create policy rescue_status_self_read on public.rescue_status
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy rescue_status_self_write on public.rescue_status
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create table public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  issue_code text not null check (issue_code in ('safety', 'abuse', 'technical', 'other')),
  state text not null default 'open' check (state in ('open', 'reviewing', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.user_reports enable row level security;
create policy reports_owner_read on public.user_reports
  for select to authenticated using (reporter_id = auth.uid() or public.is_admin());
create policy reports_owner_insert on public.user_reports
  for insert to authenticated with check (reporter_id = auth.uid());
create policy reports_admin_update on public.user_reports
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create table public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (action in ('role_changed', 'report_status_changed', 'rescue_status_changed', 'sos_status_changed')),
  target_type text not null check (target_type in ('profile', 'report', 'rescue_status', 'sos_event')),
  target_id uuid not null,
  created_at timestamptz not null default now()
);
create index admin_audit_logs_created_idx on public.admin_audit_logs(created_at desc);
alter table public.admin_audit_logs enable row level security;
create policy audit_admin_read on public.admin_audit_logs
  for select to authenticated using (public.is_admin());

create or replace function public.admin_dashboard_counts()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'devices', (select count(*) from public.devices),
    'sos', (select count(*) from public.sos_events),
    'audit', (select count(*) from public.admin_audit_logs)
  );
end;
$$;
revoke all on function public.admin_dashboard_counts() from public;
grant execute on function public.admin_dashboard_counts() to authenticated;

create or replace function public.admin_set_user_role(target_user_id uuid, new_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if new_role not in ('user', 'rescuer', 'admin') then
    raise exception 'invalid_role' using errcode = '22023';
  end if;
  if target_user_id = auth.uid() then
    raise exception 'self_role_change_forbidden' using errcode = '42501';
  end if;
  update public.profiles set role = new_role, updated_at = now()
    where id = target_user_id;
  if not found then raise exception 'profile_not_found' using errcode = 'P0002'; end if;
  insert into public.admin_audit_logs(actor_id, action, target_type, target_id)
    values (auth.uid(), 'role_changed', 'profile', target_user_id);
end;
$$;
revoke all on function public.admin_set_user_role(uuid, text) from public;
grant execute on function public.admin_set_user_role(uuid, text) to authenticated;

create or replace function public.admin_set_sos_state(target_event_id uuid, next_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  update public.sos_events set is_active = next_active, updated_at = now()
    where id = target_event_id;
  if not found then raise exception 'sos_event_not_found' using errcode = 'P0002'; end if;
  insert into public.admin_audit_logs(actor_id, action, target_type, target_id)
    values (auth.uid(), 'sos_status_changed', 'sos_event', target_event_id);
end;
$$;
revoke all on function public.admin_set_sos_state(uuid, boolean) from public;
grant execute on function public.admin_set_sos_state(uuid, boolean) to authenticated;

grant select on public.profiles, public.devices, public.sos_events,
  public.admin_audit_logs, public.user_reports, public.rescue_status
  to authenticated;
grant select, insert on public.message_receipts to authenticated;
grant select, insert, update, delete on public.device_push_tokens to authenticated;
grant select, insert, update on public.user_reports to authenticated;
grant select, insert, update on public.rescue_status to authenticated;

-- There is deliberately no Admin policy for public.messages or attachments.
