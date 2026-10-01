# RELIO Android QA Distribution Autopilot Status

## Current state

- Workspace and Git root: `D:\RELIO_Mobile`
- Platform: Android only
- Previous release: `0.8.5+11` through Firebase App Distribution
- Previous source baseline: `0.8.6+20`
- Compatibility release target: `0.8.6+21`
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
- Build 21 target tag: `qa-v0.8.6-b21` in the public
  `RELIO-Android-Updates` repository; publication is not verified
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
  API 33+. RELIO requests it only on API 33+ and keeps the API 32 fine-location
  tier because older Wi-Fi discovery paths can require Location. Plugin 4.3.0
  also contributes permission declarations; the merged manifest is verified by
  the Android builds.
- SOS/location coordinates use `LocationService` separately. RELIO does not
  infer physical location from Nearby radio information.
- Wi-Fi is a capability/degradation for `P2P_CLUSTER`; Bluetooth remains the
  required radio. Lifecycle start/stop is serialized and retries on resume,
  radio changes, and periodic foreground checks. No background radio service
  is added.
- Local release validation passed. Automated tests cannot prove physical radio
  interoperability across devices; public upload/Hosting checks remain
  unverified until CLI credentials and remote checks succeed.

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
- `flutter test`: 123 passed for Build 21
- QA/PROD App Distribution SDK isolation: passed
- DEV debug, QA debug, QA signed release, and PROD debug verification builds:
  passed for Build 21. QA signed artifact:
  `dist/relio-test-0.8.6+21.apk`; package `com.relio.relio_mobile.test`;
  signing identity matches the preserved TEST keystore.
- `scripts/deploy-test.ps1 -NoUpload`: passed; no Firebase upload was made.
- Public Build 21 release and Hosting deployment: not verified in this status
  snapshot. Do not report it as publicly available without remote verification.
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
not evidence of Build 21 installation. No phone was modified during Build 21
preparation. Physical acceptance for Build 21—including API-level permission
prompts, OEM radios, discovery/reconnect, and cross-version transfer—remains
**PENDING PHYSICAL TEST**.
