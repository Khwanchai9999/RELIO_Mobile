# RELIO Mobile — v0.9.0

RELIO Mobile Foundation is the Android-first Flutter companion to the existing
`RELIO_SOS` React/Vite prototype. v0.9.0 keeps the offline-first local core,
ownership-gated cloud boundary, bounded Nearby relay foundation, and adds a
hybrid public Android QA update channel: Firebase Hosting serves metadata and
GitHub Releases serves the signed APK.

RELIO means **Relay + IO** — “สื่อสารได้ แม้ไม่มีสัญญาณ”. It is an
offline-first emergency communication app: nearby devices can exchange data
without Internet, while optional Cloud sync can catch up when Internet is
available. Conversation history is saved locally first and remains available
when a temporary transport connection ends.

The React prototype is intentionally kept as a separate project. This Flutter
app lives in `RELIO_Mobile` and does not replace or modify `RELIO_SOS`.

## Project overview

RELIO addresses the loss of direct communication during an Internet outage.
Nearby Connections is the direct transport; Drift/SQLite keeps conversations,
messages, SOS state, and queued work on the device. Optional Supabase sync is a
separate path that can resume when Internet and an authenticated account are
available. Offline-first storage does not mean real-radio behavior has been
physically verified: Build 33 still requires the two-phone checklist.

## Current scope (v0.9.0 development / Android QA)

- Optional Supabase email/password authentication with guest/offline entry
- Configuration through `SUPABASE_URL` and `SUPABASE_ANON_KEY` dart-defines;
  missing configuration is safe and does not block local use
- `CloudDataSource`, `CloudAuthService`, `SupabaseCloudDataSource`, and
  deterministic `FakeCloudDataSource`
- Versioned Supabase schema with normalized tables, RLS policies, and private
  `relio-media` storage
- Developer-only `/developer/cloud` diagnostics
- `SyncEngine` processes only queue items owned by the currently authenticated
  Supabase user; owner mismatch or unknown ownership stays local
- Guest/signed-out data is never auto-assigned to a later account. Explicit
  adoption is available as `นำข้อมูลออฟไลน์นี้ไปซิงก์กับบัญชีนี้`
- Automatic sync retries at startup, foreground resume, Cloud/auth readiness,
  and new queue items; manual `ซิงก์ตอนนี้` is also available
- SQLite remains authoritative. Cloud failures preserve local data and queue
  ownership through retry and crash recovery
- `FakeCloudDataSource` is the deterministic automated test path; routine tests
  do not upload live user data
- Public QA update checks use a small HTTPS manifest and are enabled only in
  RELIO Test; APK download and Android installation require explicit user
  actions
- Firebase App Distribution is an internal/fallback QA channel; the public QA
  APK is an immutable GitHub Release asset, not hosted on Firebase
- Full App Distribution SDK and public QA installation behavior are excluded
  from DEV and PROD

- Welcome, login/register prototype, offline entry, and permission explainer
- Home dashboard with separate Internet and Nearby connectivity status
- Runtime connectivity distinguishes Internet reachability, Wi-Fi radio,
  Bluetooth, SDK-specific Nearby permissions, Google Play Services status,
  legacy Location requirements, connected peers, and optional Cloud state
- Nearby readiness is capability driven on API 24–36, with a guarded API 37
  local-network upgrade path. SOS/location coordinates remain separate; modern
  Nearby is not blocked by GPS being off.
- Foreground Nearby starts advertising and discovery when readiness is met,
  retries after resume/radio changes, and shows Thai blockers. Wi-Fi off is
  reported as reduced capability while P2P_CLUSTER can continue over Bluetooth.
- Nearby device list with All, SOS, Rescue, and Normal filters
- Seeded peers are marked and grouped as `DEMO`; actual peers use transport
  discovery and a hello handshake before stable device identity is accepted
- Nearby discovery/advertising/connect/disconnect coordination with explicit
  endpoint and connection state
- Chat list and chat room with persistent text, image, video, and location
  message flows
- Drift database schema version 7 with conversations, persistent unread/read
  state, trusted/blocked peer metadata, messages, attachments,
  nearby devices, sync queue, SOS events, app settings, relay packets, and
  relay forward history tables
- Incoming Nearby connection requests with explicit accept/reject and saved
  trust/block controls; cryptographically pinned peers can reconnect after
  first-contact approval
- Android local message/SOS notification channels and tap-through navigation;
  FCM token registration is consent-gated and QA-only, while its server
  integration awaits disposable QA Supabase setup
- Repository-owned persistence for conversations, messages, SOS, queue items,
  nearby peer metadata, and the stable local device identity
- Local outgoing message lifecycle: pending → nearbySent → delivered; Cloud
  sync is tracked separately through `cloudSyncStatus`
