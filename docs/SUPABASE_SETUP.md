# Supabase setup — RELIO v0.9

Supabase is an optional cloud destination. Drift/SQLite remains authoritative
for chat, SOS, Nearby, media, and settings when the app is offline or no
Supabase configuration is supplied.

## Configure a development build

Create a Supabase project, then run the SQL files in
`supabase/migrations/` in order. Use the project URL and the public
publishable/anon key only:

```powershell
flutter run `
  --dart-define="SUPABASE_URL=https://your-project.supabase.co" `
  --dart-define="SUPABASE_ANON_KEY=your-public-key"
```

Do not commit credentials and never place a `service_role` or other secret key
in a Flutter build. The app intentionally starts in `notConfigured` state when
either define is missing or a service-role key is detected.

## Supabase dashboard checklist

1. Enable email/password authentication.
2. Apply `0001_initial_schema.sql`, `0002_rls_policies.sql`,
   `0003_storage.sql`, `0004_v07_hardening.sql`, and later migrations in order.
3. Confirm `relio-media` is private.
4. Confirm RLS is enabled on every public table and test with a normal user.
5. Create a disposable test account; do not use personal production data.
6. Verify profile, message, SOS, and storage operations only after local/mock
   tests pass.

The v0.6 SyncEngine still requires the ownership gate: it uploads only queue
rows owned by the currently authenticated user, never auto-adopts Guest Mode
history, and preserves local data on sign-out or Cloud failure. Live project
verification and uploads are `DEFERRED` when credentials are not supplied.

The v0.7 adapter additionally rejects malformed configuration, maps live SDK
errors to safe stable codes, validates the current-user Storage path, and
accepts local attachment files only from RELIO's managed media root. These
checks are covered by fake/in-memory tests before any live project is used.

## Build 25 communication migrations — not applied remotely

`0005_communication_platform.sql` adds read receipts, owner-scoped push tokens,
narrowly scoped Admin metadata operations, and server-only push deduplication.
`0006_admin_sos_rpc_only.sql` removes direct Admin SOS table updates so state
changes use the audited RPC. `0007_cloud_direct_chat.sql` adds idempotent direct
conversation creation, server-managed membership, membership-only Cloud
message authorization, server-owned message timestamps, and paged receipt
reconciliation. Migration 0007 is source-reviewed but not applied or SQL-
executed; do not infer a Supabase project from Firebase `relio-17dc0`.
Never apply them to production as part of local validation.
The matching `send-message-push` Edge Function requires a service account and
webhook secret stored only in Supabase's server-side secret store. It has not
been deployed or remotely tested. The QA seed utility is
`scripts/seed-qa-users.ps1`; it creates/reuses four distinct configured QA
identities (two users, one rescuer, one admin) and sets their roles, without
logging passwords or key material. It requires both QA and PROD refs, a QA
service-role key in process environment variables, and a QA ref matching the
reviewed `supabase/qa-project-allowlist.json`. `.env.qa.local` is ignored and
is never read automatically. No QA Supabase ref, CLI, URL/key, or service-role
credential is configured in this workspace, so no seeding or remote mutation
was performed.

Build 26 Cloud sync is covered locally by shared-backend FakeCloud integration
tests, including account isolation, page cursors, new-device import, Nearby/
Cloud dedupe, unread counts, and read receipts. This does not replace applying
the migration and validating RLS with two QA accounts and an unauthorized
third account.
