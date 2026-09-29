# RELIO v0.8.6 Public Android QA Update Channel

## Purpose

RELIO Test `com.relio.relio_mobile.test` uses Firebase Hosting as the normal
public QA first-install and update channel. The confirmed site is
`relio-17dc0`, with the public page at:

```text
https://relio-17dc0.web.app/qa/
https://relio-17dc0.web.app/qa/latest.json
```

Ordinary testers do not need Firebase App Distribution enrollment, a Firebase
account, or Google sign-in. Firebase App Distribution Build 11 remains intact
as an internal/fallback channel and is not removed by this system.

## Provider boundary

`AppUpdateService` uses these boundaries:

- `PublicQaAppUpdateProvider` → `PublicQaUpdateProvider`: default in QA;
  fetches only the small HTTPS manifest and downloads only after an explicit
  user action.
- `FirebaseAppDistributionUpdateProvider`: retained as an internal fallback;
  it is not selected by default and does not trigger tester enrollment.
- `Fake` provider implementations in tests: deterministic checks without
  network or Firebase login.
- `AppUpdateInstaller`: testable boundary for APK inspection, install
  permission, FileProvider URI creation, and Android Package Installer launch.

Startup and foreground checks only fetch `latest.json`, remain non-blocking
when offline, and use the existing 30-minute cooldown. The Settings action
`ตรวจสอบอัปเดต` bypasses that cooldown. A newer manifest is shown to the user;
the APK is not downloaded automatically.

## Manifest schema

`latest.json` uses schema version 1:

```json
{
  "schemaVersion": 1,
  "channel": "qa-public",
  "packageName": "com.relio.relio_mobile.test",
  "versionName": "0.8.6",
  "versionCode": 12,
  "apkUrl": "https://relio-17dc0.web.app/qa/relio-test-0.8.6+12.apk",
  "sha256": "64 lowercase hexadecimal characters",
  "sizeBytes": 123,
  "signingCertSha256": "64 hexadecimal characters",
  "publishedAt": "2026-09-29T00:00:00.000Z",
  "releaseNotes": ["Thai or English release notes"]
}
```

The parser rejects unsupported schema versions, wrong channel/package, invalid
version values, non-HTTPS URLs, hosts or paths outside the approved Hosting
`/qa/` origin, malformed hashes/fingerprints, unreasonable file sizes, bad
timestamps, and malformed release notes. An update is offered only when
`versionCode` is greater than the installed build.

## Download and verification flow

1. The user taps `ดาวน์โหลดอัปเดต` after reviewing the current/new version,
   release notes, and size.
2. The provider downloads to app-controlled cache storage with a deterministic
   versioned filename and removes obsolete cached update APKs.
3. The downloaded byte count and SHA-256 must match `latest.json`; a mismatch
   deletes the file and never reaches Android.
4. Native Android `PackageManager` inspects package name and versionCode.
5. The APK signer is compared with the manifest fingerprint and the currently
   installed RELIO Test signer. Wrong package, same build, downgrade, malformed
   APK, or signer mismatch is rejected.
6. QA checks `canRequestPackageInstalls()`. If needed, the app opens the
   user-controlled `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` page.
7. The app passes a temporary `content://` FileProvider URI to Android Package
   Installer. Android always asks the user to confirm installation/update.

There is no silent install, root install, ADB install, accessibility click,
background install, or raw `file://` URI. Local SQLite/Drift data remains under
Android's normal same-package/same-signer update behavior.

## Flavor safety

- QA has `REQUEST_INSTALL_PACKAGES`, the public updater, and the full Firebase
  App Distribution SDK.
- DEV has no public QA updater behavior and no sideload permission.
- PROD has no public QA updater behavior, no sideload permission, and only the
  API-only App Distribution dependency. Supabase remains the application cloud
  backend; no Firebase Auth, Firestore, Storage, or Analytics SDK is added.

The machine check is:

```powershell
.\scripts\verify-qa-update-isolation.ps1
```

## Release and Hosting pipeline

From `D:\RELIO_Mobile`, use:

```powershell
.\scripts\release-public-qa.ps1 -NoDeploy
.\scripts\release-public-qa.ps1
```

The script derives its root from `$PSScriptRoot`, requires `0.8.6+12`, runs
format/analyze/tests, checks QA/PROD isolation, builds the signed QA APK,
verifies package/version/signing, generates `public_update/qa/latest.json` and
the download page, then deploys only:

```text
firebase deploy --only hosting:relio-17dc0 --project relio-17dc0
```

It verifies the public page, manifest, APK URL, and remote APK SHA-256 after
deployment. `public_update/` is generated and ignored; the template and
Firebase Hosting configuration are maintained in the repository. Hosting
headers keep `latest.json` non-cacheable and versioned APKs immutable.

### Current Hosting blocker

The first live deployment was intentionally stopped by Firebase with:
`Executable files are forbidden on the Spark billing plan`. Firebase Hosting
did not activate the page, manifest, or APK; all three public URLs remain 404.
Do not upgrade billing automatically and do not switch to Firebase Storage or
another Firebase service. The user must explicitly choose an approved
hosting/billing path before this public channel can become live.

## Manual boundary

Automated tests prove manifest validation, provider selection, cooldown,
offline/error mapping, download failure handling, APK metadata/signer gates,
and install permission states. They do not prove OEM Android installer behavior.
The physical first-install baseline remains manual: open the public URL on an
Android phone, install Build 12, open RELIO Test, confirm `0.8.6+12`, create
persistent local data, and confirm `ตรวจสอบอัปเดต` reports no newer version.

Build 13 is reserved for a later physical `12 → 13` OTA verification. Do not
create Build 13 or start v0.9 before the user confirms the Build 12 baseline.