- Chat and conversation list driven by local database streams; SOS state and
  sync queue counts persist locally
- `NearbyTransport` abstraction, deterministic `MockNearbyTransport`, and the
  Android adapter wrapping `nearby_connections`
- RELIO packet protocol v1 using validated UTF-8 JSON for hello, textMessage,
  deviceStatus, ack, sos, and additive relay-v1 packets
- Bounded A→B→C store-and-forward for text, location, and SOS with TTL, max
  hops, relay capability checks, persistent deduplication, and destination-only
  private-text materialization; binary media is not relayed
- Application-level hello handshake mapping a transport endpoint to stable
  local `deviceId` metadata
- Direct one-to-one chat routing, local-first pending/nearbySent/delivered
  lifecycle, post-handshake pending flush, duplicate protection, ACK
  idempotence, and user retry
- RELIO-owned media storage, MIME/signature validation, bounded image/video
  policy, native Nearby file payloads, progress, completion ACK, and retry
- On-demand LocationService for location messages and SOS, with current/last
  known fallback and bounded timeout; no background tracking
- Local SOS packet receive/deduplication/deactivation and Rescue status
  propagation; status precedence is SOS > Rescue > Normal
- Permission service architecture and Android Nearby-related declarations
- Development-only `/developer/nearby` diagnostics screen, reachable from
  Profile → Settings → Nearby Diagnostics
- DEV/QA-only `ตั้งค่า → การวินิจฉัยระบบ` with bounded, redacted logs and a
  shareable diagnostics ZIP; production excludes its route and native action
- SOS setup, confirmation, active state, stop confirmation, and received SOS
- Rescue mode with active SOS cases and local status updates
- Profile, settings, dark mode, theme selection, and sync visibility
- Theme selection supports Light, Dark, and System modes. One application-level
  controller persists stable `light`, `dark`, or `system` values and the root
  `MaterialApp.router` observes it immediately.
- Prototype seed data is only initial local data; user-generated data is
  persisted before transport delivery
- Physical Android device-to-device verification is deferred; see
  [docs/MANUAL_DEVICE_TESTS.md](docs/MANUAL_DEVICE_TESTS.md)

Instructor-facing references: [architecture](docs/architecture.md),
[testing](docs/testing.md), [demo checklist](docs/demo-checklist.md), and
[submission checklist](docs/submission-checklist.md).

The Android adapter compiles and is the application runtime default after the
Flutter binding is active. Headless automated tests and deliberate developer
overrides use Mock transport. Build 33 (`0.9.0+33`) is the current public QA
physical-test candidate. Its automated release gates passed, but physical
Huawei/realme Nearby radio retest is still pending; publication does not prove
real-device behavior.
The current source hardening candidate is Build 34 (`0.9.0+34`) and is not yet
released; it must pass all automated and packaging gates before distribution.
Cross-account direct conversation linking, local mapping, paged
cloud-to-local message reconciliation, and receipt merge are implemented and
covered by multi-account FakeCloud tests. The separate RELIO-QA Supabase
project, live RLS/Cloud message and receipt checks, FCM authorization path,
Admin authorization, GitHub APK, and Hosting manifest have passed QA
verification. Running the production Dart SyncEngine against live QA accounts
and all physical Nearby/GPS/device checks remain unverified.
Build 27 fixed a reproduced app-root incoming-prompt scheduling defect and
added connection tracing and finite transport timeouts. Build 28 fixes the
first-contact identity challenge parser contract and adds identity-stage and
disconnect attribution diagnostics. Build 29 retries locally queued image/video
delivery over Nearby and adds privacy-aware previews and transfer diagnostics.
Build 30 aligns advertising and outgoing-request fingerprint metadata, verifies
trusted identity after a hintless transport handshake, deduplicates reconnect
prompts, and preserves active connections across discovery/advertising restarts.
Build 31 preserved raw Google Nearby resolution status in a repository-local
Android plugin bridge and added lifecycle/session diagnostics. Build 32 keeps
that bridge, separates request/accept/result phases, changes the 35-second
application timeout to a non-destructive soft timeout, and uses a later hard
watchdog only for stale native negotiations. Physical retesting remains
pending; this source/test evidence is not a claim of radio success.
Physical testing across Android versions is still required before claiming
device-level compatibility; see
`docs/MANUAL_DEVICE_TESTS.md`.

## Active workspace

The active development repository and Git root are `D:\RELIO_Mobile`. Do not
use or modify any old RELIO workspace. The historical source path
`D:\ปี 3 เทอม 1\mobile app จารเกียร์\RELIO_Mobile` is retained only as an
inactive historical reference; it is not a runnable workspace.

## Requirements

- Flutter 3.44 or newer on the stable channel
- Dart 3.12 or newer
- Android SDK / Android Studio for Android builds

