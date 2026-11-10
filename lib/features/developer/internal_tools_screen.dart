// เครื่องมือภายในสำหรับดูสถานะและควบคุมตัวเลือก QA ที่เปิดใช้ตาม flavor
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../app/environment.dart';
import '../../core/app_update/app_update_service.dart';
import '../../core/app_update/public_update_errors.dart';
import '../../core/feature_flags/feature_flags.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';
import '../settings/connectivity_diagnostics_card.dart';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Internal Tools Screen
class InternalToolsScreen extends StatefulWidget {
  const InternalToolsScreen({super.key});

  @override
  State<InternalToolsScreen> createState() => _InternalToolsScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Internal Tools Screen State)
class _InternalToolsScreenState extends State<InternalToolsScreen> {
  AppUpdateService? _appUpdateService;
  List<NearbyPeer> _bondedPeers = const [];
  var _updateCheckInProgress = false;
  bool backgroundRelay = false;
  bool _backgroundRelayLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_backgroundRelayLoaded) {
      _backgroundRelayLoaded = true;
      final dependencies = RelioDependencyScope.of(context);
      unawaited(
        dependencies.repositories.settings
            .getBool('background_relay_enabled', defaultValue: false)
            .then((value) {
              if (mounted) setState(() => backgroundRelay = value);
            }),
      );
    }
    if (!RelioBuildInfo.isTest || _appUpdateService != null) return;
    _appUpdateService = RelioDependencyScope.of(context).appUpdateService
      ..addListener(_handleUpdateChanged);
  }

  @override
  void dispose() {
    _appUpdateService?.removeListener(_handleUpdateChanged);
    super.dispose();
  }

  void _handleUpdateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setBackgroundRelay(bool enabled) async {
    final dependencies = RelioDependencyScope.of(context);
    if (enabled &&
        !await dependencies.localNotificationService.notificationsAllowed &&
        !await dependencies.localNotificationService.requestPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ต้องอนุญาตการแจ้งเตือนเพื่อแสดงสถานะ Relay เบื้องหลัง',
          ),
        ),
      );
      return;
    }
    final active = await dependencies.setBackgroundRelayEnabled(enabled);
    if (!mounted) return;
    setState(() => backgroundRelay = enabled && active);
    if (!active) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'เปิดโหมดส่งต่อเบื้องหลังไม่ได้ ตรวจสอบสิทธิ์และ Nearby',
          ),
        ),
      );
    }
  }

  Future<void> _handleUpdateTap() async {
    final service = _appUpdateService;
    if (service == null) return;
    if (service.snapshot.status == AppUpdateStatus.updateAvailable) {
      await _showUpdateDialog();
      return;
    }
    await _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final service = _appUpdateService;
    if (service == null) return;
    setState(() => _updateCheckInProgress = true);
    final snapshot = await service.checkForUpdate(manual: true);
    if (!mounted) return;
    setState(() => _updateCheckInProgress = false);
    if (snapshot.status == AppUpdateStatus.updateAvailable) {
      await _showUpdateDialog();
      return;
    }
    _showUpdateMessage(snapshot);
  }

  Future<void> _showUpdateDialog() async {
    final service = _appUpdateService;
    if (service == null) return;
    final manifest = service.snapshot.manifest;
    if (manifest == null || !mounted) return;
    final shouldDownload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('พบอัปเดต RELIO'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'เวอร์ชันปัจจุบัน ${service.currentBuild}\n'
                'เวอร์ชันใหม่ ${manifest.versionName}+${manifest.versionCode}',
              ),
              const SizedBox(height: 12),
              Text(
                'ขนาดประมาณ ${(manifest.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB',
              ),
              if (manifest.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('รายการเปลี่ยนแปลง'),
                ...manifest.releaseNotes.map((note) => Text('• $note')),
              ],
              const SizedBox(height: 12),
              const Text(
                'ระบบจะดาวน์โหลดหลังจากกดยืนยัน และ Android จะขอให้ยืนยันการติดตั้งอีกครั้ง',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ดาวน์โหลดอัปเดต'),
          ),
        ],
      ),
    );
    if (shouldDownload != true || !mounted) return;
    setState(() => _updateCheckInProgress = true);
    final snapshot = await service.downloadAndInstall();
    if (!mounted) return;
    setState(() => _updateCheckInProgress = false);
    _showUpdateMessage(snapshot);
  }

  void _showUpdateMessage(AppUpdateSnapshot snapshot) {
    final message = switch (snapshot.status) {
      AppUpdateStatus.noUpdate ||
      AppUpdateStatus.checked => 'ยังไม่มีอัปเดตใหม่',
      AppUpdateStatus.installing => 'เปิด Android Package Installer แล้ว',
      AppUpdateStatus.installPermissionRequired =>
        'โปรดอนุญาตให้ RELIO ติดตั้ง APK จากภายนอก แล้วกดยืนยันอีกครั้ง',
      AppUpdateStatus.error => _friendlyUpdateError(snapshot.code),
      AppUpdateStatus.unavailable => 'ยังไม่พร้อมใช้งาน โปรดลองภายหลัง',
      _ => 'ฟีเจอร์นี้ใช้ได้เฉพาะแอป QA',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyUpdateError(String? code) => switch (code) {
    PublicUpdateErrorCode.dnsError ||
    PublicUpdateErrorCode.socketError ||
    PublicUpdateErrorCode.timeoutError => 'เชื่อมต่อเซิร์ฟเวอร์อัปเดตไม่สำเร็จ',
    PublicUpdateErrorCode.tlsError => 'ไม่สามารถสร้างการเชื่อมต่อที่ปลอดภัยได้',
    PublicUpdateErrorCode.httpError ||
    PublicUpdateErrorCode.jsonError ||
    PublicUpdateErrorCode.manifestValidationError ||
    PublicUpdateErrorCode.urlValidationError => 'ข้อมูลอัปเดตไม่ถูกต้อง',
    _ => 'ตรวจสอบหรือติดตั้งอัปเดตไม่สำเร็จ',
  };

  String get _updateSubtitle {
    final status = _appUpdateService?.snapshot.status;
    return switch (status) {
      AppUpdateStatus.checking => 'กำลังตรวจสอบ…',
      AppUpdateStatus.checked ||
      AppUpdateStatus.noUpdate => 'ตรวจสอบล่าสุดแล้ว',
      AppUpdateStatus.updateAvailable ||
      AppUpdateStatus.updateStarted => 'มี build ใหม่ให้ติดตั้ง',
      AppUpdateStatus.unavailable =>
        'ตรวจสอบช่องทางสาธารณะไม่สำเร็จ โปรดลองภายหลัง',
      AppUpdateStatus.downloading => 'กำลังดาวน์โหลดอัปเดต…',
      AppUpdateStatus.installPermissionRequired =>
        'ต้องอนุญาตการติดตั้ง APK จากภายนอก',
      AppUpdateStatus.installing => 'รอการยืนยันจาก Android',
      AppUpdateStatus.error => 'ตรวจสอบไม่สำเร็จ',
      _ =>
        'เวอร์ชัน ${RelioBuildInfo.versionName}+${RelioBuildInfo.buildNumber}',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!RelioBuildInfo.developerDiagnosticsEnabled) {
      return Scaffold(
        appBar: RelioAppBar(title: 'เครื่องมือภายใน'),
        body: const Center(child: Text('ไม่สามารถใช้เครื่องมือนี้ได้')),
      );
    }
    final dependencies = RelioDependencyScope.of(context);
    final internalExperience = dependencies.internalExperience;
    if (!internalExperience.developerModeEnabled) {
      return Scaffold(
        appBar: RelioAppBar(title: 'เครื่องมือภายใน'),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('กลับไปการตั้งค่า'),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: RelioAppBar(
        title: 'เครื่องมือภายใน',
        onBack: () => context.pop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        children: [
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.developer_mode_rounded),
              title: const Text('โหมดผู้พัฒนา'),
              subtitle: const Text('ปิดเพื่อซ่อนเครื่องมือภายในและข้อมูล DEMO'),
              value: internalExperience.developerModeEnabled,
              onChanged: (enabled) async {
                await internalExperience.setDeveloperMode(enabled);
                if (!enabled && context.mounted) context.go('/settings');
              },
            ),
          ),
          ExpansionTile(
            key: const ValueKey('developer-device-status'),
            title: const _InternalSectionTitle('สถานะอุปกรณ์และการเชื่อมต่อ'),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
            children: const [ConnectivityDiagnosticsCard()],
          ),
          ExpansionTile(
            key: const ValueKey('developer-nearby-relay'),
            title: const _InternalSectionTitle('Nearby และ Relay'),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              if (defaultTargetPlatform == TargetPlatform.android &&
                  dependencies.transport is! MockNearbyTransport) ...[
                RelioSettingTile(
                  icon: Icons.hub_outlined,
                  title: 'ช่วยส่งต่อข้อความเบื้องหลัง',
                  subtitle:
                      'ให้เครื่องนี้ช่วย Relay ต่อเมื่อย่อแอป โดยมีการแจ้งเตือนค้างไว้',
                  trailing: Switch(
                    value: backgroundRelay,
                    onChanged: (value) => unawaited(_setBackgroundRelay(value)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (dependencies
                  .nearbyService
                  .compatibilityFallbackAvailable) ...[
                OutlinedButton(
                  onPressed: () async {
                    await dependencies.nearbyService.activateCompatibilityMode(
                      serverRole: true,
                    );
                    if (mounted) setState(() {});
                  },
                  child: const Text('Bluetooth Classic QA · Listener'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final nearby = dependencies.nearbyService;
                    await nearby.activateCompatibilityMode(
                      serverRole: false,
                      bondedOnly: true,
                    );
                    final devices = await nearby.bondedBluetoothDevices();
                    if (mounted) {
                      setState(
                        () => _bondedPeers = devices
                            .map(
                              (d) => NearbyPeer(id: d.endpointId, name: d.name),
                            )
                            .toList(),
                      );
                    }
                  },
                  child: const Text('Bluetooth Classic QA · อุปกรณ์ที่จับคู่'),
                ),
                for (final peer in _bondedPeers)
                  ListTile(
                    title: Text(peer.name),
                    onTap: () =>
                        dependencies.nearbyService.connect(peer.endpointId),
                  ),
              ],
              RelioSettingTile(
                icon: Icons.developer_mode_outlined,
                title: 'ตรวจสอบ Nearby (สำหรับทีมพัฒนา)',
                subtitle: 'เครื่องมือตรวจสอบการเชื่อมต่อ',
                onTap: () => context.push('/developer/nearby'),
              ),
              const SizedBox(height: 8),
              RelioSettingTile(
                icon: Icons.usb_rounded,
                title: 'ตรวจสอบ Nearby Transport',
                subtitle: 'เครื่องมือทดสอบ Transport สำหรับ DEV/QA',
                onTap: () => context.push('/diagnostics/nearby-transport'),
              ),
              const SizedBox(height: 8),
              RelioSettingTile(
                icon: Icons.route_outlined,
                title: 'ตรวจสอบ Relay (สำหรับทีมพัฒนา)',
                subtitle: 'เครื่องมือตรวจสอบ Relay',
                onTap: () => context.push('/developer/relay'),
              ),
            ],
          ),
          ExpansionTile(
            key: const ValueKey('developer-experiments'),
            title: const _InternalSectionTitle('เครื่องมือทดลองและจำลอง'),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: dependencies.nearbyService,
                builder: (context, _) {
                  final nearby = dependencies.nearbyService;
                  final enabled =
                      nearby.developerLocationSharingOverrideEnabled;
                  final subtitle = !enabled
                      ? 'OFF • หยุดรับ GPS และการแชร์ทันที'
                      : nearby.liveLocationSharingConsent != true
                      ? 'ON ตามค่าเริ่มต้น • เริ่มเมื่อผู้ใช้ให้ความยินยอมและ Android อนุญาต'
                      : 'ON • ใช้เมื่อแอปเปิด และแชร์เฉพาะอุปกรณ์ที่ยืนยันแล้ว';
                  return Card(
                    child: SwitchListTile(
                      key: const ValueKey('developer-live-location-override'),
                      secondary: const Icon(Icons.my_location_outlined),
                      title: const Text('แชร์ตำแหน่งสดอัตโนมัติ'),
                      subtitle: Text(subtitle),
                      value: enabled,
                      onChanged: (value) async {
                        try {
                          await nearby.setDeveloperLocationSharingOverride(
                            value,
                          );
                        } on Object {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'เปลี่ยนตัวเลือกตำแหน่งสดไม่สำเร็จ',
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.science_outlined),
                  title: const Text('แสดงข้อมูล DEMO'),
                  subtitle: const Text(
                    'แสดงข้อมูลตัวอย่างสำหรับทดสอบ Chat และ Nearby',
                  ),
                  value: internalExperience.demoEnabled,
                  onChanged: (enabled) async {
                    try {
                      await internalExperience.setDemoEnabled(enabled);
                    } on Object {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('เปิดข้อมูล DEMO ไม่สำเร็จ'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              if (RelioBuildInfo.isTest) ...[
                AnimatedBuilder(
                  animation: dependencies.internetSimulator,
                  builder: (context, _) {
                    final simulator = dependencies.internetSimulator;
                    return Card(
                      child: SwitchListTile(
                        secondary: const Icon(Icons.wifi_off_rounded),
                        title: const Text('จำลองอินเทอร์เน็ต Offline (QA)'),
                        subtitle: Text(
                          simulator.simulatedOffline
                              ? 'QA: Internet ถูกจำลองเป็น Offline • Cloud ถูกบล็อก แต่ Nearby ยังทำงาน'
                              : 'ปิดอยู่ตามค่าเริ่มต้น • ใช้ทดสอบ Nearby โดยไม่พึ่ง Cloud',
                        ),
                        value: simulator.simulatedOffline,
                        onChanged: (value) {
                          simulator.setSimulatedOffline(value);
                          unawaited(
                            dependencies.repositories.settings.setBool(
                              'qa_simulated_internet_offline',
                              value,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _ExperimentalFeaturesCard(
                  controller: dependencies.featureFlags,
                ),
                const SizedBox(height: 8),
                RelioSettingTile(
                  icon: Icons.system_update_outlined,
                  title: 'ตรวจสอบอัปเดต',
                  subtitle: _updateSubtitle,
                  trailing: _updateCheckInProgress
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _updateCheckInProgress ? null : _handleUpdateTap,
                ),
              ],
            ],
          ),
          ExpansionTile(
            key: const ValueKey('developer-diagnostics'),
            title: const _InternalSectionTitle('การวินิจฉัยและบันทึกเหตุการณ์'),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              RelioSettingTile(
                icon: Icons.health_and_safety_outlined,
                title: 'การวินิจฉัยระบบ',
                subtitle: 'สถานะ Nearby และส่งออก Log สำหรับ QA',
                onTap: () => context.push('/diagnostics'),
              ),
              RelioSettingTile(
                icon: Icons.cloud_outlined,
                title: 'ตรวจสอบ Cloud (สำหรับทีมพัฒนา)',
                subtitle: 'เครื่องมือตรวจสอบ Cloud',
                onTap: () => context.push('/developer/cloud'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Internal Section Title)
class _InternalSectionTitle extends StatelessWidget {
  const _InternalSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Experimental Features Card)
class _ExperimentalFeaturesCard extends StatelessWidget {
  const _ExperimentalFeaturesCard({required this.controller});

  final FeatureFlagController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              leading: Icon(Icons.tune_rounded),
              title: Text('ฟีเจอร์ทดลอง (QA)'),
              subtitle: Text('ใช้สำหรับ QA เท่านั้น'),
            ),
            for (final flag in RelioFeatureFlag.values)
              SwitchListTile(
                title: Text(flag.label),
                subtitle:
                    flag == RelioFeatureFlag.routePreview &&
                        !controller.isEnabled(RelioFeatureFlag.nearbyMapUi)
                    ? const Text('ต้องเปิด Nearby Map UI ก่อน')
                    : null,
                value: controller.configuredValue(flag),
                onChanged: (value) =>
                    unawaited(controller.setOverride(flag, value)),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => unawaited(controller.resetOverrides()),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('คืนค่าฟีเจอร์ทดลอง'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
