# RELIO Nearby Protocol v1

## v0.8 cloud boundary

Nearby remains a direct peer/offline protocol. Supabase is not a transport
replacement and does not change packet versioning. Cloud metadata and media
operations use the separate `CloudDataSource` boundary after local persistence;
Nearby packets continue to use protocol version 1 and must work without a
network connection.

This document describes the direct-peer and bounded relay protocol used by RELIO
Mobile v0.8.
Physical radio behavior is still `DEFERRED MANUAL VERIFICATION`.

## Envelope

Every payload is UTF-8 JSON with `protocolVersion` (`1`), a UUID `packetId`,
`type`, stable `senderDeviceId`, `senderUserId`, ISO-8601 `createdAt`, and a
validated packet-specific `payload` object.

Supported types are `hello`, `textMessage`, `deviceStatus`, `ack`, `sos`,
`mediaMetadata`, `mediaAck`, `locationMessage`, additive `relayEnvelope`, and
`relayAck`.
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

Until `hello` establishes this mapping, the endpoint is not treated as an
identified RELIO peer. A data/control packet from an unmapped endpoint, or a
packet whose `senderDeviceId` differs from the established mapping, is rejected
before application state is changed. Pending direct messages are flushed only
after the hello packet identifies the connected recipient.

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

`hello.capabilities` advertises `relay-v1` when the node can store and forward
bounded envelopes. `relayEnvelope` carries a `RelayEnvelope` with a relay
packet ID separate from its inner payload ID, origin/destination device IDs,
payload type/ID, creation and expiry times, hop count/max hops, priority, and
previous-hop metadata. v0.8 accepts only text, location, and SOS payloads;
media metadata and binary media are not relayable. A relay node stores the
envelope and sends a hop ACK before forwarding one selected eligible peer.
Private text is materialized only at the destination. SOS may be consumed by
relay nodes for safety presentation while retaining the original SOS identity
and location capture metadata. `relayAck` reports `stored`, `delivered`,
`expired`, or `blocked`; `stored` is not final delivery.

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

v0.8 supports a bounded direct-peer relay path only. It does not implement
unrestricted flooding, Internet gateway behavior, background Nearby services,
route metrics, CRDT reconciliation, or complex encryption. New packet types
remain on protocol v1; older peers fail safely on unknown types and continue
decoding the existing v1 packet types.
