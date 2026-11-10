import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

class BatterySnapshot {
  const BatterySnapshot({this.level, this.isCharging, this.updatedAt});

  final int? level;
  final bool? isCharging;
  final DateTime? updatedAt;

  bool get isValid =>
      (level == null || (level! >= 0 && level! <= 100)) &&
      (level != null || isCharging != null);

  Map<String, Object?> toPacketFields() => {
    if (level != null) 'batteryLevel': level,
    if (isCharging != null) 'isCharging': isCharging,
    if (level != null || isCharging != null)
      'batteryUpdatedAt': (updatedAt ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
  };
}

abstract interface class BatteryInfoService {
  Future<BatterySnapshot?> readSnapshot();
  Stream<void> get stateChanges;
}

class BatteryPlusInfoService implements BatteryInfoService {
  BatteryPlusInfoService({Battery? battery}) : _battery = battery ?? Battery();

  final Battery _battery;

  @override
  Stream<void> get stateChanges => _battery.onBatteryStateChanged.map((_) {});

  @override
  Future<BatterySnapshot?> readSnapshot() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      if (level < 0 || level > 100) return null;
      return BatterySnapshot(
        level: level,
        isCharging: switch (state) {
          BatteryState.charging || BatteryState.full => true,
          BatteryState.discharging ||
          BatteryState.connectedNotCharging => false,
          BatteryState.unknown => null,
        },
        updatedAt: DateTime.now().toUtc(),
      );
    } on Object {
      return null;
    }
  }
}

class FakeBatteryInfoService implements BatteryInfoService {
  FakeBatteryInfoService(this.snapshot);

  BatterySnapshot? snapshot;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get stateChanges => _changes.stream;

  @override
  Future<BatterySnapshot?> readSnapshot() async => snapshot;

  void emit(BatterySnapshot? next) {
    snapshot = next;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

class BatteryPublishPolicy {
  const BatteryPublishPolicy({
    this.meaningfulLevelDelta = 5,
    this.refreshInterval = defaultRefreshInterval,
  });

  static const defaultRefreshInterval = Duration(minutes: 10);
  static const displayFreshnessGrace = Duration(minutes: 2);

  final int meaningfulLevelDelta;
  final Duration refreshInterval;

  // ให้ UI แสดง battery reading ต่อได้ตลอดรอบ refresh พร้อม grace สั้น ๆ
  Duration get maxDisplayAge => refreshInterval + displayFreshnessGrace;

  bool shouldPublish({
    required BatterySnapshot? previous,
    required BatterySnapshot current,
    required DateTime now,
    bool force = false,
  }) {
    if (!current.isValid) return false;
    if (force || previous == null) return true;
    if (previous.isCharging != current.isCharging) return true;
    final previousLevel = previous.level;
    final currentLevel = current.level;
    if (previousLevel != null &&
        currentLevel != null &&
        (currentLevel - previousLevel).abs() >= meaningfulLevelDelta) {
      return true;
    }
    final lastSent = previous.updatedAt;
    return lastSent != null && now.difference(lastSent) >= refreshInterval;
  }
}
