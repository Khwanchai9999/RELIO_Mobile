# RELIO Android QA Distribution Autopilot Status

## Current state

- Workspace and Git root: `D:\RELIO_Mobile`
- Platform: Android only
- Previous release: `0.8.5+11` through Firebase App Distribution
- Current milestone: `0.8.6+13` through the hybrid public QA channel
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
- `flutter test`: 88 passed
- QA/PROD App Distribution SDK isolation: passed
- DEV debug, QA debug, QA signed release, and PROD verification builds are
  required before the public release pipeline can deploy.
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

The automated work does not claim OEM Android installer behavior. Build 12 is
already the physical baseline on two Android phones. The next manual action is
to open RELIO Test on a phone still running Build 12 and tap
`ตรวจสอบอัปเดต`, then confirm the user-controlled download/install flow and
that local data remains present. Physical status:
**Build 12 → Build 13 in-app OTA: PENDING PHYSICAL TEST**. Do not ADB-install
Build 13 or start v0.9.
