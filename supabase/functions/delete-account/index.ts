import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 })
  }

  const authorization = request.headers.get('Authorization')
  const match = authorization?.match(/^Bearer\s+(.+)$/i)
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!match) {
    return Response.json({ error: 'unauthorized' }, { status: 401 })
  }
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return Response.json({ error: 'delete_unavailable' }, { status: 503 })
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${match[1]}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { data, error: authError } = await userClient.auth.getUser(match[1])
  if (authError || !data.user) {
    return Response.json({ error: 'unauthorized' }, { status: 401 })
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const userId = data.user.id

  // Keep shared chat rows and their foreign keys, but remove personal account data.
  const cleanupResults = await Promise.all([
    admin.from('device_push_tokens').delete().eq('owner_user_id', userId),
    admin.from('push_delivery_dedup').delete().eq('recipient_id', userId),
    admin.from('devices').delete().eq('owner_user_id', userId),
    admin.from('sos_events').delete().eq('owner_user_id', userId),
    admin.from('rescue_status').delete().eq('user_id', userId),
    admin.from('message_receipts').delete().eq('reader_id', userId),
    admin.from('user_reports').delete().eq('reporter_id', userId),
    admin
      .from('profiles')
      .upsert(
        { id: userId, display_name: 'บัญชีที่ลบแล้ว', role: 'user' },
        { onConflict: 'id' },
      ),
  ])
  if (cleanupResults.some(({ error }) => error)) {
    return Response.json({ error: 'delete_unavailable' }, { status: 503 })
  }

  // Replace sign-in credentials and personal metadata; retain the UUID only as
  // an opaque tombstone for shared messages, memberships, and audit references.
  const { error: anonymizeError } = await admin.auth.admin.updateUserById(userId, {
    email: `deleted+${userId}@account-deleted.invalid`,
    password: `${crypto.randomUUID()}${crypto.randomUUID()}!aA1`,
    email_confirm: true,
    user_metadata: {},
    app_metadata: {},
    ban_duration: '876000h',
  })
  if (anonymizeError) {
    return Response.json({ error: 'account_delete_failed' }, { status: 500 })
  }

  // Best effort: the current app also clears its local session after success.
  await admin.auth.admin.signOut(match[1], 'global').catch(() => ({ error: true }))
  return new Response(null, { status: 204 })
})
