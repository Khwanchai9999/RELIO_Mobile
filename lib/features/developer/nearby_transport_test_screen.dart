// หน้าทดลองการทำงานของ transport ในสภาพแวดล้อมพัฒนา โดยไม่แทนผลทดสอบวิทยุจริง
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/diagnostics_log_service.dart';
import '../../core/nearby/nearby_service.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Nearby Transport Test Screen
class NearbyTransportTestScreen extends StatefulWidget {
  const NearbyTransportTestScreen({super.key});

  @override
  State<NearbyTransportTestScreen> createState() =>
      _NearbyTransportTestScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Nearby Transport Test Screen State)
class _NearbyTransportTestScreenState extends State<NearbyTransportTestScreen> {
  late NearbyService _nearby;
  String? _selectedEndpoint;
  bool _initialized = false;
  bool _changingMode = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _nearby = RelioDependencyScope.of(context).nearbyService;
    _nearby.addListener(_refresh);
    _initialized = true;
  }

  @override
  void dispose() {
    _nearby.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _selectMode(NearbyTransportTestMode? mode) async {
    if (mode == null || mode == _nearby.transportTestMode) return;
    setState(() => _changingMode = true);
    try {
      await _nearby.configureTransportTestMode(mode);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปลี่ยนโหมดไม่ได้ระหว่างเชื่อมต่อ')),
        );
      }
    } finally {
      if (mounted) setState(() => _changingMode = false);
    }
  }

  Future<void> _selectRole(NearbyDiagnosticRole? role) async {
    if (role == null || role == _nearby.diagnosticRole) return;
    setState(() => _changingMode = true);
    try {
      await _nearby.configureDiagnosticRole(role);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เปลี่ยนบทบาท Nearby ไม่ได้: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _changingMode = false);
    }
  }

  Future<void> _startTest() async {
    final endpoint = _selectedEndpoint;
    if (endpoint == null || !_nearby.isEndpointCurrent(endpoint)) return;
    _nearby.clearTransportTestResults();
    await _nearby.connect(endpoint);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _nearby,
    builder: (context, _) {
      final candidates = _nearby.discoveredPeers
          .where((peer) => _nearby.isEndpointCurrent(peer.endpointId))
          .toList(growable: false);
      if (!candidates.any((peer) => peer.endpointId == _selectedEndpoint)) {
        _selectedEndpoint = candidates.firstOrNull?.endpointId;
      }
      final snapshot = _nearby.nativeTransportSnapshot;
      final failure = _nearby.lastNativeConnectionFailure;
      return Scaffold(
        appBar: RelioAppBar(
          title: 'ทดสอบ Nearby Transport',
          onBack: () => context.pop(),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<NearbyDiagnosticRole>(
              key: ValueKey(_nearby.diagnosticRole),
              initialValue: _nearby.diagnosticRole,
              decoration: const InputDecoration(labelText: 'บทบาท QA Nearby'),
              items: NearbyDiagnosticRole.values
                  .map(
                    (role) =>
                        DropdownMenuItem(value: role, child: Text(role.label)),
                  )
                  .toList(growable: false),
              onChanged: _changingMode ? null : _selectRole,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<NearbyTransportTestMode>(
              key: ValueKey(_nearby.transportTestMode),
              initialValue: _nearby.transportTestMode,
              decoration: const InputDecoration(labelText: 'โหมดทดสอบ'),
              items: NearbyTransportTestMode.values
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(growable: false),
              onChanged: _changingMode ? null : _selectMode,
            ),
            const SizedBox(height: 12),
            _infoCard('สถานะ Transport', [
              'โหมด: ${_nearby.transportTestMode.diagnosticName}',
              'Discovery: ${_nearby.isDiscovering ? 'ทำงาน' : 'หยุด'} • Advertising: ${_nearby.isAdvertising ? 'ทำงาน' : 'หยุด'}',
              'Discovery Epoch: ${_nearby.transport.discoveryEpoch}',
              'Endpoint ปัจจุบัน: ${candidates.length}',
              'การเชื่อมต่อ: ${_nearby.applicationState.name}',
              'Google Play Services: ${snapshot['googlePlayServicesVersionName'] ?? 'ไม่ทราบ'} (${snapshot['googlePlayServicesVersionCode'] ?? '—'})',
              'Native ล่าสุด: ${failure?.rawStatusCode ?? '—'} ${failure?.rawStatusName ?? ''}',
              'Strategy: ${_nearby.transport.strategyName}',
              'QA role: ${_nearby.diagnosticRole.name}',
            ]),
            if (candidates.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'ยังไม่มี Endpoint ที่ค้นพบใน Discovery Epoch ปัจจุบัน',
                  ),
                ),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedEndpoint),
                initialValue: _selectedEndpoint,
                decoration: const InputDecoration(
                  labelText: 'Endpoint ปัจจุบัน',
                ),
                items: candidates
                    .map(
                      (peer) => DropdownMenuItem(
                        value: peer.endpointId,
                        child: Text(
                          '${DiagnosticsLogService.peerAlias(peer.endpointId)} • ${peer.foundAt == null ? 'อายุไม่ทราบ' : '${DateTime.now().toUtc().difference(peer.foundAt!).inSeconds}s'}',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _selectedEndpoint = value),
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed:
                  _selectedEndpoint != null &&
                      _nearby.isEndpointCurrent(_selectedEndpoint!) &&
                      !_nearby.hasActiveConnectionAttempts
                  ? _startTest
                  : null,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('เริ่มทดสอบการเชื่อมต่อ'),
            ),
            OutlinedButton.icon(
              onPressed: _nearby.clearTransportTestResults,
              icon: const Icon(Icons.clear_all),
              label: const Text('ล้างผลทดสอบเฉพาะรอบ'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.push('/diagnostics'),
              icon: const Icon(Icons.ios_share),
              label: const Text('ส่งออก Diagnostics'),
            ),
            const SizedBox(height: 8),
            _infoCard('ผลทดสอบล่าสุด', [
              if (_nearby.transportAttemptResults.isEmpty)
                'ยังไม่มีผลการเชื่อมต่อ'
              else
                for (final result in _nearby.transportAttemptResults)
                  'Attempt ${result['attemptId']} • ${result['transportTestMode']} • ${result['connected'] == true ? 'connected' : 'failed'} • ${result['nativeStatusCode'] ?? '—'} ${result['nativeStatusName'] ?? ''} • ${result['elapsedMs'] ?? '—'}ms',
            ]),
          ],
        ),
      );
    },
  );

  Widget _infoCard(String title, List<String> lines) => Card(
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
              child: SelectableText(line),
            ),
        ],
      ),
    ),
  );
}
