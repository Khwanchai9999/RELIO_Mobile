# Cloud architecture — RELIO v0.8

The cloud layer is an adapter, not a replacement for the offline core:

```text
UI → repository/domain → Drift/SQLite → local sync_queue → CloudDataSource → Supabase
```

Local user-created data is written first. `CloudDataSource` exposes auth, DTO
mapping, PostgREST upserts/fetches, and private Storage upload/download
primitives. `SyncEngine` is a foreground/lifecycle-triggered worker that reads
the queue; it never makes Cloud the source of truth.

`SupabaseCloudDataSource` is the production adapter. `FakeCloudDataSource` is a
deterministic in-memory adapter for tests and development. Widgets depend on
`AuthService`/diagnostics and never import Supabase SDK types. The local
`deviceId` is independent from `cloudUserId`; guest/offline use is valid.

Cloud states are `notConfigured`, `signedOut`, `ready`, `offline`, and `error`.
Signing out immediately prevents account-bound claims and uploads; it never
deletes local SQLite, queue rows, owner IDs, or RELIO-managed media.

## Ownership gate

Every queue row has a nullable `ownerUserId`. A non-null row is eligible only
when it exactly matches the current authenticated Cloud identity. Null,
malformed, or mismatched ownership is blocked and remains local. A Guest Mode
row is never adopted on login; the user must explicitly choose
`นำข้อมูลออฟไลน์นี้ไปซิงก์กับบัญชีนี้`, which assigns only currently unowned
pending/failed rows to the current account.

Message, SOS, and attachment work uses the same gate. An attachment also waits
for its parent message and metadata operation, and its private Storage path is
derived from the verified current user ID. Exact SOS coordinates and message
content are not written to ordinary diagnostics.

Retries, stale-processing recovery, account switches, and app restarts retain
the original owner. A retry always re-checks the current identity before the
Cloud call. Cloud errors change queue state only; they do not delete or mutate
the authoritative local payload.

Remote IDs reuse local UUIDs. Media metadata is stored in Postgres while binary
files use the private `relio-media` bucket under a user-owned path. No media is
Base64 encoded into Nearby JSON and no cloud path is treated as local truth.

Relay is a separate Nearby destination. A foreign `relay-v1` envelope is kept
in the local relay tables and is never inserted into `sync_queue`; it cannot be
uploaded as the currently signed-in account. Bidirectional conflict resolution,
cloud subscriptions, background services, and live media download remain
deferred. Live Supabase/device sync is also deferred until a disposable test
project and manual verification are explicitly configured.
