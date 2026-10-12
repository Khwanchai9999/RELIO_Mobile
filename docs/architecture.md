# RELIO architecture

RELIO is an Android-first Flutter application for local-first emergency
communication. The UI does not write to SQLite tables directly and does not
call the Nearby plugin directly.

```text
Flutter screens
  → repositories and application services
  → Drift / SQLite (authoritative local state)
  → Nearby transport and/or account-owned sync queue
  → Android Nearby Connections / optional Supabase
```

## Main boundaries

- `lib/app/` owns app startup, centralized GoRouter routes, and the
  application-lifetime Material 3 theme controller.
- `lib/features/` contains Home, Nearby, Chat, SOS, Rescue, Settings, Profile,
  Sync, and diagnostics screens.
- `lib/core/repositories/` maps domain operations to Drift persistence.
  `lib/core/database/` owns SQLite tables and forward-only migrations.
- `NearbyService` coordinates validated RELIO packets, repositories,
  acknowledgements, and direct endpoint routing. `AndroidNearbyTransport`
  contains plugin-specific types; `MockNearbyTransport` enables deterministic
  tests.
- `SyncEngine` processes only queue rows whose owner exactly matches the
  current Cloud identity. `SupabaseCloudDataSource` is the live adapter and
  `FakeCloudDataSource` is the isolated test implementation.
- `MediaStorageService` copies and validates media under app-managed storage.
  Protocol JSON carries metadata, while Nearby file payloads carry bytes.
- `LocationService` is called only for an explicit Send Location, SOS, or
  Nearby Map location-share action. Map sharing is one-shot; there is no
  background location history.
- `NearbyDeviceRepository` persists optional battery and last-known peer
  location metadata received only after the stable identity handshake. The
  MapLibre canvas renders that state lazily and does not gate Nearby services.

## Offline-first and trust

Outgoing text, location, SOS, and attachment metadata are persisted locally
before transport delivery. A disconnected peer does not remove a conversation
or outgoing message. Nearby endpoint IDs are temporary routing identifiers;
RELIO device IDs and Cloud user/conversation IDs are separate identifiers.

First contact requires an explicit accept/reject decision. For trusted
reconnect, RELIO pins a cryptographic public identity and requires proof of the
matching key; a device name or endpoint ID alone is not identity. Direct private
chat is sent to the mapped peer, not broadcast to every connected device.

Cloud is optional. Guest-created and unowned work stays local until explicit
adoption; sign-out does not delete SQLite data. Local-first and simulated
Nearby behavior are automated-tested, but real-radio, permission, GPS, and
two-phone behavior remain subject to [manual verification](MANUAL_DEVICE_TESTS.md).

## Technology

Flutter/Dart and Material 3; Drift/SQLite; Google Nearby Connections; optional
Supabase Auth, Postgres, and private Storage; QA-only consent/account-gated
Firebase Cloud Messaging; Android package installation for the QA updater.
The separately maintained Admin Web is not part of this mobile application.
