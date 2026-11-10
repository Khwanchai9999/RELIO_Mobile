import 'package:flutter/foundation.dart';

import '../../app/environment.dart';
import '../repositories/local_repositories.dart';

class InternalExperienceController extends ChangeNotifier {
  InternalExperienceController(this._settings, {this.onDemoEnabled});

  static const developerModeKey = 'developer_mode_enabled';
  static const demoModeKey = 'developer_demo_enabled';

  final RelioSettingsRepository _settings;
  final Future<void> Function()? onDemoEnabled;
  bool _developerModeEnabled = false;
  bool _demoModeEnabled = false;
  bool _initialized = false;
  int _demoRequestGeneration = 0;
  Future<void> _settingsWrite = Future<void>.value();

  bool get isAuthorizedEnvironment =>
      RelioBuildInfo.developerDiagnosticsEnabled;
  bool get developerModeEnabled =>
      isAuthorizedEnvironment && _developerModeEnabled;
  bool get demoEnabled => developerModeEnabled && _demoModeEnabled;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    _developerModeEnabled = await _settings.getBool(
      developerModeKey,
      defaultValue: false,
    );
    _demoModeEnabled = await _settings.getBool(
      demoModeKey,
      defaultValue: false,
    );
    if (!developerModeEnabled && _demoModeEnabled) {
      _demoModeEnabled = false;
      await _settings.setBool(demoModeKey, false);
    }
    _initialized = true;
    notifyListeners();
    if (demoEnabled) {
      try {
        await onDemoEnabled?.call();
      } on Object {
        _demoModeEnabled = false;
        await _settings.setBool(demoModeKey, false);
        notifyListeners();
        rethrow;
      }
    }
  }

  Future<void> setDeveloperMode(bool enabled) async {
    await initialize();
    if (!isAuthorizedEnvironment && enabled) return;
    _developerModeEnabled = enabled;
    if (!enabled) {
      // ทำให้ seed ของ fixture ที่อาจยังรอ SQLite อยู่ใช้ผลเก่าต่อไม่ได้      // Invalidate a fixture seed that may still be awaiting SQLite.
      _demoRequestGeneration++;
      _demoModeEnabled = false;
    }
    notifyListeners();
    await _serializeSettings(() async {
      await _settings.setBool(developerModeKey, enabled);
      if (!enabled) await _settings.setBool(demoModeKey, false);
    });
  }

  Future<void> setDemoEnabled(bool enabled) async {
    await initialize();
    if (enabled && !developerModeEnabled) return;
    final generation = ++_demoRequestGeneration;
    _demoModeEnabled = enabled;
    notifyListeners();
    await _serializeSettings(() async {
      if (generation != _demoRequestGeneration) return;
      final effectiveValue = enabled && developerModeEnabled;
      await _settings.setBool(demoModeKey, effectiveValue);
      if (effectiveValue && generation == _demoRequestGeneration) {
        try {
          await onDemoEnabled?.call();
        } on Object {
          if (generation == _demoRequestGeneration) {
            _demoModeEnabled = false;
            await _settings.setBool(demoModeKey, false);
            notifyListeners();
          }
          rethrow;
        }
      }
    });
  }

  Future<void> _serializeSettings(Future<void> Function() operation) {
    final next = _settingsWrite
        .catchError((Object _) {})
        .then((_) => operation());
    _settingsWrite = next;
    return next;
  }
}
