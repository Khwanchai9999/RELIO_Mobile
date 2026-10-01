# RELIO v0.8 Manual Device Tests

## DEFERRED MANUAL VERIFICATION — NOT PERFORMED

No two physical Android phones, Bluetooth radios, Wi-Fi radios, real Android
runtime permission, file-transfer, or GPS flows were used for this milestone.
Automated tests, fake location, and `MockNearbyTransport` cover the deterministic
development path. Do not
interpret this checklist as evidence that device-to-device Nearby communication
has been verified.

## A. Single-phone verification

Run later on at least one real Android phone:

1. Install the debug APK and launch RELIO.
2. Check the Nearby permission explanation and runtime permission prompts.
3. Enter offline mode and verify Home, Nearby, Chat, SOS, Profile, and Settings.
4. Check light/dark/system theme behavior, keyboard behavior, and supported
   rotation behavior.
5. Send a local chat message, force-stop/relaunch the app, and confirm the
   conversation and delivery state remain in local storage.
6. Verify Android Back behavior, status-bar contrast, and navigation-bar
   contrast.

### v0.5.1 Theme Hotfix Verification

Manual real-device verification remains pending. Install the v0.5.1 debug APK
and check:

1. Select Theme → Light, Dark, and System; confirm each applies immediately.
2. Navigate through Home, Nearby, Chat, SOS, and Profile after each change.
3. Close and reopen the app; confirm the selected mode remains selected.
4. Change Android system brightness while RELIO is set to System; confirm the
   app follows it.
5. Open the Chat keyboard, SOS confirmation, and attachment sheet in both
   Light and Dark modes.
6. Confirm Android status-bar and navigation/gesture-area icons remain visible.

## B. Two-phone Nearby verification

Prepare Phone A and Phone B with RELIO installed. Turn Internet and mobile data
off while leaving the required Wi-Fi/Bluetooth radios on.

1. Start advertising and discovery on both phones; confirm repeated starts do
   not create duplicate sessions.
2. Confirm A can discover B and B can discover A, then connect both directions.
3. Confirm the hello handshake maps each changing transport endpoint to the
   stable RELIO device ID and display name.
4. Connect the phones and send `Hello RELIO` from A. Confirm B receives and
   persists it, sends an ACK, and A changes from Nearby sent to Delivered.
5. Send B → A, restart both apps, and confirm histories and delivery states
   remain in local SQLite.
6. Activate SOS on A. Confirm B sees A as red SOS, can open Chat, receives the
   SOS message/location only when a real location exists, and sees the state
   clear after A deactivates it.
7. Enable Rescue on B. Confirm A sees blue Rescue, then confirm disabling it
   propagates back to Normal. Verify SOS presentation overrides Rescue.
8. Record Android versions, device models, permission results, endpoint/device
   mappings, and diagnostics logs.

## C. Range and failure verification

Later test connection loss, moving devices out of range, reconnection to the
same logical device, Bluetooth off, Wi-Fi off, denied permissions, and app
background/foreground transitions. Confirm failures are visible, pending chat
messages remain stored, and explicit retry works after reconnection.

## D. Android-version verification

Test at least two Android versions/devices if available. Do not claim broad
Android compatibility until permission prompts, discovery, connection, and
restart persistence have been checked on those versions.

## E. OEM verification (optional)

If available, repeat the critical flow on Samsung, Xiaomi, OPPO/realme, and
Pixel/stock Android devices. Record battery-optimization, background, and
permission differences instead of assuming identical behavior.

## F. Media transfer — DEFERRED

With two real Android phones and Internet/mobile data disabled:

1. Select a JPEG/PNG/WEBP image on A, send it to B, observe progress, confirm
   B stores and shows the image, and confirm A reaches Delivered only after the
   receiver acknowledgement.
2. Repeat in both directions with a supported MP4/video file.
3. Try a file over the configured size limit and confirm a clear local error.
4. Disconnect at the beginning, middle, and end of a transfer. Confirm the
   attachment is not shown as completed and retry does not duplicate the chat
   message.
5. Restart after completed and failed transfers. Confirm completed local files
   remain visible and failed transfers remain retryable.

## G. Location and SOS — DEFERRED

1. Send Location from A to B and confirm the offline coordinate card, capture
   time, and optional accuracy.
2. Deny location permission, deny it permanently, disable the location service,
   and force a timeout. Confirm the feature explains the failure without a
   crash.
3. Activate SOS with location available and confirm coordinates plus capture
   metadata reach B.
4. Activate SOS with location unavailable and confirm SOS still activates while
   the UI says `ไม่พบพิกัดล่าสุด`.
5. If a last-known location is used, confirm it is identified as latest rather
   than current and no live tracking is implied.

