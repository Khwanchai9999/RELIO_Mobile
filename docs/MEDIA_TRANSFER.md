# RELIO v0.4 Media Transfer

## Scope

Images and bounded video files are selected locally, copied into a
RELIO-owned application-support directory, and represented by a persistent
message plus `attachments` row before Nearby is attempted. There is no cloud
upload, media synchronization, Base64 media JSON, transcoding, or relay.

## Storage and validation

`MediaStorageService` generates UUID-based filenames and never trusts an
external filename as a path. It validates file existence, size, MIME type, and
basic file signatures. v0.4 accepts JPEG, PNG, WEBP, MP4, and common QuickTime
files. The prototype policy is 15 MB per image and 100 MB per video. These
limits are centralized in `MediaTransferPolicy`.

## Transfer lifecycle

An outgoing media message is created locally first:

```text
selected file → validate/copy → attachment pending → message pending
→ native Nearby file payload + mediaMetadata → transferring
→ mediaAck from receiver → attachment completed/message delivered
```

The JSON `mediaMetadata` packet contains `messageId`, `attachmentId`,
`transferId`, media metadata, and the native Nearby payload ID. The binary
content travels through `nearby_connections.sendFilePayload`. Incoming files
are normalized by `AndroidNearbyTransport` into a local path before the rest of
the application sees them. Metadata and file callbacks may arrive in either
order; the service holds the incomplete half until both are available.

The stable states are `pending`, `preparing`, `transferring`, `received`,
`completed`, `failed`, and `cancelled`. A process restart must not turn a stale
`transferring` row into `completed`; it remains recoverable/failed until a
future explicit retry policy handles it. A failed transfer retains its local
message and exposes retry rather than creating a second logical message.

## Mock and Android modes

`MockNearbyTransport` emits deterministic start and completion events and can
simulate failures, progress, disconnects, and incoming files for automated
tests. Android uses `AndroidNearbyTransport`, which wraps the installed
`nearby_connections 4.3.0` file payload and progress API. Exact two-phone file
behavior is `DEFERRED MANUAL VERIFICATION`.

## Known limitations

- No final media playback/transcoding pipeline is included.
- No checksum is currently required for completion; MIME, size, and signature
  validation are the v0.4 integrity checks.
- File transfer is foreground/session-bound. Background Nearby services are
  intentionally out of scope.
- No cloud storage or media sync exists yet.
