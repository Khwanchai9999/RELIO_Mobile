import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app.dart';
import '../../app/environment.dart';
import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool bluetooth = true;
  bool wifi = true;
  bool notifications = true;
  bool rescue = false;
  bool _settingsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    unawaited(_loadLocalSettings());
  }

  Future<void> _loadLocalSettings() async {
    final value = await RelioDependencyScope.of(
      context,
    ).repositories.settings.getBool('rescue_mode', defaultValue: false);
    if (mounted) setState(() => rescue = value);
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
            'การเชื่อมต่อ',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.bluetooth_rounded,
            title: 'Bluetooth',
            subtitle: bluetooth ? 'เปิดใช้งาน' : 'ปิดใช้งาน',
            trailing: Switch(
              value: bluetooth,
              onChanged: (value) => setState(() => bluetooth = value),
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.wifi_rounded,
            title: 'Wi-Fi Direct',
            subtitle: wifi ? 'พร้อมใช้งาน' : 'ปิดใช้งาน',
            trailing: Switch(
              value: wifi,
              onChanged: (value) => setState(() => wifi = value),
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.shield_outlined,
            title: 'โหมดหน่วยกู้ภัย',
            subtitle: rescue ? 'เปิดใช้งาน' : 'ปิดใช้งาน',
            trailing: Switch(
              value: rescue,
              onChanged: (value) {
                setState(() => rescue = value);
                final dependencies = RelioDependencyScope.of(context);
                unawaited(() async {
                  await dependencies.repositories.settings.setBool(
                    'rescue_mode',
                    value,
                  );
                  await dependencies.nearbyService.propagateCurrentStatus();
                }());
              },
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'การแสดงผล',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.dark_mode_outlined,
            title: 'ธีม',
            subtitle: _themeLabel(RelioThemeScope.of(context).mode),
            onTap: () => context.push('/settings/theme'),
          ),
          const SizedBox(height: 18),
          Text(
            'การแจ้งเตือนและข้อมูล',
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
              onChanged: (value) => setState(() => notifications = value),
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.sync_rounded,
            title: 'สถานะการซิงก์',
            subtitle: 'ดูคิวข้อมูลในเครื่อง',
            onTap: () => context.push('/sync'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.developer_mode_outlined,
            title: 'Nearby Diagnostics',
            subtitle: 'Developer technical spike',
            onTap: () => context.push('/developer/nearby'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.cloud_outlined,
            title: 'Cloud Diagnostics',
            subtitle: 'Supabase foundation / developer only',
            onTap: () => context.push('/developer/cloud'),
          ),
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
    ThemeMode.system => 'ตามระบบ',
  };
}

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = RelioThemeScope.of(context);
    return Scaffold(
      appBar: RelioAppBar(title: 'ธีม', onBack: () => context.pop()),
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
                  title: 'ตามระบบ',
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