## H. SyncEngine ownership verification — DEFERRED

Use a disposable test Supabase project only after credentials are explicitly
configured. These checks have not been performed:

1. Create a message while signed in as Account A, sign out, sign in as B, and
   confirm the queue remains owned by A and is not uploaded as B.
2. Create Guest Mode history, sign in, and confirm it stays local until the
   user explicitly chooses `นำข้อมูลออฟไลน์นี้ไปซิงก์กับบัญชีนี้`.
3. Turn Cloud offline, create authenticated data, restore connectivity, and
   confirm startup/resume/manual Sync Now retry without deleting SQLite data.
4. Queue an attachment and confirm its parent ownership and private storage
   path cannot cross accounts.

These checks are **DEFERRED — NOT YET PERFORMED**.

## I. v0.7 live adapter verification — DEFERRED

After a disposable Supabase project is explicitly configured, verify the
following with two non-production test accounts:

1. Confirm repeated adapter initialization restores one session without
   duplicate auth listeners.
2. Confirm malformed URLs, service-role keys, and secret-like keys stay in
   `notConfigured` and never make a request.
3. Confirm owner conversations can write their own messages, while another
   account cannot update or read them unless the documented membership policy
   permits it.
4. Confirm Storage rejects another user's path, accepts only `relio-media`,
   and preserves the private bucket boundary.
5. Confirm auth, RLS, Storage, timeout, and server failures surface stable
   safe diagnostics without payload text or exact SOS coordinates.

These checks are **DEFERRED — NOT YET PERFORMED**.

## J. Supabase live verification — DEFERRED

Only after a disposable Supabase project is configured with dart-defines:

1. Register and sign in with email/password; confirm session restoration and
   auth-state changes.
2. Sign out and confirm the cloud session is removed while local conversations,
   SOS events, settings, and RELIO-managed media remain intact.
3. Verify profile/device/conversation/message/SOS metadata follows RLS rules
   for two separate users; confirm one user cannot read another user's data.
4. Upload and download a supported image and video through the private
   `relio-media` bucket and confirm the safe user/message/attachment path.
5. Disable Internet during local chat/SOS/Nearby use and confirm the UI stays
   local-first with truthful `notConfigured`/offline/cloud-error state.
6. Confirm `/developer/cloud` never displays the full URL key or any secret.

These checks are **DEFERRED — NOT YET PERFORMED**. They require live project
credentials and network access and are not required to use the automated/mock
path. Physical radio, GPS, and OEM checks remain deferred as well.

## K. Historical Firebase Build 11 distribution — DEFERRED

Before a TEST upload, a developer should:

1. Run the automated quality gate and build `RELIO Test`.
2. Upload only the approved Build 11 artifact through Firebase App Distribution.
3. Open the Firebase tester invitation on the Android phone, sign in with the
   approved Google account, accept the invitation, and install Build 11.
4. Allow Android's installation confirmation if requested, open RELIO Test, and
   verify the displayed package/version and a basic local-data smoke test.
5. Build 11 remains historical/internal; the public Build 12 flow is documented
   in section K1 below.
6. Confirm Android updates the same TEST app without clearing its local SQLite
   data, then verify the displayed version/build.

7. The Firebase tester update dialog is fallback-only and is not the normal
   public QA path.
8. Return to background and foreground; confirm automatic checks are throttled
   and do not show repeated dialogs during the cooldown.
9. After the update, verify messages, SOS data, attachments, sync queue, relay
   packets, forwarding history, and settings remain available locally.

These distribution steps are not claimed as manually completed by Codex.

## K1. Public Build 12 → Build 16 in-app OTA — PENDING PHYSICAL TEST

The user confirmed Build 15 on Realme reports “up to date” against public Build
13. The latest ADB check found no connected devices, so Huawei's installed
artifact has not been independently verified; the user intends to preserve
Huawei Build 12 as the OTA baseline. Build 16 is publicly available and its
live manifest/page, APK hash, package, version, and signer were verified. No
phone was modified. The user will manually open RELIO on Huawei Build 12 and
check for an update from Settings. Automated verification covers the live
manifest parser, hash, package, version, signer, permission, and PROD isolation,
but cannot establish installed phone state or OEM installer behavior.

## L. v0.8 Relay A→B→C — DEFERRED

No physical relay test was performed for v0.8. With three Android phones and
Internet/mobile data disabled:

1. Confirm A, B, and C complete the hello handshake and advertise `relay-v1`.
2. Queue a text payload from A for C, with only A↔B and B↔C available.
3. Confirm B shows a stored hop state but does not insert the private text into
   B's normal chat history.
