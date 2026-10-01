# RELIO communication platform — Build 24

## Implemented in source

- Nearby connection requests require a user decision and show the transport
  authentication code on both phones. The saved peer directory stores trust
  and block state, with controls in the Nearby screen. Identity is still
  established by the RELIO `hello` packet after the transport handshake.
- Conversations persist unread counts; messages persist `readAt`. Read-receipt
  packets contain only a message ID and timestamp and are sent directly to the
  mapped Nearby peer after the recipient opens a conversation.
- Android local notifications use separate message and urgent SOS channels.
  Lock-screen visibility is private and message previews are generic. Taps route
  to the relevant chat or SOS screen. Notification preference and Android
  notification permission are respected.
- Android QA builds can register an FCM token only after notification consent
  and Supabase sign-in. The token write is account-scoped by RLS. DEV/PROD never
  request a token, and the full Firebase App Distribution SDK remains QA-only.
- `supabase/functions/send-message-push` accepts only the configured database
  webhook secret, resolves recipients from conversation membership, sends a
  generic notification through FCM HTTP v1, and deduplicates per recipient.
  It never sends message content, location, or SOS text.
- `D:\RELIO_Admin` is an independent React/Vite console. It accepts only an
  authenticated `profiles.role = admin` session, displays metadata/aggregates,
  and uses audited server functions for role and SOS changes. Its browser code
  uses only a public Supabase anon key.

## QA backend setup — not yet applied

No Supabase project ref/URL or service-role/FCM server credentials are stored in
this workspace. Do not infer the QA Supabase project from Firebase project
`relio-17dc0`; they are separate systems. Before enabling remote services:

1. An operator verifies the exact disposable QA Supabase project ref and URL.
2. Apply `supabase/migrations/0005_communication_platform.sql` only to that QA
   project, after reviewing its RLS/column grants. Do not run it on production.
3. Provision the initial Admin role out-of-band for the explicitly approved QA
   account. Ordinary client sessions cannot promote themselves.
4. Deploy `send-message-push` to that verified QA project. Set
   `FCM_PROJECT_ID=relio-17dc0`, `FCM_SERVICE_ACCOUNT_JSON`, and a random
   `DATABASE_WEBHOOK_SECRET` in the Edge Function secret store. The service
   account must be scoped to Firebase Cloud Messaging; never put it in Vite,
   Dart defines, or source control.
5. Configure a database webhook for `public.messages` INSERT to the QA Edge
   Function. Send `x-relio-webhook-secret` from the secret store. Verify a
   generic test notification and ensure no message body is in the request log.
6. Supply QA-only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` to the Admin
   deployment. Apply the same migration before exposing the site.

These operations are intentionally not executed by local build/test commands.
The Supabase CLI is not installed/configured here, and the Admin site is not
linked to a Vercel project. Remote account setup, migration application, FCM
service-account provisioning, webhook wiring, and deployment remain manual.

Automatic reconnect is deliberately not enabled yet: Nearby endpoint IDs are
ephemeral and the current app has no persisted cryptographic key binding that
can safely authorize a silent reconnect. A trusted peer still requires a
user-initiated connection and visible authentication-code check. Do not
interpret a stored trust flag as automatic transport authorization.

## Release/device boundary

Build 24 is software-side QA candidate only. This task does not install an APK
on a phone. Verify acceptance on physical Android devices before describing
Nearby trust/reconnect, notifications, or read receipts as device-verified.
