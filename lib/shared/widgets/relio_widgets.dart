import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../data/models/prototype_models.dart';

class RelioAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RelioAppBar({
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: onBack != null,
      leading: onBack == null
          ? null
          : IconButton(
              onPressed: onBack,
              tooltip: 'ย้อนกลับ',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          if (subtitle != null)
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64);
}

class RelioSectionHeader extends StatelessWidget {
  const RelioSectionHeader({required this.title, this.action, super.key});

  final String title;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: action,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('ดูทั้งหมด ›'),
          ),
      ],
    );
  }
}

class RelioStatusChip extends StatelessWidget {
  const RelioStatusChip({
    required this.status,
    this.compact = false,
    super.key,
  });

  final DeviceStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 10 : 11,
        ),
      ),
    );
  }
}

class RelioUserAvatar extends StatelessWidget {
  const RelioUserAvatar({
    required this.name,
    this.size = 46,
    this.status,
    super.key,
  });

  final String name;
  final double size;
  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final palette = [
      RelioColors.primary,
      RelioColors.rescue,
      const Color(0xFFF97316),
      const Color(0xFF8B5CF6),
    ];
    final color = palette[name.codeUnitAt(0) % palette.length];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Icon(Icons.person_rounded, size: size * 0.62, color: color),
        ),
        if (status == DeviceStatus.sos || status == DeviceStatus.rescue)
          Positioned(
            right: -2,
            bottom: -1,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: status!.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: Icon(
                status == DeviceStatus.sos
                    ? Icons.priority_high_rounded
                    : Icons.shield_rounded,
                color: Colors.white,
                size: size * 0.16,
              ),
            ),
          ),
      ],
    );
  }
}

class RelioConnectivityBanner extends StatelessWidget {
  const RelioConnectivityBanner({required this.internetOnline, super.key});

  final bool internetOnline;

  @override
  Widget build(BuildContext context) {
    final color = internetOnline ? RelioColors.success : RelioColors.warning;
    final surface = internetOnline
        ? RelioColors.success.withValues(alpha: 0.08)
        : RelioColors.warning.withValues(alpha: 0.10);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RelioSpacing.lg,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.25)),
        ),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _ConnectivityLine(
            icon: internetOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            label: 'Internet',
            detail: internetOnline
                ? 'ออนไลน์ • ซิงก์คลาวด์แล้ว'
                : 'ไม่มีอินเทอร์เน็ต',
            color: color,
          ),
          const _ConnectivityLine(
            icon: Icons.radar_rounded,
            label: 'Nearby',
            detail: 'พร้อมใช้งาน • พบ 5 เครื่อง',
            color: RelioColors.primary,
          ),
        ],
      ),
    );
  }
}

