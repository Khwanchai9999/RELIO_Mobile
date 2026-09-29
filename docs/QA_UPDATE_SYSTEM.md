# RELIO v0.8.5 QA wireless update system

## Scope

`RELIO Test` is the only variant that may contain the full Firebase App
Distribution Android SDK. The package is `com.relio.relio_mobile.test`, and
the release version is `0.8.5+11`. DEV and PROD use the API-only library, so
their Dart code can safely report “not applicable” and their APKs do not carry
the full self-update implementation.

The app uses the official Firebase basic update flow through a small Kotlin
MethodChannel. Firebase owns tester sign-in, the update dialog, download
progress, and the Android installation confirmation. RELIO never downloads an
APK itself and never requests silent installation.

## Flutter boundary

`AppUpdateService` exposes only build/environment metadata, availability,
status, and `checkForUpdate({manual})`. The gateway is fakeable in Flutter
tests. The Flutter service invokes the Android gateway only for the QA
environment; the bridge calls `updateIfNewReleaseAvailable()` and returns a
safe no-op/unavailable state when the full implementation is absent. Error
states do not expose account details, tokens, or exception text.

Automatic checks run after app startup and when the app returns to the
foreground. They are throttled by a 30-minute cooldown. The TEST Settings
screen has `ตรวจสอบอัปเดต`, which bypasses the cooldown. DEV and PROD do not
show this control.

## Firebase SDK isolation

The module declares:

- `firebase-appdistribution-api` for every variant. This API-only library has
  no effect without the implementation.
- `firebase-appdistribution` under `qaImplementation` only.

Run the machine check from the repository root:

```powershell
.\scripts\verify-qa-update-isolation.ps1
```

It inspects `qaReleaseRuntimeClasspath` and `prodReleaseRuntimeClasspath` and
fails if QA lacks the full SDK or PROD contains it.

The real QA Firebase config is tracked at
`android/app/src/qa/google-services.json` and is for the exact package
`com.relio.relio_mobile.test`. The Google Services Gradle plugin is declared in
`android/settings.gradle.kts`, applied by the app module, and configured with a
WARN policy so DEV/PROD remain buildable without Firebase config. The config
contains only the identifiers required by App Distribution; no Firebase Auth,
Firestore, Storage, or Analytics SDK is added.

## Tester flow

First install:

1. Build and distribute the signed QA APK through Firebase App Distribution.
2. The tester accepts the invitation and signs in to the official tester
   experience with Google.
3. The tester installs the first QA build and opens RELIO Test.
4. The official in-app alert flow may ask the tester to enable alerts.

Future updates:

1. A new QA release is distributed with a higher `versionCode` and the same
   package and signing key.
2. Startup/foreground checking can show the official update dialog, or the
   tester can use `ตรวจสอบอัปเดต`.
3. The tester confirms the Android installation. There is no silent APK
   installation.

The same package, signing key, and monotonic version code preserve the app's
SQLite/Drift data during a normal Android update: messages, SOS data,
attachments, sync queue, relay packets, forwarding history, and settings.
An uninstall or lost signing key is a different, destructive event and is not
part of this update flow.

## One-time Firebase setup

1. Register Firebase Android app `com.relio.relio_mobile.test`; do not register
   the PROD package for this tester channel.
2. Enable Firebase App Distribution and the Firebase App Testers API.
3. Install Firebase CLI and authenticate with `firebase login` (or the team's
   approved CI authentication). Never put tokens or passwords in the repo.
4. Create the recommended tester group alias `relio-testers` and add real
   testers in Firebase. No tester email is stored in this repository.
5. Set `FIREBASE_APP_ID` and either `FIREBASE_GROUPS=relio-testers` or
   `FIREBASE_TESTERS` in the local environment. If `FIREBASE_APP_ID` is absent,
   the deployment script uses `mobilesdk_app_id` from the verified QA config.
   If neither group nor tester is supplied, it uses the authorized
   `relio-testers` group.
6. Keep the original `android/relio-test.keystore` and its password backed up.
7. Run `.\scripts\deploy-test.ps1`; it stops with a clear deferred message
   when live Firebase values are absent.

## Verification boundary

Automated tests prove the Flutter state machine, fake gateway, cooldown, and
safe error mapping. The build isolation script proves the PROD dependency
graph does not include the full SDK. Actual tester sign-in, Firebase network
availability, update alerts, Android download/install confirmation, and
SQLite-preserving over-the-top updates remain manual device verification.
