# RELIO Android QA Distribution Autopilot Status

## Current state

- Workspace and Git root: `D:\RELIO_Mobile`
- Platform: Android only
- Previous Firebase App Distribution release: `0.8.5+11`
- Latest public QA release: `0.9.0+27`
- Build 24 checkpoint: `0.9.0+24` / versionCode 24 (not published or installed)
- Current candidate: `0.9.0+28` / versionCode 28 (unpublished, not installed)
- Build 23 Nearby fix: published and remotely verified; physical retest pending
- Previous public QA release: `0.8.6+21`
- Current public release tag: `qa-v0.9.0-b27`
- Drift schema: v7; v6 data is migrated by
  adding nullable pinned-key fields and disabling reconnect for legacy rows
- DEV package: `com.relio.relio_mobile.dev`
- QA package: `com.relio.relio_mobile.test`
- PROD package: `com.relio.relio_mobile`

## Build 26 — public Cloud communication baseline

- Cross-account direct conversation creation/linking, owner-scoped persistent
  mappings, paged Cloud pull, SQLite merge, UUID dedupe, unread tracking, and
  Cloud read-receipt reconciliation are implemented.
- SyncEngine actually calls paged message and receipt fetch methods. The
  shared-backend FakeCloud integration test models independent accounts and
  verifies import/restore, authorization, pagination, duplicate Nearby/Cloud
  delivery, unread count stability, and read receipts.
- Supabase migration `0007_cloud_direct_chat.sql` is source-reviewed only; no
  local PostgreSQL or QA backend is configured. No claim of live RLS/backend
  verification is made.
- FCM Edge Function dispatcher has seven mocked Node tests. It is not deployed,
  and real Android push delivery is not verified. Admin remains separately
  protected by authenticated profile roles and audited RPCs; no Admin source
  changes were needed for this Mobile pass.
- Build 26 is public QA. Physical Nearby, notification, and device acceptance
  remain deferred.

## Build 27 — public connection-diagnostics release

- Fixes root-Navigator incoming-request presentation when a Nearby page is no
  longer mounted, and bounds unanswered native connection results.
- Adds DEV/QA-only rolling redacted diagnostics and ZIP export. Production
  excludes the route and native share/device-info channel.
- Automated tests cover manual/auto single-flight, incoming-request navigation,
  legacy trust fallback, timeout/retry, endpoint-loss history preservation, and
  export redaction. Physical radio behavior is not verified in this workspace.

## Build 28 — first-contact identity-handshake candidate

- Build 27 physical logs from Huawei STK-L22/API 29 and Samsung SM-G965F/API 29
  showed that both sides accepted the nearby request and connected natively,
  then timed out after starting identity proof.
- Source audit found the initial challenge intentionally carries an empty
  stable target ID before enrollment, while the parser rejected empty values.
  The identity deadline also disconnected after eight seconds without useful
  stage attribution.
- Build 28 accepts that empty target only for the initial endpoint-scoped
  challenge, keeps signature verification, user acceptance, and key pinning,
  expands the finite handshake bound to 30 seconds, and fixes trusted
  reconnect auto-accept. Paired tests cover first contact, reconnect,
  simultaneous challenges, wrong signatures, and timeout attribution.
- No phone was modified or tested for Build 28. Physical retest is still
  required after installation by the owner.

## Firebase identity

