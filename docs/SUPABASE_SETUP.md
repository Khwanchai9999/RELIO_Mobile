# Supabase setup — RELIO v0.5

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
2. Apply `0001_initial_schema.sql`, `0002_rls_policies.sql`, and
   `0003_storage.sql`.
3. Confirm `relio-media` is private.
4. Confirm RLS is enabled on every public table and test with a normal user.
5. Create a disposable test account; do not use personal production data.
6. Verify profile, message, SOS, and storage operations only after local/mock
   tests pass.

Live project verification is `DEFERRED` when credentials are not supplied.
