import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/environment.dart';
import '../../core/diagnostics/diagnostics_log_service.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

class SystemDiagnosticsScreen extends StatefulWidget {
  const SystemDiagnosticsScreen({super.key});

  @override
  State<SystemDiagnosticsScreen> createState() =>
      _SystemDiagnosticsScreenState();
}

class _SystemDiagnosticsScreenState extends State<SystemDiagnosticsScreen> {
  late RelioDependencies _dependencies;
  Map<String, Object?> _device = const {};
  List<dynamic> _trustedPeers = const [];
  bool _busy = false;
  bool _listenerAttached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = RelioDependencyScope.of(context);
    if (!_listenerAttached) {
      _dependencies = next;
      _dependencies.nearbyService.addListener(_refresh);
      _listenerAttached = true;
      _load();
    }
  }

  @override
  void dispose() {
    _dependencies.nearbyService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final values = await Future.wait<Object?>([
      _dependencies.diagnostics.deviceInfo(),
      _dependencies.nearbyService.nearbyDevices.listDevices(),
    ]);
    if (!mounted) return;
    setState(() {
      _device = Map<String, Object?>.from(values[0]! as Map);
      _trustedPeers = values[1]! as List<dynamic>;
    });
  }

  Future<Map<String, Object?>> _deviceState() async {
    final runtime = await _dependencies.connectivityStatus
        .readRuntimeSnapshot();
    final service = _dependencies.nearbyService;
    final active = service.peerStates.entries
        .where(
          (entry) =>
              entry.value == NearbyConnectionState.connecting ||
              entry.value == NearbyConnectionState.incomingRequest ||
              entry.value == NearbyConnectionState.connected,
        )
        .map(
          (entry) => {
            'peerAlias': DiagnosticsLogService.peerAlias(entry.key),
            'state': entry.value.name,
            'failure': service.peerErrors[entry.key],
          },
        )
        .toList(growable: false);
    final lastFailure = service.peerErrors.isNotEmpty
        ? service.peerErrors.values.last
        : service.lastErrorCode;
    final nativeFailure = service.lastNativeConnectionFailure;
    final transportSnapshot = service.nativeTransportSnapshot;
    return {
      'bluetoothEnabled': runtime.bluetoothEnabled,
      'wifiEnabled': runtime.wifiEnabled,
      'locationEnabled': runtime.locationEnabled,
      'permissions': runtime.permissions,
      'nearbyReady': runtime.nearbyReadiness.ready,
      'nearbyReadiness': runtime.nearbyReadiness.summary,
      'discoveredPeers': service.discoveredPeers.length,
      'connectedPeers': service.connectedPeerCount,
      'pendingIncomingRequests': service.pendingConnectionRequests.length,
      'applicationState': service.applicationState.name,
      'retryAttempt': _dependencies.nearbyRetryAttempt,
      'peers': active,
      'currentPeerTrust': _currentPeerTrustState(),
      'trustedPeerCount': _trustedPeers
          .where((peer) => peer.isTrusted == true)
          .length,
      'lastFailure': lastFailure,
      'lastNearbyNativeError': service.lastDiagnostic,
      'activeNegotiation': service.hasActiveConnectionAttempts,
      'nativeStatusCode': nativeFailure?.rawStatusCode,
      'nativeStatusName': nativeFailure?.rawStatusName,
      'nativeStatusMessage': nativeFailure?.rawStatusMessage,
      'nativeOperation': nativeFailure?.operation,
      'nativeRole': nativeFailure?.role,
      'nativeElapsedMs': nativeFailure?.elapsedMs,
      'nativeStrategy': nativeFailure?.strategy,
      'googlePlayServicesVersionName':
          transportSnapshot['googlePlayServicesVersionName'],
      'googlePlayServicesVersionCode':
          transportSnapshot['googlePlayServicesVersionCode'],
      'nearbyLibraryVersion': transportSnapshot['nearbyLibraryVersion'],
      'identityHandshake':
          service.peerErrors.values.any((value) => value.contains('identity'))
          ? 'failed_or_rejected'
          : service.connectedPeers.isEmpty
          ? 'not_active'
          : 'active',
    };
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final state = await _deviceState();
      final summary = [
        'RELIO ${RelioBuildInfo.versionName}+${RelioBuildInfo.buildNumber}',
        'Flavor: ${RelioBuildInfo.environmentLabel}',
        'Device: ${_device['manufacturer'] ?? 'unknown'} ${_device['model'] ?? 'unknown'}',
        'Android/API: ${_device['androidVersion'] ?? 'unknown'} / ${_device['apiLevel'] ?? 'unknown'}',
        'Nearby readiness: ${state['nearbyReadiness']}',
        'Bluetooth/Wi-Fi/Location: ${state['bluetoothEnabled']} / ${state['wifiEnabled']} / ${state['locationEnabled']}',
        'Connection: ${state['applicationState']}; discovered ${state['discoveredPeers']}; connected ${state['connectedPeers']}; incoming ${state['pendingIncomingRequests']}',
        'Active negotiation: ${state['activeNegotiation']}',
        'Google Play Services: ${state['googlePlayServicesVersionName'] ?? 'unknown'} (${state['googlePlayServicesVersionCode'] ?? 'unknown'})',
        'Last native failure: ${state['nativeStatusCode'] ?? 'none'} ${state['nativeStatusName'] ?? ''}; operation ${state['nativeOperation'] ?? '—'}; elapsed ${state['nativeElapsedMs'] ?? '—'}ms; role ${state['nativeRole'] ?? '—'}; strategy ${state['nativeStrategy'] ?? '—'}',
        'Last failure: ${state['lastFailure'] ?? 'none'}',
        'Last native diagnostic: ${state['lastNearbyNativeError'] ?? 'none'}',
        'Events: ${_dependencies.diagnostics.eventCount}; oldest ${_dependencies.diagnostics.oldestEvent?.toIso8601String() ?? 'unknown'}; newest ${_dependencies.diagnostics.newestEvent?.toIso8601String() ?? 'unknown'}',
      ].join('\n');
      final file = await _dependencies.diagnostics.exportZip(
        appInfo: {
          'app': RelioBuildInfo.appName,
          'version': RelioBuildInfo.versionName,
          'build': RelioBuildInfo.buildNumber,
          'package': _device['package'] ?? 'unknown',
          'flavor': RelioBuildInfo.environmentLabel,
        },
        deviceState: {..._device, ...state},
        summary: summary,
      );
      await _dependencies.diagnostics.share(file);
    } on Object {
      if (mounted) _message('ส่งออกข้อมูลวินิจฉัยไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    await _dependencies.diagnostics.clearLogs();
    if (mounted) {
      setState(() {});
      _message('ล้างเฉพาะ Log วินิจฉัยแล้ว');
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final service = _dependencies.nearbyService;
    final readiness = service.readiness;
    final diagnostic = _dependencies.diagnostics;
    return Scaffold(
      appBar: RelioAppBar(
        title: 'การวินิจฉัยระบบ',
        onBack: () => context.pop(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('แอป', [
            'RELIO ${RelioBuildInfo.versionName}+${RelioBuildInfo.buildNumber}',
            'Package: ${_device['package'] ?? 'กำลังอ่าน'}',
            'Flavor: ${RelioBuildInfo.environmentLabel}',
          ]),
          _section('อุปกรณ์', [
            '${_device['manufacturer'] ?? 'กำลังอ่าน'} ${_device['model'] ?? ''}',
            'Android ${_device['androidVersion'] ?? '—'} • API ${_device['apiLevel'] ?? '—'}',
          ]),
          _section('ความพร้อม Nearby', [
            'Bluetooth: ${_status(readiness?.bluetoothEnabled)}',
            'Wi-Fi: ${_status(readiness?.wifiEnabled)}',
            'Location: ${_status(readiness?.locationEnabled)}',
            'สิทธิ์: ${readiness?.missingPermissions.isEmpty ?? true ? 'ครบ' : 'ขาด ${readiness!.missingPermissions.join(', ')}'}',
            readiness?.summary ?? 'ยังไม่มีข้อมูล readiness',
          ]),
          _section('Native Nearby', [
            'Active negotiation: ${service.hasActiveConnectionAttempts ? 'yes' : 'no'}',
            'Google Play Services: ${service.nativeTransportSnapshot['googlePlayServicesVersionName'] ?? 'กำลังอ่าน'} (${service.nativeTransportSnapshot['googlePlayServicesVersionCode'] ?? '—'})',
            'Nearby library: ${service.nativeTransportSnapshot['nearbyLibraryVersion'] ?? '—'} • play-services-nearby ${service.nativeTransportSnapshot['playServicesNearbyDependencyVersion'] ?? '—'}',
            'กลยุทธ์: Advertising ${service.nativeTransportSnapshot['advertisingStrategy'] ?? '—'} • Discovery ${service.nativeTransportSnapshot['discoveryStrategy'] ?? '—'}',
            if (service.lastNativeConnectionFailure case final failure?)
              'ครั้งล่าสุด: ${failure.rawStatusCode ?? '—'} • ${failure.rawStatusName ?? '—'} • ${failure.operation ?? '—'} • ${failure.elapsedMs ?? '—'}ms • ${failure.role ?? '—'} • ${failure.strategy ?? '—'}',
            if (service.lastNativeConnectionFailure?.rawStatusMessage
                case final message?)
              'รายละเอียด: $message',
            if (service.lastNativeConnectionFailure == null)
              'ความล้มเหลว Native ล่าสุด: ยังไม่มี',
          ]),
          _section('การเชื่อมต่อและ Trust', [
            'ค้นพบ ${service.discoveredPeers.length} • เชื่อมต่อ ${service.connectedPeerCount} • คำขอเข้า ${service.pendingConnectionRequests.length}',
            'สถานะ: ${service.applicationState.name} • retry ${_dependencies.nearbyRetryAttempt}',
            'Trusted peers: ${_trustedPeers.where((peer) => peer.isTrusted == true).length}',
            'เพียร์ปัจจุบัน: ${_trustStateLabel(_currentPeerTrustState())}',
            'ความล้มเหลวล่าสุด: ${service.peerErrors.values.lastOrNull ?? service.lastErrorCode ?? 'ไม่มี'}',
            'Handshake: ${service.peerErrors.values.any((value) => value.contains('identity'))
                ? 'มีข้อผิดพลาด'
                : service.connectedPeers.isEmpty
                ? 'ยังไม่เริ่ม'
                : 'กำลังดำเนินการ/สำเร็จ'}',
          ]),
          FutureBuilder<int>(
            future: diagnostic.storageBytes,
            builder: (context, snapshot) => _section('Log วินิจฉัย', [
              'ขนาด ${((snapshot.data ?? 0) / 1024).toStringAsFixed(1)} KB • ${diagnostic.eventCount} events',
              'เก่าสุด ${diagnostic.oldestEvent?.toLocal().toString() ?? '—'}',
              'ใหม่สุด ${diagnostic.newestEvent?.toLocal().toString() ?? '—'}',
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            label: const Text('ส่งออกข้อมูลวินิจฉัย'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _clear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('ล้างเฉพาะ Log'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<String> lines) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                line,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    ),
  );

  String _status(bool? value) => value == null
      ? 'ไม่ทราบ'
      : value
      ? 'พร้อม'
      : 'ปิด/ไม่พร้อม';

  String _currentPeerTrustState() {
    final service = _dependencies.nearbyService;
    final endpoint = service.peerStates.entries
        .where(
          (entry) =>
              entry.value == NearbyConnectionState.connecting ||
              entry.value == NearbyConnectionState.incomingRequest ||
              entry.value == NearbyConnectionState.connected,
        )
        .firstOrNull
        ?.key;
    if (endpoint == null) return 'no_active_peer';
    final stableId = service.endpointToDeviceId[endpoint];
    final hint = service.discoveredPeers
        .where((candidate) => candidate.endpointId == endpoint)
        .firstOrNull
        ?.identityFingerprintHint;
    final peer = _trustedPeers.where((item) {
      return item.deviceId == stableId ||
          (hint != null && item.publicIdentityFingerprint == hint);
    }).firstOrNull;
    if (peer == null) return 'unknown_or_requires_manual_approval';
    if (peer.isBlocked == true) return 'blocked';
    if (peer.isTrusted == true &&
        peer.publicIdentityKey != null &&
        peer.publicIdentityFingerprint != null) {
      return 'trusted_identity_pinned';
    }
    return peer.isTrusted == true
        ? 'legacy_trusted_requires_manual_approval'
        : 'untrusted_requires_manual_approval';
  }

  String _trustStateLabel(String state) => switch (state) {
    'no_active_peer' => 'ไม่มี peer ที่กำลังเชื่อมต่อ',
    'trusted_identity_pinned' => 'ยืนยันตัวตนแล้ว',
    'legacy_trusted_requires_manual_approval' =>
      'Trust เดิมไม่สมบูรณ์ — ต้องอนุมัติด้วยตนเอง',
    'blocked' => 'ถูกบล็อก',
    'untrusted_requires_manual_approval' => 'ยังไม่เชื่อถือ — ต้องอนุมัติ',
    _ => 'ไม่พบข้อมูล — ต้องตรวจสอบด้วยตนเอง',
  };
}
