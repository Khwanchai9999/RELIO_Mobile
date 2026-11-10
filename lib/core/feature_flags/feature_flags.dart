import 'package:flutter/foundation.dart';

import '../../app/environment.dart';
import '../repositories/local_repositories.dart';

// กำหนด flags สำหรับการนำเสนอ UI โดยไม่เปลี่ยน transport หรือการเก็บ metadata
// ค่าเริ่มต้นมาจาก build; QA override ถูกจัดเก็บแยกใน app_settings
enum RelioFeatureFlag { nearbyMapUi, peerBatteryUi, routePreview }

abstract final class FeatureFlagDefaults {
  static const nearbyMapUi = bool.fromEnvironment(
    'RELIO_FEATURE_NEARBY_MAP_UI',
    defaultValue: true,
  );
  static const peerBatteryUi = bool.fromEnvironment(
    'RELIO_FEATURE_PEER_BATTERY_UI',
    defaultValue: true,
  );
  static const routePreview = bool.fromEnvironment(
    'RELIO_FEATURE_ROUTE_PREVIEW',
    defaultValue: true,
  );

  static bool forFlag(RelioFeatureFlag flag) => switch (flag) {
    RelioFeatureFlag.nearbyMapUi => nearbyMapUi,
    RelioFeatureFlag.peerBatteryUi => peerBatteryUi,
    RelioFeatureFlag.routePreview => routePreview,
  };
}

extension RelioFeatureFlagInfo on RelioFeatureFlag {
  String get storageKey => switch (this) {
    RelioFeatureFlag.nearbyMapUi => 'feature.nearbyMapUi.override',
    RelioFeatureFlag.peerBatteryUi => 'feature.peerBatteryUi.override',
    RelioFeatureFlag.routePreview => 'feature.routePreview.override',
  };

  String get label => switch (this) {
    RelioFeatureFlag.nearbyMapUi => 'Nearby Map UI',
    RelioFeatureFlag.peerBatteryUi => 'Peer Battery UI',
    RelioFeatureFlag.routePreview => 'ดูเส้นทาง',
  };
}

class FeatureFlagRepository {
  FeatureFlagRepository(this._settings);

  final RelioSettingsRepository _settings;

  Future<bool?> readOverride(RelioFeatureFlag flag) =>
      _settings.getNullableBool(flag.storageKey);

  Future<void> writeOverride(RelioFeatureFlag flag, bool? value) async {
    if (value == null) {
      await _settings.remove(flag.storageKey);
    } else {
      await _settings.setBool(flag.storageKey, value);
    }
  }
}

class FeatureFlagController extends ChangeNotifier {
  FeatureFlagController({
    required this.repository,
    required this.allowLocalOverrides,
    bool Function(RelioFeatureFlag)? buildDefault,
  }) : _buildDefault = buildDefault ?? FeatureFlagDefaults.forFlag;

  final FeatureFlagRepository repository;
  final bool allowLocalOverrides;
  final bool Function(RelioFeatureFlag) _buildDefault;
  final Map<RelioFeatureFlag, bool?> _overrides = {};
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _restore();

  Future<void> _restore() async {
    if (allowLocalOverrides) {
      try {
        for (final flag in RelioFeatureFlag.values) {
          _overrides[flag] = await repository.readOverride(flag);
        }
      } on Object {
        // Storage ผิดพลาดให้ใช้ build defaults เพื่อให้แอปยังเปิดได้
        _overrides.clear();
      }
    }
    notifyListeners();
  }

  bool buildDefault(RelioFeatureFlag flag) => _buildDefault(flag);

  bool configuredValue(RelioFeatureFlag flag) => allowLocalOverrides
      ? (_overrides[flag] ?? _buildDefault(flag))
      : _buildDefault(flag);

  bool isEnabled(RelioFeatureFlag flag) {
    final value = configuredValue(flag);
    if (flag == RelioFeatureFlag.routePreview) {
      return value && isEnabled(RelioFeatureFlag.nearbyMapUi);
    }
    return value;
  }

  bool? localOverride(RelioFeatureFlag flag) =>
      allowLocalOverrides ? _overrides[flag] : null;

  Future<void> setOverride(RelioFeatureFlag flag, bool value) async {
    if (!allowLocalOverrides) return;
    try {
      await repository.writeOverride(flag, value);
      _overrides[flag] = value;
    } on Object {
      // ไม่ใช้ override ที่บันทึกไม่ได้; คืนพฤติกรรมตามค่า build
      _overrides[flag] = null;
    }
    notifyListeners();
  }

  Future<void> resetOverrides() async {
    if (!allowLocalOverrides) return;
    try {
      for (final flag in RelioFeatureFlag.values) {
        await repository.writeOverride(flag, null);
      }
      _overrides.clear();
    } on Object {
      _overrides.clear();
    }
    notifyListeners();
  }
}

FeatureFlagController createFeatureFlagController(
  RelioSettingsRepository settings,
) => FeatureFlagController(
  repository: FeatureFlagRepository(settings),
  allowLocalOverrides: RelioBuildInfo.isTest,
);
