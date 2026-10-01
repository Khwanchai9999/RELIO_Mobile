# RELIO Public QA release workflow

The supported publisher is `scripts/publish-qa.ps1`. It reads `version:` from
`pubspec.yaml` and derives the APK filename, GitHub tag, and release title from
that value. `scripts/public-qa-config.ps1` is the canonical source for the
approved manifest URL, GitHub repository, channel, Firebase project, package,
and signing certificate.

## Release sequence

DEVELOPMENT → TEST → VERSION → BUILD → GITHUB RELEASE → MANIFEST → FIREBASE
HOSTING → PHONE OTA

Every new installable QA application change needs a new build number. Use the
version recorded in `pubspec.yaml`; never infer or bump a build number as part
of publication. A version change requires an explicitly authorized release
task and fresh quality, build, and signing verification. Do not publish
different application binaries with the same version code.

From the project root, the normal future publication command is:

```powershell
Set-Location 'D:\RELIO_Mobile'
.\scripts\publish-qa.ps1
```

This requires a clean, pushed `main` checkout. It verifies formatting, analyze,
tests, QA/PROD isolation, then builds a fresh signed QA APK. It verifies the
APK and GitHub read-back before generating and validating the manifest and
deploying only Firebase Hosting metadata/page. GitHub CLI and Firebase CLI
are discovered from PATH and common Windows install locations.

For read-only preflight use:

```powershell
.\scripts\publish-qa.ps1 -DryRun
```

For a previously built artifact, explicitly opt in:

```powershell
.\scripts\publish-qa.ps1 -ReuseExistingArtifact
```

Before considering a release ready, run
`.\scripts\final-qa-preflight.ps1` from the clean, pushed Mobile `main` root.
It is a read-only external preflight (it does not upload, deploy, seed, or
install), but it requires verified QA Supabase identities, an authenticated
GitHub CLI, and the deployed QA Admin URL/anon key in the process environment.
Do not run it as a substitute for `publish-qa.ps1` or bypass its identity
checks.

To bind that run to a previously recorded digest, pass `-ExpectedSha256`.
Normal future releases build fresh; the publisher never selects an arbitrary
file from `dist`.

The phone sees an update only after both the verified APK exists as a GitHub
Release asset and live `latest.json` advertises it. Pushing source to GitHub
alone does not publish an OTA update. APK files remain on GitHub Releases;
Firebase Hosting receives only the QA page and manifest.

If a local process has a stale proxy, resolve that process environment before
running the publisher. The publisher does not change Windows, registry, or
user-wide proxy settings.
