# RELIO v0.7 Cloud reconciliation preparation

v0.7 hardens the one-way local outbox without enabling a background service or
inventing live credentials.

```text
SQLite authoritative state
        │
        ├─ ownerUserId gate
        ├─ dependency ordering
        ├─ retry / stale recovery
        └─ CloudDataSource adapter
                 │
                 └─ Supabase RLS + private Storage
```

The current direction is local → Cloud. Every Cloud write is idempotent by the
local UUID, and account ownership is checked both by `SyncEngine` and by the
adapter/fake server boundary. A future pull/reconciliation phase must compare
server rows against local rows by stable UUID and explicit timestamps; it must
never overwrite newer local data implicitly or assign Guest history to a user.

The v0.7 adapter preparation includes:

- configuration validation that rejects missing, malformed, secret, and
  service-role keys;
- safe error-code mapping without copying backend payloads into diagnostics;
- authenticated sender/owner checks before message, SOS, conversation, and
  attachment writes;
- a strict `users/{userId}/messages/{messageId}/{attachmentId}-{fileName}`
  Storage path policy;
- local-media-root validation before an attachment leaves the device;
- fake server-side account isolation and idempotent storage behavior;
- an RLS hardening migration for owner conversations and the private bucket.

Live Supabase requests, account isolation against two real accounts, and
reconciliation against a real project remain deferred until a disposable test
project is explicitly configured.