The current development machine uses Flutter 3.44.6, Dart 3.12.2, and Android
SDK 36. Android Studio's bundled JDK 21 is recommended.

## Run and verify

```bash
flutter pub get
flutter run --flavor dev --dart-define=RELIO_ENV=development
flutter analyze
flutter test
flutter build apk --flavor dev --debug --dart-define=RELIO_ENV=development
```

For an internal QA no-upload build, use `.\scripts\deploy-test.ps1 -NoUpload`.
QA updater values are loaded from `scripts/public-qa-config.ps1`; do not build
QA manually without those approved dart-defines. Run
`.\scripts\verify-qa-update-isolation.ps1` before QA packaging.

After Drift schema changes, generate sources with:

```bash
dart run build_runner build --delete-conflicting-outputs
```

If build_runner cannot write its AOT snapshot, use `--force-jit`:

```bash
dart run build_runner build --force-jit --delete-conflicting-outputs
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

For a release build, configure signing and run:

```bash
flutter build apk --release
```

The PROD Android application ID is `com.relio.relio_mobile`; DEV and QA have
separate flavor IDs. These IDs and the QA signing identity are preserved.

The public QA release is `0.9.0+33` (versionCode 33), available from
[the RELIO QA page](https://relio-17dc0.web.app/qa/) and its linked immutable
GitHub release. Build 33 passed automated verification; physical
interoperability remains pending an authorized two-phone retest. Release
publication alone does not establish device behavior. PROD remains
`com.relio.relio_mobile`.

## Public QA distribution and wireless updates (v0.9.0)

RELIO Test uses the internal Android flavor `qa` (the TEST environment name), application ID
`com.relio.relio_mobile.test`, and a dedicated local signing key. Prepare the
key once, then use the canonical publisher from the active workspace:

```powershell
.\scripts\setup-test-signing.ps1
.\scripts\publish-qa.ps1
```

The public pipeline runs format, analyze, tests, QA/PROD isolation, and a
signed QA build before creating an immutable GitHub release and deploying only
Firebase Hosting metadata for `relio-17dc0`. Firebase Hosting contains only
`/qa/index.html` and `/qa/latest.json`; the signed APK and `SHA256SUMS.txt`
are GitHub release assets. It never deploys Functions, Firestore, Realtime
Database, Storage, App Distribution, or Supabase resources. Future builds use
a fresh APK by default; `-ReuseExistingArtifact` is explicit. See
[docs/QA_RELEASE_WORKFLOW.md](docs/QA_RELEASE_WORKFLOW.md).

The QA variant contains the full Firebase App Distribution Android SDK for the
internal/fallback channel. DEV and PROD contain only the safe API-only stub;
public QA installation permission and update behavior are excluded from PROD.
The isolation verifier checks Gradle runtime dependencies and available flavor
APK permissions; the signed QA release pipeline also asserts the installer
permission is present in its final artifact.
The real QA Firebase config is
`android/app/src/qa/google-services.json` and targets
`com.relio.relio_mobile.test`; the Google Services Gradle plugin processes it
only as QA configuration. No Firebase Auth, Firestore, Storage, or Analytics
SDK is added; Supabase remains the cloud backend. See
[docs/QA_UPDATE_SYSTEM.md](docs/QA_UPDATE_SYSTEM.md).
Both QA build pipelines use `scripts/public-qa-config.ps1` as the canonical
source for the manifest URL, GitHub owner/repository, and update channel.
Missing or unapproved QA updater values fail at compile time.

The intended public first-install URL is `https://relio-17dc0.web.app/qa/`.
Ordinary download follows the exact authenticated owner's public
`RELIO-Android-Updates` release asset and does not require a Firebase tester
account or Google sign-in. Android still requires the user to approve unknown-
app installation and confirm the Package Installer update. The earlier
all-Firebase attempt was blocked by the Spark executable-file restriction; the
hybrid channel keeps the APK out of Hosting and does not upgrade billing or
use Firebase Storage. Build 13, Build 16, and Build 22 are immutable historical
releases. Build 33 is the current public QA physical-test candidate. Neither
source changes nor automated simulations establish physical radio behavior;
two-phone verification remains pending.

## Architecture

The code is organized by app foundation, feature, shared UI, and data:

```text
lib/
  app/       app shell, router, theme tokens, theme controller
  data/      mock models and centralized prototype data
  features/  onboarding, auth, home, nearby, chat, SOS, rescue, profile, sync
  core/media/ RELIO-owned media storage and transfer policy
  core/location/ on-demand location abstraction and fake test service
  shared/    reusable RELIO widgets
test/        widget smoke and interaction tests
```

