# RELIO v0.8 Relay Architecture

RELIO v0.8 adds a bounded Nearby store-and-forward foundation. It is a
foreground, direct-peer feature for a small A→B→C path; it is not a mesh
flooding service or an Internet gateway.

## Responsibilities

```text
NearbyTransport → NearbyService → RelayEngine → DriftRelayRepository → SQLite
                                      ↓
                              selected direct peer
```

`NearbyService` owns packet parsing and the direct protocol. `RelayEngine`
owns relay validation, destination handling, hop selection, ACK semantics, and
retry. `DriftRelayRepository` owns the `relay_packets` and
`relay_forward_history` tables. No relay packet is inserted into the normal
Cloud `sync_queue`.

## RelayEnvelope

The additive `relay-v1` envelope has a relay `packetId` that is distinct from
the inner payload ID:

```text
packetId, originDeviceId, destinationDeviceId
payloadType, payloadId, payload
createdAt, expiresAt, hopCount, maxHops, priority
previousHopDeviceId, protocol = relay-v1
```

Supported payloads are text, location, and SOS. Media metadata and binary file
payloads are rejected. TTL, maximum hops, packet size, and the supported
payload set are centralized in `RelayPolicy`.

## Store-before-forward

On receipt, a node validates and stores the envelope before sending a hop ACK
or attempting to forward. The persistent packet row is the deduplication key;
the persistent forward-history key is `(packetId, targetDeviceId)`. A process
restart can retry a failed or stale in-progress target without creating a new
relay packet identity.

Relay selection chooses one eligible connected peer at a time. It excludes the
local device, the origin, the previous hop, peers without a verified device
identity, and peers that did not advertise `relay-v1`. A direct destination is
preferred. This keeps v0.8 bounded and avoids unrestricted flooding.

## Privacy and materialization

Relay nodes store the envelope locally so they can forward it, but a private
text or location payload is not inserted into the relay node's normal chat
repository. Only the destination materializes the inner payload. SOS is the
exceptional safety payload: the destination and relay nodes may process its
active state through the SOS path, while preserving the original SOS ID,
origin, location capture timestamp, and accuracy metadata.

Exact coordinates, message content, and relay payload JSON are not written to
normal logs or diagnostics. Relay packets remain local and are never treated
as cloud-owned data. Cloud ownership checks therefore remain unchanged: a
foreign relay packet cannot become an Account B `SyncQueue` row or upload.

## Delivery semantics

The hop ACK means only `stored` (or `delivered` when the destination consumes
the payload). It is not proof of final delivery to the destination. An
optional end-to-end receipt remains deferred until a later milestone can add it
without weakening the current bounded behavior.

## Resource and lifecycle limits

Packets expire locally, are marked expired, and are not forwarded. The
foreground engine resumes pending forwarding on a newly connected eligible
peer. There is no background daemon, aggressive polling loop, route metric,
CRDT, live location tracker, or relay of attachments/media.

Physical radio, two-phone, and runtime-permission checks remain deferred manual
verification in `docs/MANUAL_DEVICE_TESTS.md`.
