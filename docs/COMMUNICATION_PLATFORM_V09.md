# RELIO communication platform — Build 24 baseline / Build 25 identity update

## Implemented in source

Build 24 is the preserved local communication-platform baseline. Build 25 adds
an Android Keystore P-256 signing identity, local public-key/fingerprint pins,
protocol-v2 nonce challenges, and fingerprint-hint candidate routing. Only a
challenge proof matching the pinned key can authorize a trusted reconnect; the
endpoint name itself never grants trust. Old trusted records migrate without
their auto-reconnect bit so they must pair again. Dart protocol behavior is
automated-tested and Android flavors compile; real Keystore signatures and
reconnection are not physically verified.

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

Cloud boundary: the foreground SyncEngine currently processes owner-matched
local queue uploads. A verified cross-account conversation membership/linking
flow and cloud-to-local message reconciliation are not implemented; the
existing `fetchMessages` adapter is not called by SyncEngine. Do not describe
messages as deliverable between separate cloud accounts while that remains so.
Local-first Nearby messaging remains independent of this cloud limitation.

## QA backend setup — not yet applied

No Supabase project ref/URL or service-role/FCM server credentials are stored in
this workspace. Do not infer the QA Supabase project from Firebase project
`relio-17dc0`; they are separate systems. Before enabling remote services:

1. An operator verifies the exact disposable QA Supabase project ref and URL.
2. Apply `0005_communication_platform.sql` and then
   `0006_admin_sos_rpc_only.sql` only to that QA project, after reviewing RLS
   and grants. Do not run them on production.
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
`scripts/seed-qa-users.ps1` also requires the QA ref to match the reviewed
`supabase/qa-project-allowlist.json`; it fails closed while the allowlist is
blank. The Supabase CLI is not installed/configured here, and the Admin site is not
linked to a Vercel project. Remote account setup, migration application, FCM
service-account provisioning, webhook wiring, and deployment remain manual.

Build 25 implements cryptographically authorized auto-reconnect in source.
Its physical-device acceptance remains deferred. A persisted trust flag alone
does not authorize a connection; the peer must prove the pinned key.

## Release/device boundary

Build 25 remains an unpublished software-side QA candidate. Format, analyze,
151 Flutter tests, DEV/QA/PROD builds, QA isolation, PowerShell syntax checks,
and the signed QA `-NoUpload` pipeline passed locally. No APK was uploaded or
installed on a phone. Verify acceptance on physical Android devices before
describing Nearby trust/reconnect, notifications, or read receipts as
device-verified.
