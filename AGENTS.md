# RELIO Mobile agent notes

## Purpose

This directory is the Android-first Flutter implementation of RELIO Mobile
v0.9.0. It is a separate project from the sibling React/Vite
`RELIO_SOS` prototype. Do not rewrite the React project or move Flutter files
into it.

## Product principles

- Offline-first is a product invariant, not a later optimization.
- Nearby and Cloud are separate transport concepts and must be represented by
  separate delivery states.
- SOS actions must be explicit, confirmable, visible, and reversible where
  appropriate.
- Keep Internet connectivity, Nearby connectivity, and sync state distinct in
  both the model and UI.
- All outgoing user-generated data must eventually be persisted locally before
  attempting Nearby or Cloud delivery.
- The local database is authoritative for core application state. The write path
  is UI → repository → Drift/SQLite → Nearby/Sync; UI code must not write to a
  transport directly.

## Technical conventions

- Use Flutter and Dart; keep the Android target as the primary runtime.
- Use `go_router` for navigation and keep route names centralized in
  `lib/app/router.dart`.
- Keep design decisions in `lib/app/theme/` and reusable UI in
  `lib/shared/widgets/`.
- Keep mock identities and prototype data centralized in `lib/data/`.
- Prefer feature folders under `lib/features/` over large cross-feature files.
- Repositories own persistence and map database rows to application models where
  that improves separation. UI must not call Drift-generated tables directly.
- Keep plugin-specific Nearby types inside `AndroidNearbyTransport`; expose only
  the transport abstraction and RELIO domain packet types elsewhere.
- Keep SQL out of `NearbyService`. It coordinates transport, packet validation,
  repository calls, and acknowledgements.
- Keep `MediaStorageService`, `AttachmentRepository`, and `LocationService`
  behind application boundaries. Widgets may render media but must not own
  file copying, SQLite queries, or geolocator calls.
- Never put image/video bytes in JSON packets. Use Nearby file payloads and
  correlate them with persistent `transferId` plus native payload ID metadata.
- Request location only for explicit Send Location or SOS actions. Do not add
  background location, continuous tracking, or a location history.
- Use `MockNearbyTransport` for deterministic development and automated tests.
- Use `FakeCloudDataSource` for deterministic cloud/auth tests; never require
  internet in the normal test suite.
