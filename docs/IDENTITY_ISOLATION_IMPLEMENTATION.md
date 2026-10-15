# Identity isolation candidate

## Identity boundaries

Device identity remains the existing `device_id`, Keystore key, fingerprint,
trusted pins and transport session. Changing the active account changes none
of those values and does not restart discovery, advertising or negotiation.

Application identity uses `account:<raw Supabase UUID>` or one persisted
installation Guest UUID (`app_settings.guest_principal`). Raw Cloud user IDs
remain raw in Cloud ownership columns. Names and avatars belong to principals.
A claimed account principal is application metadata, not proof of a Supabase
session or a replacement for signed device authentication.

`OwnerContext` captures raw owner plus generation and carries that immutable
snapshot through asynchronous work. Auth transitions invalidate even A → B → A.
Repository writes check the snapshot inside their SQLite transaction before
commit. UI dialogs, pickers, GPS and Cloud pulls retain the initiating context.
Conversation caches clear synchronously when the owner changes; chat shells
and profile futures rebind without retaining another owner's snapshot.

## Forward migration: SQLite version 9 → 10

New repository-owned SQL tables (no generated Drift files edited):

| Table | Responsibility |
| --- | --- |
| `local_principal_profiles` | Principal, kind, raw Cloud ID, name/custom state, avatar, revision/time |
| `conversation_principals` | Local principal, remote principal, physical route and active/quarantine state |
| `remote_principal_profiles` | Metadata per remote device and principal |
| `nearby_active_principals` | Last announced application principal per physical device |
| `profile_sync_snapshots` | Immutable queue owner/name/revision |
| `queue_principals` | Proven local principal at queue creation |

The migration preserves IDs, timestamps, messages, attachments, device settings,
trust pins and Cloud links. Proven conversation owners remain account scoped.
Conflicting Cloud/queue evidence, null ownership without provenance and absent
owners produce `legacyUnknown` quarantine. Unknown data is preserved in SQLite
and is not displayed to Guest or implicitly adopted on login. Global legacy
name/avatar settings remain untouched and are copied to an unknown profile.
There is no automatic claim/recovery UI for unknown legacy history in this round.

Existing account chats without a known remote account retain a distinct
`legacy-device:` relationship. They are not silently relabeled as whoever now
uses that phone. Private sends wait until an exact, principal-compatible route
is available. Explicit Guest adoption applies only to proven Guest rows.

## Profiles and Cloud

Auth restore, register, login and logout rebind the active profile. Cached
profiles work offline. Cloud fetches validate the requested user and generation;
revision/pending-edit checks happen in the same transaction as applying a fetch.
Profile edits persist locally and queue an immutable owner/name snapshot.
Obsolete snapshots cannot overwrite a newer local name during retry.

Avatar files live below a principal-specific directory. Replacement/removal
can delete only that principal's previous managed copy. Legacy root files and
other principals' files are preserved; no installation-wide orphan sweep runs.

Cloud import validates owner generation after awaits; repository transactions
roll back owner changes. Existing server membership RPC and Supabase schema
are unchanged. Automated verification uses FakeCloud, with no live uploads.

## Nearby application protocol

The v1 application envelope now includes optional `senderPrincipal` and
`recipientPrincipal`; identity challenge/proof retain v2 device authentication.
Hello/status carry profile revision and application principal generation.
Verified peers reannounce changes through the existing application channel.
Per-endpoint dispatch preserves packet order; stale announcements are ignored.

Private text/location/media/receipts/ACKs require valid principals and an exact
current recipient match. They also require the announced sender principal on
the already authenticated device endpoint. Missing/legacy/mismatched private
metadata is rejected, preserving the sender's local pending history. Receipts
must match the conversation's remote principal. Display-name routing and the
single-Mock-peer private routing shortcut are removed.

Logical conversations resolve by local + remote principal; device IDs select
transport endpoints. A remote Jane → Minnie switch retains both relationships,
names and histories while preserving the same trusted physical device.

As a dependency of private account isolation, existing relay-v1 payloads retain
the same principal fields and cannot materialize private text/location for a
different or unknown recipient. Forwarding, hop policy and SOS behavior are
unchanged; this does not add Multi-hop capabilities.

## Automated evidence

Acceptance results are recorded in the final implementation report. The new
identity tests cover A/B/Guest cached profiles, avatar files, chat/message/
attachment visibility, delayed Cloud results, immutable profile queue names,
legacy migration preservation/quarantine, remote person switches and missing/
wrong recipients. Existing hotfix 30-cycle reconnect and 10-cycle cancellation
tests remain unchanged. Packet fixtures explicitly declare their principals.

Automated tests and the QA build do not establish physical acceptance. This
round does not use ADB, install APKs, clear app data or operate phones.

## Later physical account-switch QA (maximum 12 steps)

1. Record existing version, accounts, chat counts, attachment samples, device
   identity/fingerprint and trusted peer on both phones; keep existing app data.
2. Install the reviewed QA candidate over the existing QA app after separate
   physical-test authorization; do not uninstall or clear data/cache.
