# Build 40–43 online Auth and three-device Relay acceptance — 2026-10-28

Workspace `D:\RELIO_Mobile`, branch `fix/relio-offline-acceptance`. No push,
merge, app-data clear, trust reset, radio-setting change, or new SOS action.
User opened Internet on all three phones. Walking-distance acceptance remains
deferred by the user. Earlier Build 39 evidence remains separate.

## Confirmed defects and fixes

1. Login forgot-password button was a no-op. Build 40 adds request/reset screens,
   AuthService/adapter methods, SDK-verified recovery gating, exact flavor URI,
   neutral request success copy, and FakeCloud/widget regression coverage.
2. Real Build 40 outage test confirmed a missing final receipt after upstream
   went away. C had received once, B had persisted delivered, but A remained at
   stored after returning. Build 41 replays delivered Text receipts still within
   TTL from SQLite to the original upstream. Successful receipts are suppressed
   per endpoint until reconnect/process restart. Failed sends remain retryable.
   TEST Text only; no schema, OwnerContext, SOS, PROD routing changes.
3. Thai QA relay logs distinguish รับฝากแล้ว / ส่งต่อแล้ว / ถึงปลายทางแล้ว.
   Stored never means recipient delivered. Receipts remain authenticated-peer
   assertions, not end-to-end cryptographic signatures from C.
4. Build 42 restricts final receipt replay to endpoints with completed RELIO
   identity handshake. Native connected alone is insufficient. This avoids
   caching a successful native send before the remote application accepts it.
5. Build 43 persists a non-secret recovery guard before publishing recovery UI.
   Restored SDK sessions retain recovery state until explicit password change,
   password login or logout. This prevents a normal initialSession event after
   restart from implicitly enabling authenticated Sync during recovery.

## Live QA backend and Auth evidence

- Existing verified RELIO-QA project `zeuiqspvqiplusiugcto` was INACTIVE and its
  hostname unavailable. Restored the same project via supported Supabase restore;
  observed ACTIVE_HEALTHY. No new project or schema migration.
- Existing QA A/B credentials each sign in via live API and read their own
  profile. Wrong password returns HTTP 400.
- Added exact redirect `com.relio.mobile.qa://auth-reset/` through supported
  Supabase config pull/diff/push. Preview contained exactly one changed auth
  property; subsequent diff was empty. Other auth configuration preserved.
  Local ignored backup: build/qa40-config-before.toml, SHA-256
  E22097C53D9784538B57FE0174D15216126DE7D66F71F0117D6AC5805AB74029.
- Build 40 Samsung physical Login: wrong-password Thai error observed; correct
  QA A login shows its own Jane profile; process restart retains session;
  logout and Guest entry restore original Guest profile/history and trusted
  Nearby state. No adoption of Guest data performed.
- Build 40 Realme physical QA B login shows Minnie; logout and Guest entry
  restore Bob and his avatar. Nearby transport/device trust is not reset.
- Forgot button physically opens the new screen. Empty input shows Thai
  validation. Live reset request for existing QA address returns
  `email_address_invalid`; UI shows the mapped error.
- All available QA addresses use example.invalid. **Mailbox delivery, valid or
  expired emailed link handling, and a real password change are UNVERIFIED.**
  No admin-generated token or artificial session was substituted for email.
- Android resolve-activity maps the exact QA callback to the QA package.
  Automated FakeCloud tests cover recovery-required, invalid/mismatched inputs,
  neutral requests, account separation, callback filtering and successful reset.

## Build 40 physical after-stored outage — before receipt fix

Samsung A (41dfa7bb30b4) → Huawei B (7eaa913c9cfd) → Realme C (a80ab9e75e3c).
P2P_CLUSTER / CLUSTER_BASELINE. QA forced first-hop excludes direct A–C for
this payload even if that link is available.

Payload `7eb8cbec0631`, envelope `85ac16232197`, maxHops 2:

- A sends hop 1 at 05:35:41 UTC; A receives stored ACK.
- B stores hop 1 while QA hold is ON; B sends stored ACK.
- Disconnect B–C through app diagnostics after storage, stop A process, release
  B hold, restart B without clearing data, allow trusted reconnection.
- Fresh B PID 23136 sends the same envelope at hop 2, 05:38:24 UTC, while A PID
  is absent. B receives delivered ACK at 05:38:28.
- C records one payload_delivered at 05:37:52; same-ID retransmission at
  05:38:24 is duplicate_suppressed with delivered ACK, no second materialization.
- Initial C delivery relative to B restart cannot be established precisely from
  retained logs; only the fresh-process retransmission is proven for this case.
- A returns and makes its bounded third attempt, but no delivered ACK is
  observed. This is **PARTIAL / receipt FAIL**, not complete physical PASS.

Stage exports retained in build/qa40-before-cut-*.json,
qa40-after-cut-Huawei.json, qa40-fresh-middle-process.json,
qa40-middle-restart-Realme.json and qa40-source-latest.json. Log buffers roll
over; missing historical events were not reconstructed as native evidence.

## Automated verification

- Build 40 full QA: 460 passed; DEV: 454 passed / 6 QA-only skipped.
- Build 41 focused recovery + Relay: 21 passed.
- Build 41 full QA: 461 passed; DEV: 454 passed / 7 QA-only skipped.
- Build 41 format/analyze and QA/PROD isolation passed in deploy-test -NoUpload.
- Build 42 full QA: 461 passed; DEV: 454 passed / 7 QA-only skipped. Its build
  process was stopped before completion because the recovery restart guard
  required a new version. It was not installed on phones.
