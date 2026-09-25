# RELIO Bug Log

## RELIO-THEME-001 — Theme selection did not apply or persist

- **Environment:** Real Android device.
- **Observed:** Selecting Light, Dark, or System did not reliably change the
  application theme, and the selected mode was not restored after restart.
- **Root cause:** `RelioApp` read `RelioThemeController.mode` during its own
  build but did not listen to the controller. `RelioThemeScope` rebuilt
  dependent descendant screens only, leaving `MaterialApp.router` on its
  initial `themeMode`. Startup loading was also fire-and-forget, making
  restoration timing-dependent.
- **Fix:** The active v0.5 app now uses one application-lifetime controller,
  listens at the root, loads the preference before production startup, stores
  stable `light`/`dark`/`system` values in SharedPreferences, and derives
  Android system-bar styling from the active Material theme.
- **Automated:** `test/theme_controller_test.dart` plus the Theme Settings
  interaction test in `test/widget_test.dart`.
- **Manual verification:** PENDING — requires the user's real Android device.