- Project ID: `relio-17dc0`
- QA App ID: `1:789862464099:android:a26ab040a4fdbe1a899656`
- QA config: `android/app/src/qa/google-services.json`
- Hosting site: `relio-17dc0`
- Public QA URL: `https://relio-17dc0.web.app/qa/`
- Public manifest: `https://relio-17dc0.web.app/qa/latest.json`
- Build 22 release: [qa-v0.9.0-b22](https://github.com/Khwanchai9999/RELIO-Android-Updates/releases/tag/qa-v0.9.0-b22)
- Public QA page: [relio-17dc0.web.app/qa](https://relio-17dc0.web.app/qa/)
- Public manifest: [latest.json](https://relio-17dc0.web.app/qa/latest.json)
- Firebase App Distribution group: `relio-testers` (internal/fallback)
- Supabase remains the RELIO application cloud backend

## Build 25 — local secure-identity candidate

- Android Keystore generates and retains a P-256 signing key; only the X.509
  public key, SHA-256 fingerprint, and ECDSA signature cross the Flutter bridge.
- Protocol v2 challenges use a 256-bit secure random nonce, a short expiry,
  one-use local challenge state, and a signature binding protocol context and
  both stable device IDs. The fingerprint hint only selects a candidate peer.
- First/untrusted peers still require authentication-code approval. A matching
  pinned identity may auto-accept/reconnect; changed or blocked identities fail
  closed. Reconnect initiator is deterministic and retries are capped with
  exponential backoff.
- Migration v6 preserves v5 data and disables auto-reconnect for legacy trust
  records without a public-key pin.
- `dart format .`, `flutter analyze`, and all 151 Flutter tests passed locally.
  DEV debug, QA debug, signed QA release, and PROD verification builds passed;
  `scripts/deploy-test.ps1 -NoUpload` passed without uploading.
- The candidate remains local and unpublished. GitHub CLI's stored credential
  is invalid, so no release, push, or remote artifact verification was made.
- No phone was modified. Nearby radio/reconnect and OEM Keystore behavior are
  not physically verified.
- Supabase remote migrations, multi-user conversation membership/cloud pull,
  QA account seeding, FCM delivery, and Admin deployment remain unverified.

## Build 24 — local communication-platform checkpoint

The following is the historical Build 24 checkpoint record; it is superseded
by the current Build 25 section above.

- Historical source target: `0.9.0+24`, QA package `com.relio.relio_mobile.test`.
- Format, analyze, all 145 mobile tests, Windows PowerShell 5.1 syntax checks,
  QA/PROD isolation, DEV/QA/PROD debug builds, and the signed QA `-NoUpload`
  pipeline passed locally.
- The signed QA artifact is local at `dist/relio-test-0.9.0+24.apk`; it has not
  been uploaded, published, or installed on a phone.
- The migration and push Edge Function are source-only. No verified disposable
  QA Supabase project, Supabase CLI session, FCM service identity, or deployed
  webhook is configured. Admin deployment is not linked to Vercel.
- GitHub CLI reported an invalid stored credential at the time of this checkpoint.
- Build 24 did not include pinned cryptographic peer identity. Do not treat the
  historical checkpoint as a Build 25 capability or verification statement.

## Historical Build 17 — offline two-device demo hardening

- Build 17 (`0.8.6+17`) was prepared as a local QA verification build.
- It is not uploaded to Firebase App Distribution, GitHub Releases, or Firebase
  Hosting, and has not been installed on any phone.
- Automated tests cover runtime connectivity state, permission selection,
  hello identity mapping, pending-message flush after handshake, and SOS
  activation/clear propagation.
- Android radio behavior, runtime prompts, reconnection, and two-phone message
  and SOS flows remain deferred until a manual physical-device run.

## Build 21 — Android Nearby compatibility hardening

- Build 21 is required because Nearby runtime and Android manifest behavior
  changed from Build 20.
- One `NearbyReadiness` model combines SDK permission policy, actual grants,
  Bluetooth capability/state, optional Wi-Fi capability, legacy Location,
  Google Play Services, and transport support.
- Nearby requests coarse location on API 24–28, fine location on API 29–32,
  Bluetooth Scan/Connect/Advertise on API 31+, and Nearby Wi-Fi on API 33+.
  API 37 local-network permission is an upgrade gate when the app also targets
  API 37; the configured target remains API 36.
- Google Nearby's manifest sample declares `NEARBY_WIFI_DEVICES` from API 32,
  while Android's permission guide says the runtime permission is for apps on
  API 33+. RELIO requests it only on API 33+. The current official Nearby
  manifest requires fine Location through API 31; API 32 uses the modern
  Nearby Wi-Fi permission tier. SOS/Send Location permission remains separate.
  Plugin 4.3.0 also contributes permission declarations; the merged manifest
  is verified by the Android builds.
- SOS/location coordinates use `LocationService` separately. RELIO does not
  infer physical location from Nearby radio information.
- Wi-Fi is a capability/degradation for `P2P_CLUSTER`; Bluetooth remains the
  required radio. Lifecycle start/stop is serialized and retries on resume,
  radio changes, and periodic foreground checks. No background radio service
  is added.
- Local release validation passed. Automated tests cannot prove physical radio
  interoperability across devices.

## Public update implementation

- QA defaults to `PublicQaAppUpdateProvider` and fetches only `latest.json`.
- Firebase App Distribution is retained behind an explicit fallback provider;
  public QA users are not asked to enroll or sign in.
- Manifest validation gates schema, channel, package, versionCode, exact
  GitHub owner/repository/release path, SHA-256, size, release notes, and
  signing certificate. The manifest itself is fetched only from Firebase
  Hosting.
- APK verification gates package, exact higher versionCode, SHA-256, and the
  signer match against the installed QA application.
- Android Package Installer receives a temporary `content://` URI only after
  the user explicitly chooses download and installation remains user-confirmed.
- `REQUEST_INSTALL_PACKAGES` is QA-only; PROD has no public updater behavior or
  sideload permission.

## Quality baseline

- `dart format`: passed
- `flutter analyze`: passed
- `flutter test`: 125 passed for Build 22
- QA/PROD App Distribution SDK isolation: passed
- DEV debug, QA debug, QA signed release, and PROD debug verification builds:
  passed for Build 22. QA signed artifact:
  `dist/relio-test-0.9.0+22.apk`; package `com.relio.relio_mobile.test`;
  signing identity matches the preserved TEST keystore.
- `scripts/deploy-test.ps1 -NoUpload`: passed; no Firebase upload was made.
- Public Build 22 GitHub asset and Hosting page/manifest: deployed and remotely
  verified by the canonical publisher. Hosting contains metadata/page only; the
  APK is hosted as a GitHub release asset.
- `scripts/release-public-qa.ps1` is the only public release entrypoint; it
  verifies the signed APK, creates/verifies the GitHub release asset, deploys
  Hosting metadata only, and verifies both remote origins.

## Deployment status

The earlier all-Firebase deployment was **BLOCKED** by Firebase
Hosting's Spark-plan restriction: executable APK files are forbidden. The
hybrid channel resolves that limitation by keeping the APK in GitHub Releases
and deploying only page/manifest metadata to Hosting. No billing upgrade or
Firebase Storage fallback is used.

## Physical boundary

Previous Build 12 → Build 16 updater verification remains historical and is
not evidence of Build 22 installation. No phone was modified during Build 22
preparation or publication. Physical acceptance for Build 22—including
API-level permission prompts, OEM radios, discovery/reconnect, and
cross-version transfer—remains
**PENDING PHYSICAL TEST**.

## Build 23 — public QA release and Nearby fix

- Release: `0.9.0+23`, QA package `com.relio.relio_mobile.test`.
- QA page: https://relio-17dc0.web.app/qa/
- Manifest: https://relio-17dc0.web.app/qa/latest.json
- GitHub release: https://github.com/Khwanchai9999/RELIO-Android-Updates/releases/tag/qa-v0.9.0-b23
- APK: https://github.com/Khwanchai9999/RELIO-Android-Updates/releases/download/qa-v0.9.0-b23/relio-test-0.9.0+23.apk
- APK SHA-256: `b3eecc672f3cfdc83672a5078e90a2f892835dd748e2ef2f1629206c9fa8b540`
- APK size: `66,313,370` bytes; QA signing certificate SHA-256:
  `a5b3b13122d6a8cdbef9f933b4c6fdcc292ba7345649f9f5fe8632deaff62b1d`.
- `flutter test`: 142 passed. Format, analyze, QA/PROD isolation, DEV debug,
  QA debug, QA signed release, and PROD debug verification all passed.
- `scripts/publish-qa.ps1 -ReuseExistingArtifact`: passed. The immutable GitHub
  asset was not replaced; remote hash, package, version, and signer were
  verified. Firebase Hosting deployed only `/qa/index.html` and
  `/qa/latest.json`, with zero APK files, and both public origins were checked.
- Firebase App Distribution was not used. Public install remains independent
  of Firebase tester enrollment or Google login. No phone was modified;
  two-device Nearby acceptance is still pending.

## Build 22 — previous public QA release

- Release: `0.9.0+22`, QA package `com.relio.relio_mobile.test`.
- QA page: https://relio-17dc0.web.app/qa/
- Manifest: https://relio-17dc0.web.app/qa/latest.json
- GitHub release: https://github.com/Khwanchai9999/RELIO-Android-Updates/releases/tag/qa-v0.9.0-b22
- APK: https://github.com/Khwanchai9999/RELIO-Android-Updates/releases/download/qa-v0.9.0-b22/relio-test-0.9.0+22.apk
- APK SHA-256: `a71728c11a2006ec370b2951a929cd2f3829aebc1ce5bf5df4742b375b3ed112`
- APK size: `66,280,606` bytes; QA signing certificate SHA-256:
  `a5b3b13122d6a8cdbef9f933b4c6fdcc292ba7345649f9f5fe8632deaff62b1d`.
- Applied the supplied master logo to Flutter onboarding/About and generated
  Android legacy/adaptive launcher assets and splash resources from that same
  source. All flavors use the visible label `RELIO`.
- Guest-created SOS is stored locally and no longer enters the Cloud queue or
  inherits a later signed-in identity. Authenticated SOS queue rows are
  explicitly bound to the matching current user.
- Outgoing chat identity uses the current Cloud account when signed in and the
  stable device ID for guest/offline use; user-facing chat failures no longer
  expose raw exception strings. Unsupported call/menu actions were removed.
- All automated tests (125), four Android verification builds, QA/PROD SDK
  isolation, and remote GitHub/Hosting artifact checks passed before publish.
  The source release commit is `770788e`; no Firebase App Distribution or
  Play Store upload was made. No physical device has been modified; Nearby
  radio/OEM behavior remains deferred.
