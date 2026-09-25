# Cloud architecture — RELIO v0.5

The cloud layer is an adapter, not a replacement for the offline core:

```text
UI → repository/domain → Drift/SQLite → local sync_queue → CloudDataSource → Supabase
```

Local user-created data is written first. The v0.5 `CloudDataSource` exposes
auth, DTO mapping, PostgREST upserts/fetches, and private Storage upload/download
primitives. It does not run a background worker or process `sync_queue`.

`SupabaseCloudDataSource` is the production adapter. `FakeCloudDataSource` is a
deterministic in-memory adapter for tests and development. Widgets depend on
`AuthService`/diagnostics and never import Supabase SDK types. The local
`deviceId` is independent from `cloudUserId`; guest/offline use is valid.

Cloud states are `notConfigured`, `signedOut`, `ready`, `offline`, and `error`.
Signing out removes the cloud session only; it never deletes local SQLite or
RELIO-managed media.

Remote IDs reuse local UUIDs. Media metadata is stored in Postgres while binary
files use the private `relio-media` bucket under a user-owned path. No media is
Base64 encoded into Nearby JSON and no cloud path is treated as local truth.

Automatic queue processing, conflict resolution, cloud subscriptions, relay,
background services, and cloud-dependent UI are deferred to v0.6 or later.