3. Confirm migration preserves device identity, trust and known-owner history;
   unknown/conflicting history must not appear as Guest.
4. Set Guest name/avatar to GuestOne and note its local chat history.
5. Login A (Jane), verify its Cloud/cached name and set a distinct avatar; exchange
   a uniquely labeled private text and attachment with Bob on the other phone.
6. Login B (Minnie) on the same phone; verify Jane's profile, preview, header,
   messages and attachments are absent from B's screens.
7. Confirm Bob sees Minnie as a different relationship while the trusted device,
   fingerprint and Nearby session remain intact without another trust prompt.
8. Have Bob open Jane's old chat and send while Minnie is active: it must stay
   pending/unavailable and never appear in Minnie's chat. Then send to Minnie.
9. Return to Jane: verify Jane's original chat/avatar and history return and
   Minnie's content stays absent. Repeat A → B → A while a chat is open.
10. Sign out to Guest; verify GuestOne's name/avatar/history return. Change/remove
    B's avatar and confirm A and Guest files still render after switching back.
11. Restart offline under each cached identity; verify the matching profile and
    history, then reconnect Cloud and check owner-correct sync without adoption.
12. Run disconnect/reconnect and disconnect-during-connect checks; export only
    sanitized diagnostics and record physical outcomes separately.

## Acceptance matrix

| Requirements | Automated evidence |
| --- | --- |
| A–D | Independent cached A/B/Guest names, histories and managed avatar files |
| E–F | Stable device ID, key/pin/fingerprint and existing lifecycle regressions |
| G–J | Same remote device changes Jane → Minnie → Jane with separate logical chats |
| K–L | Wrong-owner conversation/message/attachment reads are empty; private viewer clears |
| M | Wrong recipient and missing principal packets never materialize under active account |
| N | Duplicate display name cannot select an endpoint without exact stable mapping |
| O–P | Stale Cloud import discarded and previous conversation preview cleared |
| Q | Delayed profile fetch cannot replace B or a newer pending local edit |
| R | Actual v9 fixture migration preserves rows, timestamps, avatar path and trust pin |
| S | Existing hotfix tests retain their original 30/30 reconnect and 10/10 cancellation assertions |

New test files add 13 tests; existing packet fixtures explicitly declare test
principals. Full suite: **393 passed**. Changed-file format: **PASS**.
`flutter analyze --no-pub`: **No issues found**. `git diff --check`: **PASS**.
QA signing preflight and QA/PROD SDK/installer isolation: **PASS**.

Source baseline: `fix/nearby-lifecycle-stability` at
`c88e979a41306b1df6f6dc34175052eb4a42fa93`.
Main baseline: `4645250b26d3983a080619fcdddc5f3c322cd11c`.
Version remains `0.9.0+38`; physical acceptance remains pending.

## Changed files

- `AGENTS.md`
- `README.md`
- `docs/IDENTITY_ISOLATION_IMPLEMENTATION.md`
- `lib/core/cloud/auth_service.dart`
- `lib/core/database/app_database.dart`
- `lib/core/identity/owner_context.dart`
- `lib/core/nearby/nearby_service.dart`
- `lib/core/nearby/relio_packet.dart`
- `lib/core/relay/relay_engine.dart`
- `lib/core/relay/relay_models.dart`
- `lib/core/relio_dependencies.dart`
- `lib/core/repositories/local_repositories.dart`
- `lib/core/repositories/principal_profile_repository.dart`
- `lib/core/repositories/profile_avatar_repository.dart`
- `lib/core/sync/sync_engine.dart`
- `lib/features/chat/chat_screens.dart`
- `lib/features/profile/profile_screen.dart`
- `lib/shared/widgets/relio_widgets.dart`
- `test/database_repository_test.dart`
- `test/identity_isolation_test.dart`
- `test/identity_owner_context_test.dart`
- `test/identity_ui_isolation_test.dart`
- `test/nearby_mock_test.dart`
- `test/pre_physical_chat_test.dart`
- `test/profile_feature_test.dart`
- `test/relay_engine_test.dart`
- `test/support/nearby_pair.dart`
- `test/support/principal_packets.dart`
- `test/v03_nearby_integration_test.dart`
- `test/v04_media_location_test.dart`

## QA artifact

QA release built **once**, after automated gates passed. Signature verification,
canonical QA signer, package `com.relio.relio_mobile.test`, version `0.9.0+38`
and non-debuggable release mode: **PASS**.

- APK: `D:\RELIO_Mobile\build\app\outputs\flutter-apk\app-qa-release.apk`
- SHA-256: `654bcc93ce9eeee7963f747d4641dc9d59c5a0016caad4bd943dc4e7440a0e7f`
- Size: 100626485 bytes
- No ADB, phone installation, physical tests, upload, push or merge in this round.

IDENTITY ISOLATION AUTOMATED ACCEPTANCE: PASS

READY FOR PHYSICAL ACCOUNT-SWITCH QA: YES
