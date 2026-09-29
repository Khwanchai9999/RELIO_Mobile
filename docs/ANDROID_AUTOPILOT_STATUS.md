# RELIO Android QA Distribution Autopilot Status

## Current state

- Workspace and Git root: `D:\RELIO_Mobile`
- Platform: Android only
- Previous release: `0.8.5+11` through Firebase App Distribution
- Current milestone: `0.8.6+12` through public Firebase Hosting QA
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
- Firebase App Distribution group: `relio-testers` (internal/fallback)
- Supabase remains the RELIO application cloud backend

## Public update implementation

- QA defaults to `PublicQaAppUpdateProvider` and fetches only `latest.json`.
- Firebase App Distribution is retained behind an explicit fallback provider;
  public QA users are not asked to enroll or sign in.
- Manifest validation gates schema, channel, package, versionCode, HTTPS
  origin/path, SHA-256, size, release notes, and signing certificate.
- APK verification gates package, exact higher versionCode, SHA-256, and the
  signer match against the installed QA application.
- Android Package Installer receives a temporary `content://` URI only after
  the user explicitly chooses download and installation remains user-confirmed.
- `REQUEST_INSTALL_PACKAGES` is QA-only; PROD has no public updater behavior or
  sideload permission.

## Quality baseline

- `dart format`: passed
- `flutter analyze`: passed
- `flutter test`: 86 passed
- QA/PROD App Distribution SDK isolation: passed
- DEV debug, QA debug, QA signed release, and PROD verification builds are
  required before the public release pipeline can deploy.
- `scripts/release-public-qa.ps1` is the only public Hosting release entrypoint;
  it deploys Hosting only and verifies the remote page, manifest, APK, and hash.

## Deployment status

Build 12 is prepared locally, but public deployment is **BLOCKED** by Firebase
Hosting's Spark-plan restriction: executable APK files are forbidden. The
Hosting deploy was not activated and the page, manifest, and APK URLs all
returned 404 afterward. No billing upgrade or Firebase Storage fallback was
performed.

## Physical boundary

The automated work does not claim OEM Android installer behavior. The user must
open the public QA URL on an Android phone, install Build 12, confirm
`0.8.6+12`, create persistent local data, and confirm `ตรวจสอบอัปเดต` reports
no newer build. Build 13 and v0.9 remain blocked until that baseline is
confirmed.
