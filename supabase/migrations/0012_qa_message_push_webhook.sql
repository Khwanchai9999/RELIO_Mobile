create extension if not exists pg_net;

create or replace function public.dispatch_message_push_webhook()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, vault, net, pg_temp
as $$
declare
  webhook_url text;
  webhook_secret text;
begin
  select decrypted_secret into webhook_url
  from vault.decrypted_secrets
  where name = 'relio_message_push_webhook_url'
  order by created_at desc
  limit 1;

  select decrypted_secret into webhook_secret
  from vault.decrypted_secrets
  where name = 'relio_message_push_webhook_secret'
  order by created_at desc
  limit 1;

  -- Push is optional; local SQLite/Cloud message persistence must not depend on it.
  if webhook_url is null or webhook_secret is null
    or webhook_url !~ '^https://[a-z0-9]{20}\.supabase\.co/functions/v1/send-message-push$'
    or length(webhook_secret) < 32 then
    return new;
  end if;

  perform net.http_post(
    url := webhook_url,
    body := jsonb_build_object(
      'type', 'INSERT',
      'schema', 'public',
      'table', 'messages',
      'record', jsonb_build_object(
        'id', new.id,
        'conversation_id', new.conversation_id,
        'sender_id', new.sender_id
      )
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-relio-webhook-secret', webhook_secret
    ),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;

revoke all on function public.dispatch_message_push_webhook() from public;
revoke all on function public.dispatch_message_push_webhook() from anon, authenticated;

drop trigger if exists messages_push_webhook on public.messages;
create trigger messages_push_webhook
after insert on public.messages
for each row execute function public.dispatch_message_push_webhook();
