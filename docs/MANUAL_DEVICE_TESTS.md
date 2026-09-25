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

## K. TEST DISTRIBUTION AND WIRELESS UPDATE GATE — DEFERRED

Before a TEST upload, a developer should:

1. Run the automated quality gate and build `RELIO Test`.
2. Install the TEST APK through USB once and complete a smoke test.
3. Upload only the approved artifact through Firebase App Distribution.
4. Install it from the Firebase tester experience and verify the displayed
   version/build.
5. Distribute the next TEST build and confirm Android updates the same TEST app
   without clearing its local SQLite data.

6. Open Settings in RELIO Test and press `ตรวจสอบอัปเดต`; confirm the official
   Firebase tester sign-in/update dialog appears only after a real release is
   available and the tester explicitly confirms installation.
7. Return to background and foreground; confirm automatic checks are throttled
   and do not show repeated dialogs during the cooldown.
8. After the update, verify messages, SOS data, attachments, sync queue, relay
   packets, forwarding history, and settings remain available locally.

These distribution steps are not claimed as manually completed by Codex.

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
