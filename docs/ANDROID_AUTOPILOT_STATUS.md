# RELIO Android QA Distribution Autopilot Status

## Current state

- Workspace and Git root: `D:\RELIO_Mobile`
- Platform: Android only
- Version/build: `0.8.5+11` (Build 11 baseline)
- Current commit: see `git rev-parse HEAD` in the active workspace
- Drift schema: v4
- Tests: 76 passing
- DEV package: `com.relio.relio_mobile.dev`
- QA package: `com.relio.relio_mobile.test`
- PROD package: `com.relio.relio_mobile`

## Firebase QA identity

- Project ID: `relio-17dc0`
- QA App ID: `1:789862464099:android:a26ab040a4fdbe1a899656`
- Config: `android/app/src/qa/google-services.json`
- Firebase products: App Distribution only; Supabase remains the cloud backend

## Distribution readiness

- Firebase CLI: installed (`15.32.0`)
- Authentication: blocked; no authorized Firebase CLI account is logged in
- Exact-project verification: pending authentication
- App Distribution: code/config ready; live upload blocked pending authentication
- App Testers API: not verified; Firebase Console check remains manual
- `relio-testers` group: not verified; empty-group creation is prepared after
  exact project access is authenticated
- Approved tester: none configured

## Quality and builds

- `dart format .`: passed
- `flutter analyze`: passed
- `flutter test`: 76 passed
- DEV debug: passed
- QA debug: passed
- QA signed release: passed
- PROD debug verification: passed
- QA/PROD SDK isolation: passed
- `deploy-test.ps1 -NoUpload`: passed; no live upload performed
- QA signing: existing `android/relio-test.keystore` certificate verified

## Remaining blockers and next milestone

- Complete interactive `firebase login` with the intended Firebase account.
- Verify App Testers API and create/reuse the empty `relio-testers` group.
- Explicitly approve at least one tester email before live upload.
- Install Build 11 on a real Android phone and complete the manual smoke/update
  flow; wireless update remains pending physical verification.
- After Build 11 installation is confirmed, explicitly prepare and distribute
  Build 12 using the documented workflow.

Do not start v0.9 or claim wireless-update success until the physical Android
verification is complete.
