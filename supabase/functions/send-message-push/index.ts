import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@9'

const expectedFirebaseProject = 'relio-17dc0'

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 })
  const webhookSecret = Deno.env.get('DATABASE_WEBHOOK_SECRET')
  if (!webhookSecret || request.headers.get('x-relio-webhook-secret') !== webhookSecret) {
    return new Response('Unauthorized', { status: 401 })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const rawServiceAccount = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')
  const projectId = Deno.env.get('FCM_PROJECT_ID')
  if (!supabaseUrl || !serviceRoleKey || !rawServiceAccount || projectId !== expectedFirebaseProject) {
    return new Response('Push service is not configured', { status: 503 })
  }

  let event: { type?: string; record?: { id?: string; conversation_id?: string; sender_id?: string } }
  let serviceAccount: { project_id?: string; client_email?: string; private_key?: string }
  try {
    event = await request.json()
    serviceAccount = JSON.parse(rawServiceAccount)
  } catch {
    return new Response('Invalid event', { status: 400 })
  }
  const message = event.record
  if (!message?.id || !message.conversation_id || !message.sender_id ||
      serviceAccount.project_id !== expectedFirebaseProject ||
      !serviceAccount.client_email || !serviceAccount.private_key) {
    return new Response('Invalid message event or service identity', { status: 400 })
  }

  const database = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { data: conversation, error: conversationError } = await database
    .from('conversations')
    .select('owner_user_id')
    .eq('id', message.conversation_id)
    .maybeSingle()
  if (conversationError || !conversation) return new Response('Conversation not found', { status: 404 })

  const { data: members, error: memberError } = await database
    .from('conversation_members')
    .select('user_id')
    .eq('conversation_id', message.conversation_id)
  if (memberError) return new Response('Recipient lookup failed', { status: 500 })
  const recipients = new Set<string>([
    conversation.owner_user_id,
    ...(members ?? []).map((member) => member.user_id as string),
  ])
  recipients.delete(message.sender_id)
  if (recipients.size === 0) return new Response('No recipients', { status: 200 })

  const auth = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  })
  const token = await auth.getAccessToken()
  if (!token.token) return new Response('FCM authentication unavailable', { status: 503 })

  const outcomes: Array<{ recipient: string; sent: number }> = []
  for (const recipientId of recipients) {
    const { error: claimError } = await database
      .from('push_delivery_dedup')
      .insert({ event_id: message.id, recipient_id: recipientId })
    if (claimError?.code === '23505') continue
    if (claimError) return new Response('Push delivery ledger unavailable', { status: 500 })

    const { data: devices, error: tokenError } = await database
      .from('device_push_tokens')
      .select('id, token')
      .eq('owner_user_id', recipientId)
    if (tokenError) {
      await database.from('push_delivery_dedup').delete()
        .eq('event_id', message.id).eq('recipient_id', recipientId)
      return new Response('Push token lookup failed', { status: 500 })
    }

    let sent = 0
    let failed = false
    for (const device of devices ?? []) {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${expectedFirebaseProject}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token.token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: { title: 'RELIO', body: 'คุณมีข้อความใหม่' },
              data: { route: `/chat/${message.conversation_id}`, eventId: message.id },
              android: { priority: 'high', notification: { channel_id: 'relio_messages' } },
            },
          }),
        },
      )
      if (response.ok) {
        sent += 1
      } else {
        const failure = await response.json().catch(() => ({})) as {
          error?: { details?: Array<{ errorCode?: string }> }
        }
        const invalidToken = failure.error?.details?.some((detail) =>
          detail.errorCode === 'UNREGISTERED' || detail.errorCode === 'INVALID_ARGUMENT')
        if (invalidToken) {
          await database.from('device_push_tokens').delete().eq('id', device.id)
        } else {
          failed = true
        }
      }
    }
    if (failed) {
      await database.from('push_delivery_dedup').delete()
        .eq('event_id', message.id).eq('recipient_id', recipientId)
      return new Response('One or more push deliveries failed', { status: 503 })
    }
    outcomes.push({ recipient: recipientId, sent })
  }

  return Response.json({ ok: true, deliveredRecipients: outcomes.length })
})
