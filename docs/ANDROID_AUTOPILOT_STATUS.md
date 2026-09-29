# RELIO Android QA Distribution Autopilot Status

## Current state

- Workspace and Git root: `D:\RELIO_Mobile`
- Platform: Android only
- Previous release: `0.8.5+11` through Firebase App Distribution
- Current source milestone: `0.8.6+17` (local-only QA verification)
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
- Public APK: authenticated-owner GitHub release asset in
  `RELIO-Android-Updates`, tag `qa-v0.8.6-b13`
- Firebase App Distribution group: `relio-testers` (internal/fallback)
- Supabase remains the RELIO application cloud backend

## Build 17 — offline two-device demo hardening

- Build 17 (`0.8.6+17`) is prepared as a local QA verification build only.
- It is not uploaded to Firebase App Distribution, GitHub Releases, or Firebase
  Hosting, and has not been installed on any phone.
- Automated tests cover runtime connectivity state, permission selection,
  hello identity mapping, pending-message flush after handshake, and SOS
  activation/clear propagation.
- Android radio behavior, runtime prompts, reconnection, and two-phone message
  and SOS flows remain deferred until a manual physical-device run.

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
- `flutter test`: 103 passed for the current Build 17 source
- QA/PROD App Distribution SDK isolation: passed
- DEV debug, QA debug, QA signed release, and PROD verification builds are
  required for local QA verification. Build 17 is not a public release.
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

The automated work does not claim OEM Android installer behavior. The user
confirmed Build 15 on Realme reports “up to date” against public Build 13,
validating the corrected updater configuration on-device. The latest ADB check
found no connected devices, so Huawei's installed package and APK hash remain
unverified; Huawei is intended to remain on Build 12. Build 16 is published
and its live manifest, page, APK hash, package, version, and signer were
verified. No phone was modified for Build 17. Physical status:
**Build 12 → Build 16 in-app OTA: PENDING PHYSICAL TEST**.
