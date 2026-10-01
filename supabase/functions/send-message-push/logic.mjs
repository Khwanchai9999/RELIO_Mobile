const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function isAuthorizedWebhook(request, expectedSecret) {
  return Boolean(expectedSecret) &&
    request.headers.get('x-relio-webhook-secret') === expectedSecret
}

export function parseMessageRecord(event) {
  const record = event?.record
  if (event?.type !== 'INSERT' ||
      !uuidPattern.test(record?.id ?? '') ||
      !uuidPattern.test(record?.conversation_id ?? '') ||
      !uuidPattern.test(record?.sender_id ?? '')) {
    return null
  }
  return {
    id: record.id,
    conversationId: record.conversation_id,
    senderId: record.sender_id,
  }
}

export function resolvePushRecipients(members, senderId) {
  const memberIds = new Set((members ?? []).map((member) => member.user_id))
  if (!memberIds.has(senderId)) return null
  memberIds.delete(senderId)
  return [...memberIds]
}

export async function dispatchMessagePush({
  message,
  recipients,
  listTokens,
  claimRecipient,
  releaseRecipient,
  removeToken,
  sendToDevice,
}) {
  if (recipients == null) return { status: 403, body: 'Sender is not a member' }
  if (recipients.length === 0) return { status: 200, body: 'No recipients' }

  let deliveredRecipients = 0
  for (const recipientId of recipients) {
    let claimed
    try {
      claimed = await claimRecipient(message.id, recipientId)
    } catch {
      return { status: 500, body: 'Push delivery ledger unavailable' }
    }
    if (claimed === false) continue

    let devices
    try {
      devices = await listTokens(recipientId)
    } catch {
      await releaseRecipient(message.id, recipientId)
      return { status: 500, body: 'Push token lookup failed' }
    }

    let failed = false
    for (const device of devices) {
      let result
      try {
        result = await sendToDevice(device.token, message)
      } catch {
        failed = true
        continue
      }
      if (result.ok) continue
      if (result.invalidToken) {
        await removeToken(device.id)
      } else {
        failed = true
      }
    }
    if (failed) {
      await releaseRecipient(message.id, recipientId)
      return { status: 503, body: 'One or more push deliveries failed' }
    }
    deliveredRecipients++
  }
  return {
    status: 200,
    body: JSON.stringify({ ok: true, deliveredRecipients }),
    json: true,
  }
}