- Keep Supabase SDK types inside `SupabaseCloudDataSource`. Widgets depend on
  `AuthService` and `CloudDataSource` abstractions only.
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` are compile-time defines. Never add a
  service-role key, password, token, or `.env` secret to source control.
- Cloud is optional: `notConfigured`, guest, offline, and local-only states are
  valid. Sign-out removes only cloud session state and never local data.
- `SyncEngine` may upload only queue rows whose `ownerUserId` exactly matches
  the current authenticated Cloud identity. Unknown, malformed, null, or
  mismatched ownership is blocked; it must never be guessed or reassigned.
- Guest-created rows remain local after login. Only an explicit user action may
  adopt unowned history for the current account. Sign-out/account switch stops
  account-bound sync and preserves original owner IDs.
- SOS/location data and attachments use the same ownership gate. Do not put
  exact locations, message content, tokens, passwords, private keys, or local
  secrets in normal logs or diagnostics.
- `FakeCloudDataSource` remains the default automated verification path and
  must enforce the same account isolation and Storage path rules as the live
  adapter. Do not
  perform live Supabase uploads during implementation without an explicitly
  configured disposable test environment and clearly test data.
- Android app runtime uses `AndroidNearbyTransport` by default once Flutter is
  running; Mock transport is an explicit test/developer override.
- Keep transport endpoint IDs separate from stable RELIO `deviceId` values.
- Accept `hello` as the identity-establishing packet for a Nearby endpoint;
  reject other data/control packets until its stable `deviceId` matches the
  completed handshake.
- Keep real discovered peers separate from seeded demo identities in every
  screen, and do not show simulated distance, signal, Internet, or delivery
  values as runtime facts.
- Direct chat is routed to the mapped endpoint for one participant; never
  broadcast private text to every connected endpoint.
- SOS has precedence over Rescue, and Rescue has precedence over Normal.
- Use Material 3 and RELIO semantic tokens. Do not scatter raw status colors
  through feature screens.
- Keep `ThemeMode` in the application-lifetime `RelioThemeController`; settings
  screens must update that controller rather than owning local theme state.
- The root `MaterialApp.router` must bind to the live controller mode, and
  startup must restore the persisted `light`, `dark`, or `system` value before
  launching the production app.
- Add concise, natural Thai comments only at important or non-obvious logic.
  Explain what the block does and why, using technical English terms such as
  ThemeMode, Repository, SQLite, Nearby, ACK, or SyncEngine when useful. Do not
  comment every line, obvious syntax, or generated files.
- Never distribute a TEST APK if `format`, `flutter analyze`, `flutter test`,
  or the TEST build fails. Never commit signing secrets, keystores, Firebase
  credentials, tokens, or service-account files. The tracked QA
  `android/app/src/qa/google-services.json` contains Firebase client
  identifiers only, must target `com.relio.relio_mobile.test`, and must never
  be copied to DEV or PROD source sets.
- Keep DEV, TEST, and PROD packaging separate. Production ID/signing must not
  be reused casually for TEST builds. Firebase App Distribution is only a test
  delivery channel; Supabase remains the RELIO backend.
- The visible Android launcher/app label is `RELIO` for every flavor. Flavor
  identity remains internal in package IDs and build configuration.
- USB smoke testing may occur before distribution. Do not implement a custom,
  silent, or insecure APK self-updater.
- Public Android QA updates use Firebase Hosting metadata and an immutable
  GitHub Releases APK asset. Firebase Hosting must never contain an APK.
  Only QA may request user-controlled unknown-app installation; PROD must not
  contain `REQUEST_INSTALL_PACKAGES` or public QA update behavior.
- The public updater fetches `latest.json` only from the approved Firebase
  Hosting URL and validates an exact authenticated-owner GitHub release asset,
  HTTPS redirects, package, versionCode, SHA-256, APK signer, and Android
  Package Installer handoff before installation.
- QA public updater builds must load the shared non-secret configuration from
  `scripts/public-qa-config.ps1` and pass its manifest URL, GitHub owner,
  repository, and channel as `dart-define` values. The Dart compile-time guard
  must reject QA builds with missing or unapproved values; DEV/PROD remain
  buildable without these QA-only values.
- Firebase App Distribution remains an internal/fallback QA channel and is not
  required for ordinary public QA downloads.
- Preserve Thai copy and accessibility labels when changing UI.
- Export one default component per screen file when adding new screen modules.

## Status semantics

- Teal: RELIO primary / Nearby communication
- Blue: Rescue mode / safety action
- Red: SOS / urgent state
- Amber: pending, queued, or attention needed
- Green: success, delivered, or synced
- Gray: offline, disabled, or neutral state

## Validation commands

Run these from `RELIO_Mobile` after changes:

```bash
dart format .
flutter analyze
flutter test
flutter build apk --flavor dev --debug --dart-define=RELIO_ENV=development
flutter build apk --flavor prod --debug
.\scripts\deploy-test.ps1 -NoUpload
```

QA debug builds must receive the approved updater dart-defines from
`scripts/public-qa-config.ps1`. Build 22 (`0.9.0+22`) is the latest public QA
release. Build 23 (`0.9.0+23`) is the current Nearby-fix candidate and must not
be installed or published unless the active release request explicitly
authorizes it. Future public releases require all automated, signing, and OTA
verification gates to pass.

The Google Services Gradle plugin is configured for the QA-only config with a
WARN policy for missing config, so DEV and PROD remain Supabase-only and
buildable. Verify its package target and App Distribution dependency boundary
with `scripts/verify-qa-update-isolation.ps1` before QA deployment.

`scripts/deploy-test.ps1` preserves the Firebase App Distribution fallback and
resolves the QA App ID from the verified config when `FIREBASE_APP_ID` is
absent. `scripts/release-public-qa.ps1` verifies the authenticated GitHub
owner/repository, creates or reuses the immutable current public QA release
asset, then deploys only metadata to the confirmed `relio-17dc0` Hosting site
and verifies both public origins. Deployment must never bump the version
implicitly.

Drift generated files are produced by build_runner and must not be edited by
hand. On this Windows path, use `dart run build_runner build --force-jit` if
the normal AOT build cannot write its snapshot.

Physical-radio, runtime-permission, GPS, Supabase live, sync account-switch,
and two-phone relay checks are `DEFERRED MANUAL VERIFICATION` for v0.9. Keep
them in `docs/MANUAL_DEVICE_TESTS.md`; do not claim real-device Nearby success
without performing them. Unit tests, emulator checks, and successful signed
builds do not prove physical Nearby compatibility across OEMs. Build 21's
public release still requires two-phone acceptance before declaring the
compatibility milestone physically verified.

## Change boundaries

- Do not add a background worker, cloud-first UI, live credentials, or live
  Supabase uploads in v0.9.0. The foreground/lifecycle SyncEngine is optional
  and ownership-gated. Public QA update behavior and the full Firebase App
  Distribution SDK must never ship inside the PROD Google Play build.
- Local-first writes remain mandatory: UI → repository → SQLite → Nearby and
  future cloud queue.
- UI must not call Drift-generated tables or the Nearby plugin directly.
- Plugin-specific Nearby types remain inside `AndroidNearbyTransport`.
- `sync_queue` is SQLite-authoritative. Queue processing must preserve
  `ownerUserId`, retry locally, and never upload across accounts.
- Supabase adapter changes must preserve safe error mapping, RLS ownership, and
  managed local-media boundaries. Reconciliation/pull is architecture only;
  do not silently overwrite newer local rows.
- Relay is limited to the `relay-v1` store-and-forward envelope. It supports
  bounded text, location, and SOS hops with persistent deduplication and
  forward history; it does not flood, relay media, or run as a background
  daemon.
- Background services, push notifications, live location, map SDKs, cloud
  media, video transcoding, and a complex encryption protocol are not
  implemented.
- Do not silently replace mock data with remote data.
- Do not remove pending/sent/synced status visibility from message UI.
- Do not make broad destructive changes to either project.
- Update this file and `README.md` when architecture or milestone boundaries
  materially change.
- All maintained scripts derive the project root from `$PSScriptRoot`; no
  runnable command may point to an old ASCII or Thai workspace path.
