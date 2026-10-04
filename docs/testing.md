# RELIO testing and verification

## Automated checks

Run from the repository root with the configured Flutter SDK:

```powershell
dart format .
flutter analyze
flutter test
```

The Flutter suite uses in-memory or temporary SQLite databases, fake location,
`MockNearbyTransport`, notification recording sinks, and `FakeCloudDataSource`.
Coverage includes:

- database repositories, schema upgrade, persistence, and queue recovery;
- packet validation, simulated Nearby handshakes, cryptographic identity,
  reconnect policy, direct chat, SOS, relay, and deduplication;
- Cloud ownership, retry/backoff, receipts, and multi-account fake behavior;
- local media validation, transfer integrity/deduplication, notifications, and
  diagnostics privacy;
- themes, app/widget behavior, and public QA updater parsing/configuration.

`.\scripts\deploy-test.ps1 -NoUpload` additionally runs the release quality
gate and signed QA no-upload build. The updater-isolation check verifies that
QA-only install/update support does not leak into PROD. It does not publish an
APK or deploy backend services.

## What automation does not prove

Mock transport, widget tests, emulator runs, and successful APK builds do not
prove Bluetooth/Wi-Fi discovery, native Nearby negotiation, Android runtime
permission behavior, GPS, OEM background behavior, or two-phone media delivery.
Those checks are explicitly deferred in
[`MANUAL_DEVICE_TESTS.md`](MANUAL_DEVICE_TESTS.md). No backend deployment or
live Cloud upload is part of the normal test suite.

For a public QA release, use only the canonical publisher after all gates pass:
`.\scripts\publish-qa.ps1`. Verify the resulting metadata and immutable GitHub
APK independently; do not infer physical acceptance from publication.