- **Final Build 43 full QA: 462 passed; DEV: 455 passed / 7 QA-only skipped.**
- Final format/analyze PASS, git diff --check PASS, QA/PROD installer/Firebase
  isolation PASS. Signed QA build PASS, preserved TEST signer match PASS,
  expected package/versionCode 43 PASS. No upload (-NoUpload).
- Final artifact: `dist/relio-test-0.9.0+43.apk`, SHA-256
  `85AD2E205998220AFF5CEF0DF5E11E3A390A7E180459E5DD98CA951790743058`.
- Build 43 was installed with `adb install -r` on Samsung SM-G990E
  `RFCT611DBBP`, Huawei STK-L22 `YDVNW19B23003867`, and Realme RMX3661
  `c821a16d`: **3/3 Success**. Package dump reports versionCode 43 on each.
  Original `firstInstallTime` values remained 2026-10-26 21:06:02,
  2026-10-20 11:16:25, and 2026-09-29 20:10:56 respectively; no app clear,
  uninstall or trust reset occurred. The installed APK was not pulled and
  independently hashed from each phone.

## Build 43 physical after-stored Relay acceptance — PASS

Samsung A `41dfa7bb30b4` → Huawei B `7eaa913c9cfd` → Realme C
`a80ab9e75e3c`, Guest principals. QA forced-through-Huawei mode selected
while A–C direct link was also available; this probe did not use A–C.
Payload alias `0168d47e6a4c`, envelope alias `d0a0d2c117ee`, maxHops 2.
All timestamps below are 2026-10-28 UTC.

1. A `packet_enqueued` at 08:05:13.135, `forward_sent` to B at hop 1 at
   08:05:13.168, then `ack_received stored` at 08:05:13.277.
2. With QA Text hold ON, B `envelope_stored` at hop 1 at 08:05:13.822 and
   `ack_sent stored` at 08:05:13.860. B's screen said “รับฝากแล้ว — บันทึกในเครื่อง รอส่งต่อ”.
3. A and C app processes were stopped without clearing data. B hold was set OFF;
   B process was then stopped and reopened while C remained stopped. C process
   reopened; B attempted the same hop-2 envelope at 08:06:39.286. C then
   selected its original Guest principal. B retried the original ID at
   08:07:22.017 while A remained stopped. The captured logs do not establish
   which native send led to C's materialization.
4. C recorded one `envelope_stored` at hop 2 (08:07:21.540), exactly one
   `payload_delivered` (08:07:21.603), and `ack_sent delivered`
   (08:07:21.612). Later ACK/retry events did not produce a second
   `payload_delivered` in the captured C log. B recorded `ack_received delivered`.
5. A reopened and selected its original Guest principal. It retried the same
   envelope to B at 08:08:07.104; B logged `final_ack_propagated` for the
   durable delivered receipt after reconnect at 08:08:22.004. A recorded
   `ack_received delivered` at 08:08:21.493. The phone clocks/log emission
   differ by about one second, so these timestamps do not prove exact send/
   receive order. Samsung QA UI displayed “ถึงปลายทางแล้ว — ได้รับ ACK ยืนยัน”.

This proves the controlled after-stored, middle-process-restart, C-delivery and
final A-receipt path for one real three-phone Text probe. A received an
authenticated Nearby receipt through B; this is not an end-to-end signed C
receipt. Walking-distance transition and different role assignments remain
unverified, as the user deferred moving the phones.

## Final QA controls and Auth smoke

- Huawei QA Text forwarding hold was visually verified OFF after the test.
  Samsung hold was OFF. Realme hold was last observed OFF before this probe.
- Samsung new-message mode was visually restored to Automatic. Huawei and
  Realme were Automatic at their last observed mode selection.
- Final Home screens on all three showed Internet online and retained Guest
  profiles. Samsung Nearby List showed two connected REAL peers, separate
  DEMO data, and stale-location warnings; MapLibre rendered map tiles. This
  verifies presentation and live peer listing, not location accuracy.
- Build 43 Samsung signed into existing QA A (Jane), retained session after
  force-stop/reopen, then signed out to its original Guest profile. Build 43
  Realme signed into existing QA B (Minnie), signed out, and restored Guest Bob
  with original avatar. No Guest-history adoption was requested or performed.
- Build 43 Samsung physically opened the forgot-password screen and an empty
  request showed Thai required-email validation. Build 40 had already shown
  physical wrong-password error and backend `email_address_invalid` for the
  `.invalid` QA mailbox. Build 43 adds a tested restart guard but no real
  mailbox was available, so
  recovery-link delivery, callback completion and real password change remain
  **UNVERIFIED** on a physical phone.

## Evidence and actual attempts

Sanitized native stage exports are retained under
`docs/evidence/build40-43-20261028/`. Each file is an actual captured subset;
timestamps and IDs are preserved. They contain no message text, precise
location, password or token. Earlier buffer loss is disclosed above.

One physical Build 40 after-stored outage attempt exposed the ACK-return gap.
Build 41 added durable receipt replay; Build 42 tightened its handshake gate;
Build 43 separately fixed recovery restart persistence. One controlled Build 43
physical retest passed after approved execution became available. There were
no further source changes or fix cycles after this retest.
Early focused invocation without QA updater defines failed its compile-time
guard; rerunning with the approved public-qa-config values passed. These are
automated/build attempts, not fabricated physical passes.

## Other physical smoke observations

Build 40 Samsung online Home shows Internet and Nearby separately; Map loads
network style/tiles and peer marker; List shows two real peers and labels DEMO
separately. Stale last-known location warning remains visible. These are UI
smokes, not proof of location accuracy, full offline tiles or all map scenarios.
Guest chat history remained visible after account login/logout. No new SOS was
sent; historical inactive SOS retry/ACK events may exist in diagnostics.
