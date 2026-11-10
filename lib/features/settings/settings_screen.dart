// หน้าตั้งค่าระบบและธีม โดยเปลี่ยน ThemeMode ผ่าน controller อายุการใช้งานระดับแอป
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../app/app.dart';
import '../../app/environment.dart';
import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';
import '../nearby/nearby_location_consent_dialog.dart';

// รวมการตั้งค่าทั่วไปและการนำทางไปยังหน้าควบคุมเฉพาะด้าน
// ThemeMode เปลี่ยนผ่าน controller อายุระดับแอปและบันทึกเพื่อกู้คืนเมื่อเปิดใหม่
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Settings Screen State)
class _SettingsScreenState extends State<SettingsScreen> {
  bool notifications = true;
  bool notificationSound = true;
  bool notificationVibration = true;
  bool notificationPreview = true;
  bool relayParticipation = false;
  bool? _notificationsAllowed;
  bool _settingsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    unawaited(_loadLocalSettings());
  }

  Future<void> _loadLocalSettings() async {
    final dependencies = RelioDependencyScope.of(context);
    final values = await Future.wait([
      dependencies.repositories.settings.getBool(
        'notifications_enabled',
        defaultValue: true,
      ),
      dependencies.repositories.settings.getBool(
        'notification_sound',
        defaultValue: true,
      ),
      dependencies.repositories.settings.getBool(
        'notification_vibration',
        defaultValue: true,
      ),
      dependencies.repositories.settings.getBool(
        'notification_preview',
        defaultValue: true,
      ),
    ]);
    final notificationsAllowed = defaultTargetPlatform == TargetPlatform.android
        ? await dependencies.localNotificationService.notificationsAllowed
        : null;
    if (!mounted) return;
    setState(() {
      notifications = values[0];
      notificationSound = values[1];
      notificationVibration = values[2];
      notificationPreview = values[3];
      _notificationsAllowed = notificationsAllowed;
    });
    final consent = await dependencies.getRelayParticipationConsent();
    if (mounted) setState(() => relayParticipation = consent);
  }

  Future<void> _setRelayParticipation(bool allowed) async {
    final dependencies = RelioDependencyScope.of(context);
    if (allowed && !relayParticipation && RelioBuildInfo.isTest) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('อนุญาต QA Relay หรือไม่?'),
          content: const Text(
            'การส่งข้อความผ่าน QA Relay ไม่เข้ารหัส เครื่องกลางที่ช่วยส่งต่อ '
            'อาจอ่านข้อความได้ เปิดเฉพาะเมื่อผู้ใช้เครื่องนี้อนุมัติ '
            'และปิด consent ได้ทุกเมื่อ การอนุญาตนี้ใช้เฉพาะ QA '
            'และไม่เปิดใช้ Production Relay',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ยอมรับและเปิด QA Relay'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    await dependencies.setRelayParticipationConsent(allowed);
    if (!mounted) return;
    setState(() => relayParticipation = allowed);
  }

  Future<void> _setNotifications(bool enabled) async {
    final dependencies = RelioDependencyScope.of(context);
    var nextValue = enabled;
    if (enabled &&
        !await dependencies.localNotificationService.requestPermission()) {
      nextValue = false;
      _notificationsAllowed = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยังไม่ได้รับอนุญาตให้แสดงการแจ้งเตือน'),
          ),
        );
      }
    } else if (enabled) {
      _notificationsAllowed = true;
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

  Future<void> _setNotificationPreference(String key, bool value) async {
    await RelioDependencyScope.of(
      context,
    ).repositories.settings.setBool(key, value);
    if (!mounted) return;
    setState(() {
      switch (key) {
        case 'notification_sound':
          notificationSound = value;
        case 'notification_vibration':
          notificationVibration = value;
        case 'notification_preview':
          notificationPreview = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = RelioDependencyScope.of(context);
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
          _SettingsSectionTitle('การแจ้งเตือน'),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.notifications_none_rounded,
            title: 'การแจ้งเตือน',
            subtitle: !notifications
                ? 'ปิดการแจ้งเตือนจาก RELIO'
                : _notificationsAllowed == false
                ? 'Android ยังไม่อนุญาตให้แสดงการแจ้งเตือน'
                : 'เปิดรับการแจ้งเตือนจาก RELIO',
            trailing: Switch(
              value: notifications,
              onChanged: (value) => unawaited(_setNotifications(value)),
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.volume_up_outlined,
            title: 'เสียงแจ้งเตือน',
            subtitle: 'เล่นเสียงเมื่อได้รับการแจ้งเตือน',
            trailing: Switch(
              value: notificationSound,
              onChanged: notifications
                  ? (value) => unawaited(
                      _setNotificationPreference('notification_sound', value),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.vibration_rounded,
            title: 'สั่นเมื่อมีการแจ้งเตือน',
            subtitle: 'สั่นเมื่อได้รับการแจ้งเตือน',
            trailing: Switch(
              value: notificationVibration,
              onChanged: notifications
                  ? (value) => unawaited(
                      _setNotificationPreference(
                        'notification_vibration',
                        value,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.visibility_outlined,
            title: 'แสดงเนื้อหาข้อความ',
            subtitle: 'แสดงตัวอย่างข้อความในการแจ้งเตือน',
            trailing: Switch(
              value: notificationPreview,
              onChanged: notifications
                  ? (value) => unawaited(
                      _setNotificationPreference('notification_preview', value),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          _SettingsSectionTitle('การจัดการข้อมูล'),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.sync_rounded,
            title: 'สถานะการซิงก์ข้อมูลออนไลน์',
            subtitle: 'ดูคิวข้อมูลในเครื่อง',
            onTap: () => context.push('/sync'),
          ),
          const SizedBox(height: 18),
          _SettingsSectionTitle('ความเป็นส่วนตัว'),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.forward_to_inbox_outlined,
            title: 'ช่วยค้นหาอุปกรณ์ผ่านรีเลย์',
            subtitle: RelioBuildInfo.isTest
                ? 'แชร์ชื่อและเส้นทางกับอุปกรณ์ที่ยืนยันตัวตนแล้ว • QA Relay ไม่เข้ารหัสและเครื่องกลางอาจอ่านข้อความได้ • ปิด consent ได้ทุกเมื่อ'
                : 'แชร์ชื่อและเส้นทางของอุปกรณ์ที่เข้าถึงได้กับเครื่อง RELIO ที่ยืนยันตัวตนแล้ว การส่งต่อข้อความผ่านรีเลย์ขึ้นอยู่กับการรองรับของรุ่นแอป',
            trailing: Switch(
              key: const ValueKey('relay-participation-consent'),
              value: relayParticipation,
              onChanged: (value) => unawaited(_setRelayParticipation(value)),
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.lock_outline,
            title: 'หลักการจัดการข้อมูล',
            subtitle: 'อ่านวิธีจัดเก็บและใช้งานข้อมูล',
            onTap: () => _showPrivacy(context, dependencies),
          ),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: dependencies.internalExperience,
            builder: (context, _) =>
                dependencies.internalExperience.developerModeEnabled
                ? Column(
                    children: [
                      RelioSettingTile(
                        icon: Icons.developer_mode_rounded,
                        title: 'ตัวเลือกสำหรับนักพัฒนา',
                        subtitle: 'เครื่องมือสำหรับ DEV และ QA',
                        onTap: () => context.push('/internal-tools'),
                      ),
                      const SizedBox(height: 18),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          _SettingsSectionTitle('เกี่ยวกับแอป'),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.info_outline,
            title: 'เกี่ยวกับ RELIO',
            subtitle: RelioBuildInfo.aboutLabel,
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _manageNearbyLocationConsent(
    RelioDependencies dependencies,
  ) async {
    final approved = await showNearbyLiveLocationConsentDialog(
      context,
      firstUse: false,
    );
    if (approved == null) return;
    var permissionGranted = true;
    if (approved) {
      try {
        permissionGranted = await dependencies.permissionService
            .requestLiveLocationPermission();
      } on Object {
        permissionGranted = false;
      }
    }
    await dependencies.nearbyService.setLiveLocationConsent(approved);
    if (approved) {
      await dependencies.nearbyService.locationCoordinator
          ?.onPermissionOrReadinessChanged();
    }
    if (!mounted) return;
    setState(() {});
    if (approved && !permissionGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ยังไม่ได้รับอนุญาต Location • ตรวจสอบสิทธิ์ได้ในตั้งค่า Android',
          ),
        ),
      );
    }
  }

  void _showPrivacy(
    BuildContext context,
    RelioDependencies dependencies,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ข้อมูลและความเป็นส่วนตัว'),
      content: const SingleChildScrollView(
        child: Text(
          'RELIO บันทึกข้อมูลหลักในเครื่องก่อน การซิงก์ Cloud ใช้กับข้อมูลของบัญชีที่ลงชื่อเข้าใช้เมื่อเชื่อมต่อได้ '
          'ตำแหน่งใช้เมื่อคุณสั่งแชร์ เปิด SOS หรืออนุญาตแชร์สดบน Nearby กับอุปกรณ์ที่ยืนยันแล้วขณะเปิดแอป '
          'การแชร์สดไม่ทำงานเบื้องหลังและไม่ส่งตำแหน่งนี้ไป Cloud คุณตรวจสอบหรือถอนความยินยอมได้จากตัวเลือกด้านล่าง '
          'และจำกัดสิทธิ์ Location ได้จาก Android '
          'ผู้ติดต่อฉุกเฉินเก็บไว้ในเครื่อง ไม่ส่งให้ผู้อื่นหรือ Cloud อัตโนมัติ',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            unawaited(_manageNearbyLocationConsent(dependencies));
          },
          child: const Text('จัดการความยินยอมตำแหน่งสด'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );

  void _showAbout(BuildContext context) => showAboutDialog(
    context: context,
    applicationName: RelioBuildInfo.appName,
    applicationIcon: Image.asset(
      'assets/branding/relio-logo-master.png',
      width: 52,
      height: 52,
    ),
    children: [
      const Text('สื่อสารและขอความช่วยเหลือผ่านอุปกรณ์ใกล้เคียง แม้ออฟไลน์'),
      const SizedBox(height: 8),
      const Text('ข้อมูลหลักจัดเก็บในเครื่อง; Cloud เป็นทางเลือก'),
      const SizedBox(height: 8),
      _AboutVersionEntry(
        version: '${RelioBuildInfo.versionName}+${RelioBuildInfo.buildNumber}',
        onInternalTools:
            RelioBuildInfo.developerDiagnosticsEnabled &&
                !RelioDependencyScope.of(
                  context,
                ).internalExperience.developerModeEnabled
            ? () {
                Navigator.of(context, rootNavigator: true).pop();
                unawaited(
                  RelioDependencyScope.of(
                    context,
                  ).internalExperience.setDeveloperMode(true).then((_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('เปิดโหมดผู้พัฒนาแล้ว')),
                    );
                  }),
                );
              }
            : null,
      ),
    ],
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Settings Section Title)
class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (About Version Entry)
class _AboutVersionEntry extends StatefulWidget {
  const _AboutVersionEntry({required this.version, this.onInternalTools});

  final String version;
  final VoidCallback? onInternalTools;

  @override
  State<_AboutVersionEntry> createState() => _AboutVersionEntryState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (About Version Entry State)
class _AboutVersionEntryState extends State<_AboutVersionEntry> {
  static const _requiredTaps = 7;
  static const _resetAfter = Duration(seconds: 2);

  Timer? _resetTimer;
  var _tapCount = 0;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onInternalTools == null) return;
    _resetTimer?.cancel();
    _tapCount++;
    if (_tapCount >= _requiredTaps) {
      widget.onInternalTools!.call();
      return;
    }
    _resetTimer = Timer(_resetAfter, () => _tapCount = 0);
  }

  @override
  Widget build(BuildContext context) {
    final text = Text('Version ${widget.version}');
    if (widget.onInternalTools == null) return text;
    return InkWell(
      key: const ValueKey('about-version-internal-tools'),
      onTap: _handleTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Semantics(
          button: true,
          label: 'Version ${widget.version}',
          child: text,
        ),
      ),
    );
  }
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Theme Settings Screen
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

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Theme Option)
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
