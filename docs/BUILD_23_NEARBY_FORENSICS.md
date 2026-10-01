# Build 22 Nearby failure → Build 23 fix

## Confirmed device evidence

The read-only ADB inspection used the two connected QA installs and did not
change device state.

### realme RMX3661 — Android 15 / API 35

- QA package was `com.relio.relio_mobile.test`, version `0.9.0`, versionCode
  `22`. The supplied device permission snapshot showed Bluetooth Scan/Connect/
  Advertise, Nearby Wi-Fi, and Location granted; Bluetooth and Wi-Fi were on.
- Google Play Services package was installed and enabled, version
  `26.36.33 (260400-986028547)`.
- Nearby Connections logs explicitly reported
  `8033: MISSING_PERMISSION_CHANGE_WIFI_STATE`. Both startAdvertising and
  startDiscovery aborted after the native permission check; the Dart adapter
  exposed only the generic plugin code `Failure`.
- The Build 22 merged QA manifest declared `CHANGE_WIFI_STATE` with
  `maxSdkVersion="31"`. Therefore Android 15 did not include that permission
  in this app's requested manifest permissions. This was an app-manifest
  blocker, not a missing runtime grant, Location setting, or radio toggle.

### Huawei STK-L22 — Android 10 / API 29

- The captured log window showed `advertising started` and `discovery started`.
  Google Nearby logged BLE L2CAP and USB-medium startup warnings, but then
  successfully began BLE legacy advertising, Wi-Fi LAN advertising, BLE
  scanning, and Wi-Fi LAN discovery. Those medium fallback warnings are not a
  failed `startAdvertising`/`startDiscovery` result.
- Google Play Services was installed/enabled. The updated package reported
  `26.34.65 (100400-981476050)`; the system image also exposed its older base
  package version `20.15.16 (120400-309763488)`. Nearby Connections itself
  completed the captured start calls.
- No matching native Nearby status failure for Huawei appears in this captured
  window. The device was unable to find a working realme advertisement while
  the other endpoint was failing its start permission check. A separate Huawei
  start failure was not established by this evidence.

## Source findings and changes

- Build 22 allowed an advertising exception to be caught and then continued to
  discovery, obscuring which start failed.
- Connectivity startup coalesced simultaneous calls but marked the coordinator
  dirty during an in-flight operation and reran it immediately. A foreground
  health timer also retried every 10 seconds without backoff.
- The real-device permission card relied on a cached permission snapshot and
  could offer a stale runtime prompt. `CHANGE_WIFI_STATE` is a normal manifest
  permission and cannot be repaired by that runtime prompt.
- Build 23 declares `CHANGE_WIFI_STATE` without an API cap, reports it
  separately from runtime grants, uses live readiness in the card, and shows an
  app-update blocker instead of a permission button if the manifest is wrong.
- Advertising and discovery use the same canonical service ID and
  `P2P_CLUSTER`. PlatformException code/message/details and recoverable Nearby
  status are retained in developer diagnostics. `Future<bool> == false` is
  distinct from a thrown platform error.
- Session starts are single-flight. Discovery is skipped when advertising
  fails. Already-advertising/discovering statuses reconcile local state;
  out-of-order recovery stops only advertising/discovery and does not drop
  connected endpoints. Retry is exponential (10 seconds initially, capped at
  5 minutes) and resets after success or a changed readiness state.
- Permission selection stays SDK-specific: coarse Location through API 28,
  fine Location for Nearby on API 29–31, Bluetooth permissions on API 31+,
  and Nearby Wi-Fi in the manifest from API 32 with runtime request from API
  33. Nearby does not require the Location toggle on API 32+; SOS/Send Location
  stays separate.

The API-tier model follows [Google Nearby Connections' current Android
permission guidance](https://developers.google.com/nearby/connections/android/get-started?hl=en).
The no-cap `CHANGE_WIFI_STATE` adjustment is specifically supported by the
captured API 35 Nearby status 8033 and the [Android reference confirming this
is a normal permission](https://developer.android.com/reference/android/Manifest.permission#CHANGE_WIFI_STATE).

## Physical boundary

The Build 23 artifact is for the user's next physical test only. This workflow
does not install it, alter phone settings, toggle radios, change permissions, or
clear app data. Huawei/realme Nearby discovery and connection must be retested
after the user installs Build 23.
