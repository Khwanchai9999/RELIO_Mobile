import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@9'
import {
  dispatchMessagePush,
  isAuthorizedWebhook,
  parseMessageRecord,
  resolvePushRecipients,
} from './logic.mjs'

const expectedFirebaseProject = 'relio-17dc0'

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }
  const webhookSecret = Deno.env.get('DATABASE_WEBHOOK_SECRET')
  if (!isAuthorizedWebhook(request, webhookSecret)) {
    return new Response('Unauthorized', { status: 401 })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const rawServiceAccount = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')
  const projectId = Deno.env.get('FCM_PROJECT_ID')
  if (
    !supabaseUrl ||
    !serviceRoleKey ||
    !rawServiceAccount ||
    projectId !== expectedFirebaseProject
  ) {
    return new Response('Push service is not configured', { status: 503 })
  }

  let event: unknown
  let serviceAccount: {
    project_id?: string
    client_email?: string
    private_key?: string
  }
  try {
    event = await request.json()
    serviceAccount = JSON.parse(rawServiceAccount)
  } catch {
    return new Response('Invalid event', { status: 400 })
  }
  const message = parseMessageRecord(event)
  if (
    !message ||
    serviceAccount.project_id !== expectedFirebaseProject ||
    !serviceAccount.client_email ||
    !serviceAccount.private_key
  ) {
    return new Response('Invalid message event or service identity', {
      status: 400,
    })
  }

  const database = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { data: conversation, error: conversationError } = await database
    .from('conversations')
    .select('id')
    .eq('id', message.conversationId)
    .maybeSingle()
  if (conversationError || !conversation) {
    return new Response('Conversation not found', { status: 404 })
  }

  const { data: members, error: memberError } = await database
    .from('conversation_members')
    .select('user_id')
    .eq('conversation_id', message.conversationId)
  if (memberError) {
    return new Response('Recipient lookup failed', { status: 500 })
  }
  const recipients = resolvePushRecipients(
    members,
    message.senderId,
  )
  if (recipients == null) {
    return new Response('Sender is not a conversation member', { status: 403 })
  }
  if (recipients.length === 0) return new Response('No recipients', { status: 200 })

  const auth = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  })
  const token = await auth.getAccessToken()
  if (!token.token) {
    return new Response('FCM authentication unavailable', { status: 503 })
  }

  const result = await dispatchMessagePush({
    message,
    recipients,
    claimRecipient: async (eventId, recipientId) => {
      const { error } = await database.from('push_delivery_dedup').insert({
        event_id: eventId,
        recipient_id: recipientId,
      })
      if (error?.code === '23505') return false
      if (error) throw error
      return true
    },
    listTokens: async (recipientId) => {
      const { data, error } = await database
        .from('device_push_tokens')
        .select('id, token')
        .eq('owner_user_id', recipientId)
      if (error) throw error
      return data ?? []
    },
    releaseRecipient: async (eventId, recipientId) => {
      await database.from('push_delivery_dedup').delete()
        .eq('event_id', eventId).eq('recipient_id', recipientId)
    },
    removeToken: async (deviceId) => {
      await database.from('device_push_tokens').delete().eq('id', deviceId)
    },
    sendToDevice: async (deviceToken, pushMessage) => {
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
              token: deviceToken,
              notification: { title: 'RELIO', body: 'คุณมีข้อความใหม่' },
              data: {
                route: `/chat/${pushMessage.conversationId}`,
                eventId: pushMessage.id,
              },
              android: {
                priority: 'high',
                notification: { channel_id: 'relio_messages' },
              },
            },
          }),
        },
      )
      if (response.ok) return { ok: true }
      const failure = (await response.json().catch(() => ({}))) as {
        error?: { details?: Array<{ errorCode?: string }> }
      }
      const invalidToken = failure.error?.details?.some((detail) =>
        detail.errorCode === 'UNREGISTERED' ||
        detail.errorCode === 'INVALID_ARGUMENT'
      )
      return { ok: false, invalidToken: Boolean(invalidToken) }
    },
  })

  if (result.json) {
    return Response.json(JSON.parse(result.body), { status: result.status })
  }
  return new Response(result.body, { status: result.status })
})
