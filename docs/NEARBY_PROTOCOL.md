# RELIO Nearby Protocol v1

## v0.5 cloud boundary

Nearby remains a direct peer/offline protocol. Supabase is not a transport
replacement and does not change packet versioning. Cloud metadata and media
operations use the separate `CloudDataSource` boundary after local persistence;
Nearby packets continue to use protocol version 1 and must work without a
network connection.

This document describes the direct-peer protocol used by RELIO Mobile v0.4.
Physical radio behavior is still `DEFERRED MANUAL VERIFICATION`.

## Envelope

Every payload is UTF-8 JSON with `protocolVersion` (`1`), a UUID `packetId`,
`type`, stable `senderDeviceId`, `senderUserId`, ISO-8601 `createdAt`, and a
validated packet-specific `payload` object.

Supported types are `hello`, `textMessage`, `deviceStatus`, `ack`, `sos`,
`mediaMetadata`, `mediaAck`, and `locationMessage`.
Unknown packet types, missing fields, wrong field types, malformed JSON, and
unsupported protocol versions fail safely and are logged as protocol errors.

## Handshake and identity

Transport endpoint IDs belong to Google Nearby Connections and may change. A
connected peer sends `hello`, which contains the RELIO device ID, display name,
status, and capabilities. `NearbyService` maps:

```text
transport endpoint ID ↔ stable RELIO deviceId
```

The mapping is refreshed after every connection and peer metadata is persisted
through `NearbyDeviceRepository`.

## Packet types and delivery

`textMessage` carries `messageId`, `conversationId`, `text`, and `timestamp`.
The receiver validates and deduplicates by `messageId`, persists the message,
then sends `ack`.

`ack` references the source `packetId` and can include `messageId`. Duplicate
ACKs are safe. A sender transitions `pending → nearbySent → delivered`; the
cloud-only `synced` state is not used by v0.4.

`deviceStatus` carries `normal`, `sos`, or `rescue`.

`sos` carries `sosId`, owner identity, optional message and coordinates,
creation time, optional location capture metadata, and `isActive`. Duplicate
SOS packets update the same local row instead of creating another visible
event. Missing location is valid; no fake coordinates are generated.

`locationMessage` carries a message ID, conversation ID, latitude/longitude,
optional accuracy, and the capture timestamp. It is an offline location card,
not a map link.

`mediaMetadata` carries message/attachment/transfer IDs, media type, original
display filename, MIME type, byte size, and optional dimensions/duration. It
never carries binary content. The sender first starts the Nearby file payload,
then sends metadata containing the native payload ID. The receiver correlates
both arrival orders by payload ID and stores the file in RELIO-owned storage.
`mediaAck` confirms that the receiver persisted the attachment; a local
transport success is not treated as delivery. v0.4 supports image and bounded
video files only.

## Status precedence

For presentation and handshake state, the precedence is:

```text
SOS > Rescue > Normal
```

An active SOS therefore remains red even if a Rescue setting is also enabled.

## Retry and boundaries

Outgoing user text is inserted into SQLite before a transport call. If the
intended peer is not connected, it remains `pending`. A direct send failure is
stored as `failed`; the chat UI exposes an explicit retry. There is no infinite
retry loop or background service.

v0.4 supports direct peer communication only. It does not implement cloud
sync, Supabase, relay, TTL, seen-message caches, live location, background
Nearby services, map SDKs, or complex encryption. New packet types remain on
protocol v1; older peers fail safely on unknown types and continue decoding
the existing v1 packet types.
