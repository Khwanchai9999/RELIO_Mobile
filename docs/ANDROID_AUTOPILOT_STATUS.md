# RELIO Android QA Distribution Autopilot Status

## Current state

- Workspace and Git root: `D:\RELIO_Mobile`
- Platform: Android only
- Previous Firebase App Distribution release: `0.8.5+11`
- Latest public QA release: `0.9.0+22`
- Current QA candidate: `0.9.0+23` (Build 23 Nearby fix; publication pending)
- Previous public QA release: `0.8.6+21`
- Current release tag: `qa-v0.9.0-b22`
- Drift schema: v4
- DEV package: `com.relio.relio_mobile.dev`
- QA package: `com.relio.relio_mobile.test`
- PROD package: `com.relio.relio_mobile`

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

## Build 22 — public QA release

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
