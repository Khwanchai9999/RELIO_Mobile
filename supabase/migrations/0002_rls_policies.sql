create or replace function public.is_conversation_member(target_conversation uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = target_conversation and user_id = auth.uid()
  );
$$;

alter table public.profiles enable row level security;
alter table public.devices enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.attachments enable row level security;
alter table public.sos_events enable row level security;

create policy profiles_owner on public.profiles for all using (id = auth.uid()) with check (id = auth.uid());
create policy devices_owner on public.devices for all using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy conversations_member_read on public.conversations for select using (owner_user_id = auth.uid() or public.is_conversation_member(id));
create policy conversations_owner_write on public.conversations for all using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy members_member_read on public.conversation_members for select using (user_id = auth.uid() or public.is_conversation_member(conversation_id));
create policy members_owner_write on public.conversation_members for insert with check (public.is_conversation_member(conversation_id) or exists (select 1 from public.conversations where id = conversation_id and owner_user_id = auth.uid()));
create policy messages_member_read on public.messages for select using (public.is_conversation_member(conversation_id));
create policy messages_member_insert on public.messages for insert with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id));
create policy messages_sender_update on public.messages for update using (sender_id = auth.uid()) with check (sender_id = auth.uid());
create policy attachments_member_read on public.attachments for select using (owner_user_id = auth.uid() or exists (select 1 from public.messages m where m.id = message_id and public.is_conversation_member(m.conversation_id)));
create policy attachments_owner_write on public.attachments for all using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy sos_owner on public.sos_events for all using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