class _ConnectivityLine extends StatelessWidget {
  const _ConnectivityLine({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 5),
        Text(detail, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class RelioDeviceCard extends StatelessWidget {
  const RelioDeviceCard({required this.device, this.onTap, super.key});

  final RelioDevice device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = device.status.color;
    final stateLabel = switch (device.presence) {
      PeerPresence.demo => 'ตัวอย่าง • ${device.approximateDistance}',
      PeerPresence.discovered => 'REAL • ค้นพบ',
      PeerPresence.connecting => 'REAL • กำลังเชื่อมต่อ',
      PeerPresence.connected => 'REAL • เชื่อมต่อแล้ว',
      PeerPresence.disconnected => 'REAL • ขาดการเชื่อมต่อ',
      PeerPresence.failed => 'REAL • เชื่อมต่อไม่สำเร็จ',
      PeerPresence.stale =>
        'REAL • พบล่าสุด ${_lastSeenLabel(device.lastSeenAt)}',
    };
    final stableDeviceId = RegExp(r'^[0-9a-fA-F-]{16,}$').hasMatch(device.id)
        ? 'RELIO-${device.id.replaceAll('-', '').substring(device.id.replaceAll('-', '').length - 4).toUpperCase()}'
        : 'รอยืนยัน RELIO ID';
    return Card(
      clipBehavior: Clip.antiAlias,
      color: color.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(RelioSpacing.md),
          child: Row(
            children: [
              RelioUserAvatar(name: device.name, status: device.status),
              const SizedBox(width: RelioSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        RelioStatusChip(status: device.status, compact: true),
                        const SizedBox(width: 6),
                        _SourceBadge(label: device.isDemo ? 'DEMO' : 'REAL'),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.isDemo
                          ? stateLabel
                          : '$stableDeviceId • $stateLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (device.isDemo) ...[
                      const SizedBox(height: 3),
                      _SignalBars(quality: device.signalQuality, color: color),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

String _lastSeenLabel(DateTime? value) {
  if (value == null) return 'ไม่ทราบเวลา';
  final age = DateTime.now().difference(value);
  if (age.inMinutes < 1) return 'เมื่อครู่';
  if (age.inHours < 1) return '${age.inMinutes} นาทีที่แล้ว';
  if (age.inDays < 1) return '${age.inHours} ชั่วโมงที่แล้ว';
  return '${age.inDays} วันที่แล้ว';
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: label == 'REAL'
          ? RelioColors.primary.withValues(alpha: 0.12)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.quality, required this.color});

  final int quality;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.signal_cellular_alt_rounded, size: 15),
        const SizedBox(width: 4),
        Text(
          'สัญญาณ ${quality >= 3 ? 'ดี' : 'พอใช้'}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class RelioQuickActionCard extends StatelessWidget {
  const RelioQuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 19),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RelioChatListTile extends StatelessWidget {
  const RelioChatListTile({required this.chat, required this.onTap, super.key});

  final RelioChatPreview chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(RelioSpacing.md),
          child: Row(
            children: [
              RelioUserAvatar(name: chat.name, status: chat.status),
              const SizedBox(width: RelioSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            chat.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 7),
                        RelioStatusChip(status: chat.status, compact: true),
                        const SizedBox(width: 6),
                        _SourceBadge(label: chat.isDemo ? 'DEMO' : 'REAL'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chat.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    chat.time,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (chat.unread > 0) ...[
                    const SizedBox(height: 6),
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: RelioColors.sos,
                      child: Text(
                        '${chat.unread}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RelioMessageBubble extends StatelessWidget {
  const RelioMessageBubble({required this.message, super.key});

  final RelioMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.id == 'system') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            message.text,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      );
    }
    final bubbleColor = message.outgoing
        ? RelioColors.primary.withValues(alpha: 0.18)
        : Theme.of(context).colorScheme.surface;
    final icon = switch (message.type) {
      MessageType.image => Icons.image_outlined,
      MessageType.video => Icons.videocam_outlined,
      MessageType.location => Icons.location_on_outlined,
      MessageType.text => null,
      MessageType.system => Icons.info_outline,
    };
    return Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.type == MessageType.image &&
                message.localFilePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(message.localFilePath!),
                  width: 230,
                  height: 170,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 56),
                ),
              ),
            if (message.type == MessageType.video)
              Container(
                width: 230,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.play_circle_outline, size: 48),
              ),
            if (message.type == MessageType.location)
              Container(
                width: 230,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message.latitude == null || message.longitude == null
                      ? 'ไม่พบพิกัดล่าสุด'
                      : 'ตำแหน่งที่แชร์\n${message.latitude!.toStringAsFixed(6)}, ${message.longitude!.toStringAsFixed(6)}',
                ),
              ),
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: message.outgoing
                          ? RelioColors.primary
                          : RelioColors.rescue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      message.type.name.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            Align(alignment: Alignment.centerLeft, child: Text(message.text)),
            const SizedBox(height: 3),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 2,
              children: [
                Text(
                  message.time,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (message.status != null) ...[
                  Text(
                    message.status!.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: message.status!.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RelioLocationCard extends StatelessWidget {
  const RelioLocationCard({
    this.title = 'ตำแหน่งล่าสุด',
    this.latitude,
    this.longitude,
    this.updatedAt,
    this.accuracyMeters,
    super.key,
  });

  final String title;
  final double? latitude;
  final double? longitude;
  final DateTime? updatedAt;
  final double? accuracyMeters;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RelioSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: RelioColors.primary,
                ),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                latitude == null || longitude == null
                    ? 'ไม่พบพิกัดล่าสุด'
                    : '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}'
                          '${accuracyMeters == null ? '' : '\nความแม่นยำประมาณ ±${accuracyMeters!.toStringAsFixed(0)} ม.'}',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              updatedAt == null
                  ? 'พิกัดเป็นข้อมูลเสริมและอาจไม่มีในโหมดออฟไลน์'
                  : 'อัปเดตเมื่อ ${updatedAt!.hour.toString().padLeft(2, '0')}:${updatedAt!.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class RelioSettingTile extends StatelessWidget {
  const RelioSettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing:
            trailing ??
            (onTap == null ? null : const Icon(Icons.chevron_right_rounded)),
        minVerticalPadding: 8,
      ),
    );
  }
}

class RelioEmptyState extends StatelessWidget {
  const RelioEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RelioSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 54,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
