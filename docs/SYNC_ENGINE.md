# RELIO v0.6 SyncEngine

`SyncEngine` is the local-first outbox processor for the optional Cloud
destination. SQLite remains authoritative:

```text
UI → Repository → Drift/SQLite → sync_queue → ownership gate → CloudDataSource
```

The engine is triggered at app startup, when Cloud/auth state becomes usable,
when a new queue row is created, when the app returns to the foreground, and by
the user pressing `ซิงก์ตอนนี้`. It is not a background service and it never
waits for Cloud before rendering local data.

## Ownership rules

- Every queue row stores `ownerUserId`, or null when it was created without an
  authenticated Cloud owner.
- A row uploads only when its owner exactly matches the current authenticated
  Cloud user ID.
- Null, malformed, missing, or mismatched ownership is blocked and stays in
  SQLite. The engine never guesses an owner.
- Guest history is not automatically assigned to the next account. The user
  must explicitly choose `นำข้อมูลออฟไลน์นี้ไปซิงก์กับบัญชีนี้`; only then are
  unowned pending/failed rows adopted for the current account.
- Sign-out and account switching stop the current run. Pending rows retain
  their original owner and are not reassigned.

SOS/location rows and attachment rows use the same gate. An attachment must
also follow its parent message and metadata queue item. Storage paths are
derived from the verified owner ID and do not use arbitrary local paths.

## Retry and recovery

Transient Cloud failures return a row to `pending` with a bounded exponential
delay. Permanent validation/auth/permission/local-file failures become
`failed` without deleting local data. A retry re-checks Cloud readiness and
ownership before the upload. Stale `processing` rows are recovered on startup,
still retaining their owner and payload.

FakeCloudDataSource is the default automated path. Live Supabase uploads,
physical radio behavior, and real account-switch verification remain deferred
manual checks; no live upload is performed by the automated suite.
