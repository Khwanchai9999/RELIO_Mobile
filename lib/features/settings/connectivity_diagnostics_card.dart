// การ์ดสรุป Internet, วิทยุ Nearby และ Cloud แยกสถานะออกจากกันตามความหมาย
import 'package:flutter/material.dart';

import '../../app/environment.dart';
import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/connectivity/runtime_connectivity.dart';
import '../../core/relio_dependencies.dart';
import '../../core/sync/sync_engine.dart';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Connectivity Diagnostics Card
class ConnectivityDiagnosticsCard extends StatefulWidget {
  const ConnectivityDiagnosticsCard({super.key});

  @override
  State<ConnectivityDiagnosticsCard> createState() =>
      _ConnectivityDiagnosticsCardState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Connectivity Diagnostics Card State)
class _ConnectivityDiagnosticsCardState
    extends State<ConnectivityDiagnosticsCard> {
  late RelioDependencies _dependencies;
  late Future<String> _deviceId;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _dependencies = RelioDependencyScope.of(context);
    _deviceId = _dependencies.identity.getDeviceId();
  }

  Future<void> _requestPermissions() async {
    await _dependencies.permissionService.requestNearbyPermissions();
    if (!mounted) return;
    await _dependencies.startNearbySessionIfPermitted(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = _dependencies.connectivityStatus;
    final nearby = _dependencies.nearbyService;
    return AnimatedBuilder(
      animation: Listenable.merge([connectivity, nearby]),
      builder: (context, _) => StreamBuilder<SyncEngineSnapshot>(
        stream: _dependencies.syncEngine.watchState(),
        initialData: _dependencies.syncEngine.snapshot,
        builder: (context, syncSnapshot) {
          final status = connectivity.status;
          final runtime = status.runtime;
          final cloud =
              syncSnapshot.data?.cloudState ?? CloudState.notConfigured;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(RelioSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'สถานะระบบจริง',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: connectivity.refresh,
                        tooltip: 'ตรวจสอบใหม่',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  FutureBuilder<String>(
                    future: _deviceId,
                    builder: (context, snapshot) => _StatusRow(
                      label: 'รหัสอุปกรณ์',
                      value: snapshot.data == null
                          ? 'กำลังโหลด'
                          : 'RELIO-${snapshot.data!.replaceAll('-', '').substring(snapshot.data!.replaceAll('-', '').length - 4).toUpperCase()}',
                    ),
                  ),
                  _StatusRow(
                    label: 'เวอร์ชันแอป',
                    value:
                        '${RelioBuildInfo.versionName}+${RelioBuildInfo.buildNumber}',
                  ),
                  _StatusRow(
                    label: 'อินเทอร์เน็ต',
                    value: _internetLabel(status.reachability),
                    color: _internetColor(status.reachability),
                  ),
                  _StatusRow(
                    label: 'Wi-Fi',
                    value: _radioLabel(runtime.wifiEnabled),
                  ),
                  _StatusRow(
                    label: 'Bluetooth',
                    value: _radioLabel(runtime.bluetoothEnabled),
                  ),
                  _StatusRow(
                    label: 'ความพร้อม Nearby',
                    value: nearby.statusLabel,
                    color: RelioColors.primary,
                  ),
                  _StatusRow(
                    label: 'อุปกรณ์ที่เชื่อมต่อ',
                    value: '${nearby.connectedPeerCount}',
                  ),
                  _StatusRow(
                    label: 'การซิงก์ข้อมูลออนไลน์',
                    value: _cloudLabel(cloud),
                  ),
                  if (runtime.androidSdk != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        runtime
                                .nearbyReadiness
                                .missingManifestPermissions
                                .isNotEmpty
                            ? 'ต้องอัปเดตแอป'
                            : runtime.nearbyReadiness.missingPermissions.isEmpty
                            ? 'สิทธิ์พร้อมใช้งาน'
                            : 'ต้องตรวจสอบสิทธิ์ Nearby',
                      ),
                      subtitle: Text(
                        runtime
                                .nearbyReadiness
                                .missingManifestPermissions
                                .isNotEmpty
                            ? runtime.nearbyReadiness.summary
                            : runtime.nearbyReadiness.missingPermissions.isEmpty
                            ? 'ไม่ต้องเปิด Location เพื่อใช้ Nearby บน Android รุ่นนี้'
                            : runtime.nearbyReadiness.missingPermissions.join(
                                ', ',
                              ),
                      ),
                      trailing:
                          runtime.nearbyReadiness.missingPermissions.isEmpty ||
                              runtime
                                  .nearbyReadiness
                                  .missingManifestPermissions
                                  .isNotEmpty
                          ? null
                          : TextButton(
                              onPressed: _requestPermissions,
                              child: const Text('ตรวจสอบสิทธิ์'),
                            ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Status Row)
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

String _internetLabel(InternetReachability state) => switch (state) {
  InternetReachability.checking => 'กำลังตรวจสอบ',
  InternetReachability.online => 'ออนไลน์',
  InternetReachability.offline => 'ออฟไลน์',
  InternetReachability.limited => 'จำกัด / ปลายทางตอบกลับไม่ได้',
  InternetReachability.unknown => 'ไม่ทราบ',
};

String _radioLabel(bool? enabled) => switch (enabled) {
  true => 'พร้อมใช้งาน',
  false => 'ปิดอยู่',
  null => 'ไม่ทราบ',
};

Color _internetColor(InternetReachability state) => switch (state) {
  InternetReachability.online => RelioColors.success,
  InternetReachability.offline ||
  InternetReachability.limited => RelioColors.warning,
  InternetReachability.checking ||
  InternetReachability.unknown => RelioColors.muted,
};

String _cloudLabel(CloudState state) => switch (state) {
  CloudState.ready => 'พร้อมซิงก์',
  CloudState.offline => 'รออินเทอร์เน็ต',
  CloudState.notConfigured => 'ใช้เฉพาะในเครื่อง',
  CloudState.signedOut => 'Guest / ในเครื่อง',
  CloudState.error => 'ยังซิงก์ไม่ได้',
};
