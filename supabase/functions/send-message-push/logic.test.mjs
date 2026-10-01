import assert from 'node:assert/strict'
import test from 'node:test'
import {
  dispatchMessagePush,
  isAuthorizedWebhook,
  parseMessageRecord,
  resolvePushRecipients,
} from './logic.mjs'

const owner = '10000000-0000-4000-8000-000000000001'
const peer = '10000000-0000-4000-8000-000000000002'
const outsider = '10000000-0000-4000-8000-000000000003'
const eventId = '20000000-0000-4000-8000-000000000001'
const conversationId = '30000000-0000-4000-8000-000000000001'
const message = { id: eventId, conversationId, senderId: owner }

test('webhook secret is required and compared exactly', () => {
  const request = new Request('https://local.test', {
    headers: { 'x-relio-webhook-secret': 'secret' },
  })
  assert.equal(isAuthorizedWebhook(request, 'secret'), true)
  assert.equal(isAuthorizedWebhook(request, ''), false)
  assert.equal(isAuthorizedWebhook(request, 'other'), false)
})

test('push event parser accepts only a valid message INSERT identity', () => {
  assert.deepEqual(parseMessageRecord({
    type: 'INSERT',
    record: {
      id: eventId,
      conversation_id: conversationId,
      sender_id: owner,
    },
  }), message)
  assert.equal(parseMessageRecord({ type: 'UPDATE', record: {} }), null)
  assert.equal(parseMessageRecord({
    type: 'INSERT',
    record: { id: 'bad', conversation_id: conversationId, sender_id: owner },
  }), null)
})

test('recipient resolution rejects a nonmember sender and excludes sender', () => {
  assert.equal(resolvePushRecipients([{ user_id: peer }], owner), null)
  assert.equal(resolvePushRecipients([{ user_id: peer }], outsider), null)
  assert.deepEqual(
    resolvePushRecipients([{ user_id: owner }, { user_id: peer }], owner),
    [peer],
  )
})

test('multiple device tokens receive one generic logical event', async () => {
  const sent = []
  const result = await dispatchMessagePush({
    message,
    recipients: [peer],
    claimRecipient: async () => true,
    listTokens: async () => [{ id: 'd1', token: 't1' }, { id: 'd2', token: 't2' }],
    releaseRecipient: async () => assert.fail('must keep successful claim'),
    removeToken: async () => {},
    sendToDevice: async (token, event) => {
      sent.push([token, event.id])
      return { ok: true }
    },
  })
  assert.equal(result.status, 200)
  assert.deepEqual(sent, [['t1', eventId], ['t2', eventId]])
})

test('duplicate recipient claim suppresses duplicate push', async () => {
  let sends = 0
  const result = await dispatchMessagePush({
    message,
    recipients: [peer],
    claimRecipient: async () => false,
    listTokens: async () => assert.fail('duplicate must short-circuit'),
    releaseRecipient: async () => {},
    removeToken: async () => {},
    sendToDevice: async () => { sends++; return { ok: true } },
  })
  assert.equal(result.status, 200)
  assert.equal(sends, 0)
})

test('missing tokens is a safe no-op; invalid tokens are removed', async () => {
  const removed = []
  const result = await dispatchMessagePush({
    message,
    recipients: [peer],
    claimRecipient: async () => true,
    listTokens: async () => [{ id: 'stale', token: 'invalid' }],
    releaseRecipient: async () => {},
    removeToken: async (id) => removed.push(id),
    sendToDevice: async () => ({ ok: false, invalidToken: true }),
  })
  assert.equal(result.status, 200)
  assert.deepEqual(removed, ['stale'])
})

test('transient FCM failure releases dedupe claim for a safe retry', async () => {
  let released = false
  const result = await dispatchMessagePush({
    message,
    recipients: [peer],
    claimRecipient: async () => true,
    listTokens: async () => [{ id: 'd1', token: 't1' }],
    releaseRecipient: async () => { released = true },
    removeToken: async () => {},
    sendToDevice: async () => ({ ok: false, invalidToken: false }),
  })
  assert.equal(result.status, 503)
  assert.equal(released, true)
})