4. Confirm C materializes the text once, preserving the original message ID
   and origin device, then returns a destination acknowledgement.
5. Repeat with SOS and location payloads; verify SOS ID, capture time, and
   accuracy are preserved and no UI describes the location as current.
6. Disconnect C, restart B, reconnect C, and confirm persisted packet and
   forward history retry without duplication.
7. Confirm expired/over-hop packets are not forwarded and attachments are not
   relayed.

These checks are **DEFERRED — NOT YET PERFORMED**. `MockNearbyTransport` and
automated tests cover the deterministic path.

## M. Historical Build 17 two-device test notes — INACTIVE

Build 17's device-test instructions are historical and must not be used as a
current install recipe. Build 22 (`0.9.0+22`) is the current QA candidate; its
software validation is covered in the status report, but no physical-device
Nearby test has been performed for it. Do not install or update a phone unless
the user explicitly authorizes the physical test and the exact release
artifact, device serial, package, version, and signing identity are verified.
Never uninstall the app or clear its data.

The acceptance steps below remain applicable only after that authorization.

1. Record phone models, Android API levels, tested package/version, and
   permission choices. Grant only the foreground Nearby permissions the app
   explains; do not grant location unless explicitly testing Send Location or
   SOS location capture.
2. Turn off mobile data and Internet access on both phones while leaving the
   radios needed by Android Nearby Connections enabled. Confirm Home shows
   Internet separately from Wi-Fi, Bluetooth, Nearby, and Cloud; no UI should
   claim Internet merely because Wi-Fi is enabled.
3. In Nearby, confirm prototype entries are labeled `DEMO` and listed separately
   from discovered real phones. Start discovery on both devices and verify
   actual device names/statuses appear only after transport discovery and the
   hello handshake; no estimated distance or signal strength is shown as fact.
4. Connect A and B, exchange text in both directions, and verify each message
   is locally persisted before send, becomes Nearby-sent on transport success,
   and becomes delivered only after ACK. Force-stop/reopen without clearing
   data and verify the local conversation remains.
5. With A disconnected, send a message to B and verify it remains pending. Put
   the phones back in range, complete the hello handshake, and verify the
   pending message is sent to that identified peer only.
6. Activate SOS on A and verify B sees A's live SOS state and can open the
   direct conversation. Clear SOS on A and verify B returns the peer to Normal.
   Enable Rescue and verify Rescue propagates to Normal when disabled, while
   SOS remains higher priority than Rescue.

## N. Android Nearby compatibility matrix — DEFERRED

Build 21 introduced SDK-driven permission selection and runtime readiness;
Build 22 retains it. Test real phones before describing OEM compatibility as
physically verified. Do not clear app data or uninstall during OTA tests.

| Android API | Expected Nearby permissions | Location toggle | Result to verify |
| --- | --- | --- | --- |
| 24–28 | `ACCESS_COARSE_LOCATION` | Required for legacy discovery | Discovery starts after permission and Location are ready |
| 29–30 | `ACCESS_FINE_LOCATION` | Required | Location off shows a blocker; on starts the session |
| 31 | Fine Location plus Bluetooth Scan/Connect/Advertise | Required by this tier | Grant prompt and discovery on/off behavior |
| 32 | Fine Location plus Bluetooth Scan/Connect/Advertise | Required by compatibility policy | Validate Android 12L independently |
| 33–36 | Bluetooth Scan/Connect/Advertise and Nearby Wi-Fi | Not required for Nearby | GPS off does not block; each missing permission does |
| 37+ | Above plus `ACCESS_LOCAL_NETWORK` when target is 37+ | API/feature dependent | Current target-36 build reports upgrade path when required |

For each tested SDK, record Bluetooth/Wi-Fi capability and state, Google Play
Services availability, permission decisions, advertising/discovery, peer found,
connect, automatic hello, offline chat/ACK, SOS, and Rescue. Also test readiness
false→true, true→false, resume, connection loss, and hello timeout/retry. Keep
the app foregrounded; background discovery is not promised.

`scripts/start-two-device-nearby-test.ps1` discovers authorized ADB devices,
prints their runtime facts, and captures filtered logs without clearing existing
logcat. One connected device is reported and left untouched until another
device is connected.
7. Toggle Bluetooth/Wi-Fi and deny then grant Nearby permissions. Confirm the
   UI reflects the actual state and gives a clear recovery action without
   claiming background discovery or Internet connectivity.
8. Record pass/fail per step, device models/OS versions, and non-sensitive
   diagnostics. Do not include message contents, exact coordinates, tokens, or
   account data in logs or reports.

All items in this section remain **DEFERRED — NOT YET PERFORMED** until a
human-run two-phone test is completed.