`go_router` owns navigation. `RelioApp` owns the application-lifetime
`RelioThemeController`; its `SharedPreferencesThemePreferenceStore` is the
single persistence source for the `light`, `dark`, or `system` preference.
`MaterialApp.router` receives the live `ThemeMode` from that controller, while
Material 3 is configured through centralized RELIO color,
spacing, and typography tokens. Google Prompt is wired through `google_fonts`
with a safe fallback for offline development.

Optional cloud account, message, receipt, and managed-media operations use the
Supabase boundary. FCM is a QA-only push transport with consent/account gates;
the admin web application is a separate deployment and is not part of this
mobile runtime. Public QA updates use Hosting for metadata and GitHub Releases
for the APK; the PROD Play build excludes QA installation/update behavior.

For the main implementation boundaries, see `lib/core/nearby/` (packet and
transport coordination), `lib/core/repositories/` (local persistence),
`lib/core/media/` (managed attachment storage), `lib/core/sync/` (optional
Cloud queue), and `lib/features/` (screens). Tests use deterministic fake
Cloud and Mock Nearby implementations; ordinary tests do not require Internet.

The local write path is:

```text
UI → repository/domain → Drift/SQLite → local sync_queue → cloud adapter →
Supabase
```

UI code does not call Drift or the Nearby plugin directly. Plugin-specific
types stay inside `AndroidNearbyTransport`. `NearbyService` coordinates packet
validation, persistence, and acknowledgements without containing SQL.

## Offline-first and Nearby boundary

The database is authoritative for core local application state. An outgoing
message is inserted as `pending` before Nearby is attempted. Accepted transport
delivery moves it to `nearbySent`; a remote ACK moves it to `delivered`. Cloud
queue items are written after local persistence, and `SyncEngine` claims only
rows whose `ownerUserId` exactly matches the current authenticated Cloud user.
Guest rows remain local until explicit adoption; they are never auto-assigned
after login.
When a peer is unavailable, the message remains stored as `pending` for an
explicit retry after reconnection. Incoming messages are validated, deduped by
`messageId`, persisted, and acknowledged before the database stream updates
the UI. Media control is JSON, while image/video content uses native Nearby
file payloads; binary content is never Base64-encoded into protocol JSON. See
[docs/NEARBY_PROTOCOL.md](docs/NEARBY_PROTOCOL.md) and
[docs/MEDIA_TRANSFER.md](docs/MEDIA_TRANSFER.md).

## Verification status

Automated tests cover local persistence, protocol validation, identity and
trust decisions, simulated Nearby exchange, media integrity, notification
decisions, relay rules, and fake Cloud ownership. These tests do not exercise
Bluetooth/Wi-Fi radio behavior between real phones. Physical discovery,
permissions, GPS prompts, reconnect, image relay, and two-phone delivery remain
pending the manual checklist in `docs/MANUAL_DEVICE_TESTS.md`.

## Roadmap

- **v0.5:** Supabase Auth + Cloud Data + Storage Foundation
- **v0.6:** ownership-gated queue-driven cloud synchronization
- **v0.7:** live Supabase integration preparation and Cloud hardening
- **v0.8:** bounded Nearby relay/store-and-forward foundation
- **v0.9.0+22:** Android branding and guest SOS account-isolation public QA
  release; physical device acceptance remains pending.
- **v0.9.0+24 checkpoint:** persistent trust/chat read state and Android
  notifications.
- **v0.9.0+26 public QA:** bidirectional direct Cloud chat with explicit
  account linking, persistent local/cloud mappings, server-timestamp paging,
  stable-UUID merge, read-receipt reconciliation, and multi-account test
  coverage. Android Keystore-backed identity remains in place. RELIO-QA live
  migrations, RLS, direct chat/receipts, FCM backend authorization, Admin, and
  public OTA metadata are verified. Production SyncEngine-to-live-QA and
  physical device acceptance remain deferred.
- **v0.9.0+27 candidate:** app-root incoming prompt scheduling fix, connection
  trace IDs, finite native-result timeout, and DEV/QA privacy-tested
  diagnostics export. Physical device acceptance remains deferred.
- **v0.9.0+25 checkpoint:** Android Keystore-backed ECDSA identity, versioned
  replay-resistant challenge-response, pinned peer identity, and guarded
  trusted reconnect are implemented. RELIO-QA Supabase/FCM/Admin verification
  is complete; physical reconnect remains pending. See
  [docs/COMMUNICATION_PLATFORM_V09.md](docs/COMMUNICATION_PLATFORM_V09.md).
- **v1.0:** production security review, observability, accessibility audit,
  signed Android release, and end-to-end field testing

## Relationship to the React prototype

`RELIO_SOS` remains the visual/reference prototype. When parity work is needed,
compare flows and semantics between the two projects, but keep each project's
toolchain and source tree independent.
