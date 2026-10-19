import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app.dart';
import '../../app/environment.dart';
import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/app_update/app_update_service.dart';
import '../../core/app_update/public_update_errors.dart';
import '../../core/relio_dependencies.dart';
import '../../core/feature_flags/feature_flags.dart';
import 'connectivity_diagnostics_card.dart';
import '../../shared/widgets/relio_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool notifications = true;
  bool notificationPreview = false;
  bool _settingsLoaded = false;
  bool _updateCheckInProgress = false;
  late AppUpdateService _appUpdateService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_updateServiceAttached) {
      _appUpdateService = RelioDependencyScope.of(context).appUpdateService;
      _appUpdateService.addListener(_handleUpdateChanged);
      _updateServiceAttached = true;
    }
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    unawaited(_loadLocalSettings());
  }

  bool _updateServiceAttached = false;

  void _handleUpdateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_updateServiceAttached) {
      _appUpdateService.removeListener(_handleUpdateChanged);
    }
    super.dispose();
  }

  Future<void> _handleUpdateTap() async {
    if (_appUpdateService.snapshot.status == AppUpdateStatus.updateAvailable) {
      await _showUpdateDialog();
      return;
    }
    await _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    setState(() => _updateCheckInProgress = true);
    final snapshot = await _appUpdateService.checkForUpdate(manual: true);
    if (!mounted) return;
    setState(() => _updateCheckInProgress = false);
    if (snapshot.status == AppUpdateStatus.updateAvailable) {
      await _showUpdateDialog();
      return;
    }
    _showUpdateMessage(snapshot);
  }

  Future<void> _showUpdateDialog() async {
    final manifest = _appUpdateService.snapshot.manifest;
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
                'เวอร์ชันปัจจุบัน ${_appUpdateService.currentBuild}\n'
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
    final snapshot = await _appUpdateService.downloadAndInstall();
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
    final snapshot = _appUpdateService.snapshot;
    return switch (snapshot.status) {
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

  Future<void> _loadLocalSettings() async {
    final dependencies = RelioDependencyScope.of(context);
    final values = await Future.wait([
      dependencies.repositories.settings.getBool(
        'notifications_enabled',
        defaultValue: true,
      ),
      dependencies.repositories.settings.getBool(
        'notification_preview',
        defaultValue: false,
      ),
    ]);
    if (mounted) {
      setState(() {
        notifications = values[0];
        notificationPreview = values[1];
      });
    }
  }

  Future<void> _setNotifications(bool enabled) async {
    final dependencies = RelioDependencyScope.of(context);
    var nextValue = enabled;
    if (enabled &&
        !await dependencies.localNotificationService.requestPermission()) {
      nextValue = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยังไม่ได้รับอนุญาตให้แสดงการแจ้งเตือน'),
          ),
        );
      }
    }
    if (nextValue) {
      unawaited(dependencies.syncPushRegistration());
    } else {
      await dependencies.removePushRegistration();
    }
    await dependencies.repositories.settings.setBool(
      'notifications_enabled',
      nextValue,
    );
    if (mounted) setState(() => notifications = nextValue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(title: 'ตั้งค่า', onBack: () => context.pop()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RelioSpacing.lg,
          14,
          RelioSpacing.lg,
          24,
        ),
        children: [
          Text(
            'การแสดงผล',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.dark_mode_outlined,
            title: 'ธีมแอป',
            subtitle: _themeLabel(RelioThemeScope.of(context).mode),
            onTap: () => context.push('/settings/theme'),
          ),
          const SizedBox(height: 18),
          Text(
            'การแจ้งเตือน',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.notifications_none_rounded,
            title: 'การแจ้งเตือน',
            subtitle: notifications ? 'เปิดใช้งาน' : 'ปิดใช้งาน',
            trailing: Switch(
              value: notifications,
              onChanged: (value) => unawaited(_setNotifications(value)),
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.visibility_outlined,
            title: 'แสดงเนื้อหาข้อความในการแจ้งเตือน',
            subtitle: notificationPreview
                ? 'แสดงเนื้อหาข้อความ'
                : 'แสดงข้อความทั่วไป',
            trailing: Switch(
              value: notificationPreview,
              onChanged: notifications
                  ? (value) {
                      setState(() => notificationPreview = value);
                      unawaited(
                        RelioDependencyScope.of(context).repositories.settings
                            .setBool('notification_preview', value),
                      );
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'สถานะการเชื่อมต่อ',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          const ConnectivityDiagnosticsCard(),
          const SizedBox(height: 18),
          Text(
            'ข้อมูลและความเป็นส่วนตัว',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.lock_outline,
            title: 'หลักการจัดการข้อมูล',
            subtitle: 'อ่านวิธีจัดเก็บและใช้งานข้อมูล',
            onTap: () => _showPrivacy(context),
          ),
          if (RelioBuildInfo.isTest) ...[
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: RelioDependencyScope.of(context).internetSimulator,
              builder: (context, _) {
                final simulator = RelioDependencyScope.of(
                  context,
                ).internetSimulator;
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
                        RelioDependencyScope.of(context).repositories.settings
                            .setBool('qa_simulated_internet_offline', value),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _ExperimentalFeaturesCard(
              controller: RelioDependencyScope.of(context).featureFlags,
            ),
          ],
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.sync_rounded,
            title: 'สถานะการซิงก์ข้อมูลออนไลน์',
            subtitle: 'ดูคิวข้อมูลในเครื่อง',
            onTap: () => context.push('/sync'),
          ),
          if (RelioBuildInfo.isTest) ...[
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
          if (RelioBuildInfo.developerDiagnosticsEnabled) ...[
            const SizedBox(height: 8),
            RelioSettingTile(
              icon: Icons.health_and_safety_outlined,
              title: 'การวินิจฉัยระบบ',
              subtitle: 'สถานะ Nearby และส่งออก Log สำหรับ QA',
              onTap: () => context.push('/diagnostics'),
            ),
            const SizedBox(height: 8),
            RelioSettingTile(
              icon: Icons.developer_mode_outlined,
              title: 'ตรวจสอบ Nearby (สำหรับทีมพัฒนา)',
              subtitle: 'เครื่องมือตรวจสอบการเชื่อมต่อ',
              onTap: () => context.push('/developer/nearby'),
            ),
            const SizedBox(height: 8),
            RelioSettingTile(
              icon: Icons.cloud_outlined,
              title: 'ตรวจสอบ Cloud (สำหรับทีมพัฒนา)',
              subtitle: 'เครื่องมือตรวจสอบ Cloud',
              onTap: () => context.push('/developer/cloud'),
            ),
            const SizedBox(height: 8),
            RelioSettingTile(
              icon: Icons.route_outlined,
              title: 'ตรวจสอบ Relay (สำหรับทีมพัฒนา)',
              subtitle: 'เครื่องมือตรวจสอบ Relay',
              onTap: () => context.push('/developer/relay'),
            ),
          ],
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.info_outline,
            title: 'เกี่ยวกับ RELIO',
            subtitle: RelioBuildInfo.aboutLabel,
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'โหมดสว่าง',
    ThemeMode.dark => 'โหมดมืด',
    ThemeMode.system => 'ตามการตั้งค่าเครื่อง',
  };

  void _showPrivacy(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ข้อมูลและความเป็นส่วนตัว'),
      content: const SingleChildScrollView(
        child: Text(
          'RELIO บันทึกข้อมูลหลักในเครื่องก่อน การซิงก์ Cloud ใช้กับข้อมูลของบัญชีที่ลงชื่อเข้าใช้เมื่อเชื่อมต่อได้ '
          'ตำแหน่งใช้เมื่อคุณสั่งแชร์ตำแหน่ง เปิด SOS หรือแชร์ตำแหน่งบน Nearby Map เท่านั้น '
          'ผู้ติดต่อฉุกเฉินเก็บไว้ในเครื่อง ไม่ส่งให้ผู้อื่นหรือ Cloud อัตโนมัติ',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );
}

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

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = RelioThemeScope.of(context);
    return Scaffold(
      appBar: RelioAppBar(title: 'ธีมแอป', onBack: () => context.pop()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RelioSpacing.lg,
          16,
          RelioSpacing.lg,
          24,
        ),
        children: [
          Text(
            'เลือกธีมที่ต้องการแสดงผล',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          RadioGroup<ThemeMode>(
            groupValue: controller.mode,
            onChanged: (value) {
              if (value != null) controller.setMode(value);
            },
            child: Column(
              children: [
                _ThemeOption(
                  mode: ThemeMode.light,
                  title: 'โหมดสว่าง',
                  subtitle: 'พื้นหลังสีขาว',
                  icon: Icons.light_mode_outlined,
                  selected: controller.mode,
                ),
                const SizedBox(height: 10),
                _ThemeOption(
                  mode: ThemeMode.dark,
                  title: 'โหมดมืด',
                  subtitle: 'เหมาะสำหรับที่มืด',
                  icon: Icons.dark_mode_outlined,
                  selected: controller.mode,
                ),
                const SizedBox(height: 10),
                _ThemeOption(
                  mode: ThemeMode.system,
                  title: 'ตามการตั้งค่าเครื่อง',
                  subtitle: 'ใช้การตั้งค่าของ Android',
                  icon: Icons.brightness_auto_outlined,
                  selected: controller.mode,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: RelioColors.primary.withValues(alpha: 0.08),
            child: const ListTile(
              leading: Icon(
                Icons.check_circle_outline,
                color: RelioColors.primary,
              ),
              title: Text('เปลี่ยนธีมทันที'),
              subtitle: Text('ค่าจะถูกบันทึกไว้สำหรับการเปิดแอปครั้งถัดไป'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
  });

  final ThemeMode mode;
  final String title;
  final String subtitle;
  final IconData icon;
  final ThemeMode selected;

  @override
  Widget build(BuildContext context) {
    final isSelected = mode == selected;
    return Card(
      color: isSelected ? RelioColors.primary.withValues(alpha: 0.08) : null,
      child: RadioListTile<ThemeMode>(
        value: mode,
        secondary: Icon(icon, color: isSelected ? RelioColors.primary : null),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
