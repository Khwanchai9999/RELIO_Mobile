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

## Build 24 communication migration — not applied

`0005_communication_platform.sql` adds read-receipt fields, owner-scoped push
tokens, narrowly scoped Admin metadata operations, and server-only push
deduplication state. Review this migration and apply it only to an explicitly
verified disposable QA project; do not infer its project from Firebase
`relio-17dc0` and never apply it to production as part of local validation.
The matching `send-message-push` Edge Function requires a service account and
webhook secret stored only in Supabase's server-side secret store. It has not
been deployed or remotely tested. The local Build 24 push-token client remains
inactive until that separately configured QA backend is proven.
