# RELIO demonstration checklist

Use a QA build and two authorized Android phones for transport demonstrations.
Record device models, Android versions, permissions, build numbers, and
observed failures. Do not mark radio-dependent steps complete without actually
performing them on the devices.

1. Launch RELIO and show the installed flavor/version.
2. Show Internet, Nearby, and Cloud as separate states.
3. On both phones, open Nearby and discover the other phone.
4. Request a connection on one phone; explicitly accept on the other.
5. Confirm the trusted identity flow, then send one direct text each way.
6. Open persistent Chat history; if authorized, send an image and supported
   video and inspect local transfer state.
7. Demonstrate fake-coordinate persistence only in automated tests; use Send
   Location on device only with the owner's explicit consent.
8. Confirm SOS activation and ending remain visible locally; do not represent
   simulated SOS delivery as a real peer receipt.
9. Show Rescue mode and the SOS > Rescue > Normal precedence.
10. Disable Internet and show that local history remains available. Nearby
    radio delivery still requires the real two-phone test.
11. If Cloud is configured and the account/test environment is authorized,
    demonstrate queue sync after connectivity returns; otherwise show the
    truthful local-only state.

Automated-only evidence: unit/widget tests and `MockNearbyTransport` output.
Physical evidence: observed two-phone steps, recorded separately in the
manual test record. Never present one as the other.
