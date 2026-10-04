# RELIO university submission checklist

## Source and explanation

- [ ] GitHub repository points to the intended RELIO Mobile Flutter project.
- [ ] README explains the problem, offline-first design, technology, features,
  architecture, run/test commands, and verification limits.
- [ ] Architecture, testing, and manual-device-test documents match the code.
- [ ] Latest source commit is pushed; no secrets, local credentials, diagnostic
  archives, or personal device notes are included.

## Build and evidence

- [ ] State the exact flavor, version, versionCode, and commit used for each
  screenshot or demo.
- [ ] Attach only an artifact produced by the documented release gates; record
  its SHA-256 and signer when distributing an APK.
- [ ] Include screenshots that show real app UI and identify mock/demo data.
- [ ] Mark unperformed physical, live-backend, GPS, and notification checks as
  pending instead of claiming success.
- [ ] Follow `docs/demo-checklist.md`; obtain consent before showing real
  account, message, SOS, or location data.

## Current handoff state

- Public QA physical-test candidate: RELIO `0.9.0+34`, versionCode 34.
- Build 34 automated, flavor, QA/PROD isolation, signer, and updater gates
  passed; the public GitHub asset and QA Hosting metadata were verified.
- Two-phone Native Nearby verification remains owner-controlled and pending.
