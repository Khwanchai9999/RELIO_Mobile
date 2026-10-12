import 'package:flutter/foundation.dart';

import '../../app/environment.dart';

/// QA-only control for suppressing RELIO-managed Internet work.
class QaInternetSimulator extends ChangeNotifier {
  QaInternetSimulator()
    : this._(
        RelioBuildInfo.isTest,
        false,
        bootOffline: RelioBuildInfo.isTest && RelioBuildInfo.qaBootOffline,
      );

  @visibleForTesting
  factory QaInternetSimulator.forTesting({
    bool qaBuild = true,
    bool bootOffline = false,
  }) => QaInternetSimulator._(qaBuild, true, bootOffline: bootOffline);

  QaInternetSimulator._(
    this._qaBuild,
    this._testOverride, {
    bool bootOffline = false,
  }) : _simulatedOffline = _qaBuild && bootOffline,
       bootOfflineOverride = _qaBuild && bootOffline;

  final bool _qaBuild;
  final bool _testOverride;
  bool _simulatedOffline;
  final bool bootOfflineOverride;

  bool get available => _testOverride ? _qaBuild : RelioBuildInfo.isTest;
  bool get simulatedOffline => available && _simulatedOffline;
  bool get internetAvailable => !simulatedOffline;

  void restore(bool value) {
    if (!available || _simulatedOffline == value) return;
    _simulatedOffline = value;
    notifyListeners();
  }

  void setSimulatedOffline(bool value) {
    if (!available || _simulatedOffline == value) return;
    _simulatedOffline = value;
    notifyListeners();
  }
}
