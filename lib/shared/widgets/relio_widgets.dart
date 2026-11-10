import 'dart:io';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/media/media_preview_layout.dart';
import '../../core/presentation/avatar_appearance.dart';
import '../../core/presentation/peer_connection_presence.dart';
import '../../core/relio_dependencies.dart';
import '../../data/models/prototype_models.dart';

// รวม widget ที่ใช้ซ้ำและผูกกับ semantic tokens ของ RELIO
// หน้าฟีเจอร์จึงใช้รูปแบบและสถานะที่เข้าถึงได้อย่างสม่ำเสมอ
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
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
    this.identityKey = '',
    this.imagePath,
    this.presence = PeerConnectionPresence.unknown,
    super.key,
  });

  final String name;
  final double size;
  final DeviceStatus? status;
  final String identityKey;
  final String? imagePath;
  final PeerConnectionPresence presence;

  @override
  Widget build(BuildContext context) {
    final baseColor = AvatarAppearanceResolver.colorFor(identityKey);
    final color = AvatarAppearanceResolver.displayColor(baseColor, presence);
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
          child: ClipOval(
            child: imagePath == null || imagePath!.isEmpty
                ? Semantics(
                    image: true,
                    label: name,
                    child: Icon(
                      Icons.person_rounded,
                      size: size * 0.62,
                      color: color,
                    ),
                  )
                : Image.file(
                    File(imagePath!),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.person_rounded,
                      size: size * 0.62,
                      color: color,
                    ),
                  ),
          ),
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

class RelioPrincipalAvatar extends StatelessWidget {
  const RelioPrincipalAvatar({
    required this.name,
    required this.imagePath,
    this.size = 68,
    super.key,
  });

  final String name;
  final String? imagePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cleaned = name.trim();
    final initial = cleaned.isEmpty
        ? null
        : String.fromCharCode(cleaned.runes.first);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: RelioColors.primary.withValues(alpha: 0.14),
        border: Border.all(color: RelioColors.primary, width: 1.5),
      ),
      child: initial == null
          ? Icon(
              Icons.person_rounded,
              size: size * 0.58,
              color: RelioColors.primary,
            )
          : Text(
              initial,
              style: TextStyle(
                fontSize: size * 0.48,
                fontWeight: FontWeight.w700,
                color: RelioColors.primary,
              ),
            ),
    );
    if (imagePath == null || imagePath!.isEmpty) return fallback;
    return ClipOval(
      child: Image.file(
        File(imagePath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
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
  const RelioDeviceCard({
    required this.device,
    this.peerIdentifier,
    this.onTap,
    this.showBattery = true,
    super.key,
  });

  final RelioDevice device;
  final String? peerIdentifier;
  final VoidCallback? onTap;
  final bool showBattery;

  @override
  Widget build(BuildContext context) {
    final color = device.status.color;
    final stateLabel = switch (device.presence) {
      PeerPresence.demo => 'ตัวอย่าง • ${device.approximateDistance}',
      PeerPresence.discovered => 'ค้นพบ Nearby',
      PeerPresence.connecting => 'กำลังเชื่อมต่อ',
      PeerPresence.connected => 'เชื่อมต่อแล้ว',
      PeerPresence.disconnected => 'ขาดการเชื่อมต่อ',
      PeerPresence.failed => 'เชื่อมต่อไม่สำเร็จ',
      PeerPresence.stale => 'พบล่าสุด ${_lastSeenLabel(device.lastSeenAt)}',
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
              RelioUserAvatar(
                name: device.name,
                identityKey: device.id,
                status: device.status,
                presence: device.connectionPresence,
                imagePath: device.avatarPath,
              ),
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
                        if (device.isDemo ||
                            device.status == DeviceStatus.sos ||
                            device.status == DeviceStatus.rescue)
                          RelioStatusChip(status: device.status, compact: true),
                        const Spacer(),
                        if (device.isDemo)
                          const _SourceBadge(label: 'DEMO')
                        else
                          RelioPresenceChip(
                            presence: device.connectionPresence,
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.isDemo
                          ? stateLabel
                          : '${peerIdentifier ?? stableDeviceId} • $stateLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (showBattery &&
                        !device.isDemo &&
                        device.batteryLevel != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${device.isCharging == true ? '⚡ ' : '🔋 '}${device.batteryLevel}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: device.batteryLevel! <= 15
                              ? RelioColors.warning
                              : null,
                        ),
                      ),
                    ],
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

class RelioPresenceChip extends StatelessWidget {
  const RelioPresenceChip({required this.presence, super.key});

  final PeerConnectionPresence presence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (presence) {
      PeerConnectionPresence.online => ('ออนไลน์', RelioColors.success),
      PeerConnectionPresence.offline => ('ออฟไลน์', RelioColors.offline),
      PeerConnectionPresence.unknown => ('ยังไม่ทราบสถานะ', RelioColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
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
              RelioUserAvatar(
                name: chat.name,
                identityKey: chat.identityKey,
                status: chat.status,
                presence: chat.presence,
                imagePath: chat.avatarPath,
              ),
              const SizedBox(width: RelioSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      children: [
                        RelioPresenceChip(presence: chat.presence),
                        if (chat.isDemo) const _SourceBadge(label: 'DEMO'),
                      ],
                    ),
                    const SizedBox(height: 2),
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
  const RelioMessageBubble({
    required this.message,
    this.onOpenLocation,
    super.key,
  });

  final RelioMessage message;
  final VoidCallback? onOpenLocation;

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
    final colors = Theme.of(context).colorScheme;
    final bubbleColor = message.outgoing
        ? const Color(0xFFD9F7F1)
        : const Color(0xFFF0F3F7);
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
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: message.outgoing
                ? RelioColors.primary.withValues(alpha: 0.32)
                : colors.outlineVariant.withValues(alpha: 0.48),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.type == MessageType.image)
              _ImageMessagePreview(filePath: message.localFilePath),
            if (message.type == MessageType.video)
              _VideoMessagePreview(filePath: message.localFilePath),
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
            if (message.type == MessageType.location)
              Semantics(
                button: true,
                label: 'เปิดดูตำแหน่งที่แชร์ในแผนที่',
                child: TextButton.icon(
                  onPressed: onOpenLocation,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('เปิดดูตำแหน่ง'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            if (icon != null && message.type == MessageType.location)
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
            if (message.type == MessageType.text ||
                message.type == MessageType.location)
              Text(message.text),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              widthFactor: 1,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  Text(
                    message.time,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (message.outgoing && message.readAt != null)
                    _MessageStatus(
                      label: 'อ่านแล้ว',
                      color: RelioColors.success,
                      icon: Icons.done_all_rounded,
                    )
                  else if (message.outgoing &&
                      message.status != null &&
                      message.status != DeliveryStatus.synced)
                    _deliveryStatus(message.status!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _deliveryStatus(DeliveryStatus status) {
  final (label, color, icon) = switch (status) {
    DeliveryStatus.pending => (
      'รอส่ง',
      RelioColors.warning,
      Icons.schedule_rounded,
    ),
    DeliveryStatus.nearbySent => (
      'ส่งออกแล้ว',
      RelioColors.rescue,
      Icons.done_rounded,
    ),
    DeliveryStatus.delivered => (
      'ถึงผู้รับแล้ว',
      RelioColors.rescue,
      Icons.done_all_rounded,
    ),
    DeliveryStatus.synced => (
      'ซิงก์แล้ว',
      RelioColors.muted,
      Icons.cloud_done_outlined,
    ),
    DeliveryStatus.failed => (
      'ส่งไม่สำเร็จ',
      RelioColors.sos,
      Icons.error_outline_rounded,
    ),
  };
  return _MessageStatus(label: label, color: color, icon: icon);
}

class _MessageStatus extends StatelessWidget {
  const _MessageStatus({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 2),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _VideoMessagePreview extends StatefulWidget {
  const _VideoMessagePreview({required this.filePath});

  final String? filePath;

  @override
  State<_VideoMessagePreview> createState() => _VideoMessagePreviewState();
}

class _VideoMessagePreviewState extends State<_VideoMessagePreview> {
  static const _channel = MethodChannel('relio/media');
  static const _cacheLimit = 64;
  static final LinkedHashMap<String, Future<Map<Object?, Object?>?>> _pending =
      LinkedHashMap();
  Future<Map<Object?, Object?>?>? _thumbnail;

  Future<Map<Object?, Object?>?> _loadThumbnail(BuildContext context) async {
    final path = widget.filePath;
    if (path == null || path.isEmpty) return null;
    final dependencies = context
        .getInheritedWidgetOfExactType<RelioDependencyScope>()
        ?.dependencies;
    final file = File(path);
    late final int sizeBytes;
    late final DateTime modifiedAt;
    try {
      sizeBytes = await file.length();
      modifiedAt = await file.lastModified();
    } on FileSystemException {
      return null;
    }
    final cacheKey = '$path:$sizeBytes:${modifiedAt.microsecondsSinceEpoch}';
    final cached = _pending.remove(cacheKey);
    if (cached != null) {
      _pending[cacheKey] = cached;
      dependencies?.diagnostics.record(
        'media',
        'video_thumbnail_cache_hit',
        fields: {'requestCacheHit': true, 'sizeBytes': sizeBytes},
      );
      return cached;
    }
    final clock = Stopwatch()..start();
    dependencies?.diagnostics.record(
      'media',
      'video_thumbnail_generation_started',
      fields: {'requestCacheHit': false, 'sizeBytes': sizeBytes},
    );
    final future = (() async {
      try {
        final result = await _channel.invokeMapMethod<Object?, Object?>(
          'videoThumbnail',
          {'path': path, 'cacheKey': cacheKey},
        );
        dependencies?.diagnostics.record(
          'media',
          'video_thumbnail_generation_completed',
          fields: {
            'durationMs': clock.elapsedMilliseconds,
            'cacheHit': result?['cacheHit'] == true,
            'sizeBytes': sizeBytes,
            'resultAvailable': result != null,
          },
        );
        if (result == null) _pending.remove(cacheKey);
        return result;
      } on PlatformException {
        dependencies?.diagnostics.record(
          'media',
          'video_thumbnail_generation_failed',
          fields: {'durationMs': clock.elapsedMilliseconds},
        );
        _pending.remove(cacheKey);
        return null;
      }
    })();
    _pending[cacheKey] = future;
    while (_pending.length > _cacheLimit) {
      _pending.remove(_pending.keys.first);
    }
    return future;
  }

  @override
  void didUpdateWidget(covariant _VideoMessagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _thumbnail = null;
    }
  }

  Future<void> _open(BuildContext context) async {
    final path = widget.filePath;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบไฟล์วิดีโอในเครื่อง')),
        );
      }
      return;
    }
    try {
      await _channel.invokeMethod<void>('playLocalVideo', {'path': path});
    } on PlatformException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเปิดวิดีโอนี้ได้')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _thumbnail ??= _loadThumbnail(context);
    return Tooltip(
      message: 'เล่นวิดีโอ',
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<Map<Object?, Object?>?>(
          future: _thumbnail,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final thumbPath = data?['path'] as String?;
            final width = (data?['width'] as num?)?.toDouble() ?? 5.0;
            final height = (data?['height'] as num?)?.toDouble() ?? 3.0;
            final size = fitMediaPreviewSize(
              Size(width, height),
              const Size(280, 360),
            );
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    if (thumbPath != null)
                      Image.file(
                        File(thumbPath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    const Center(
                      child: Icon(Icons.play_circle_outline, size: 58),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ImageMessagePreview extends StatefulWidget {
  const _ImageMessagePreview({required this.filePath});

  final String? filePath;

  @override
  State<_ImageMessagePreview> createState() => _ImageMessagePreviewState();
}

class _ImageMessagePreviewState extends State<_ImageMessagePreview> {
  @override
  Widget build(BuildContext context) {
    final path = widget.filePath;
    if (path == null || path.isEmpty) return _missingImage();
    return Tooltip(
      message: 'เปิดรูปภาพเต็มจอ',
      child: InkWell(
        onTap: () => _showViewer(context, path),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth.clamp(1.0, 280.0).toDouble()
                  : 280.0;
              final pixelRatio = MediaQuery.devicePixelRatioOf(context);
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 360),
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  cacheWidth: (560 * pixelRatio).round(),
                  cacheHeight: (720 * pixelRatio).round(),
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (frame != null || wasSynchronouslyLoaded) {
                          return child;
                        }
                        return SizedBox(
                          width: 180,
                          height: 108,
                          child: ColoredBox(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                        );
                      },
                  errorBuilder: (_, _, _) => _missingImage(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _missingImage() => const SizedBox(
    width: 180,
    height: 108,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image_outlined, size: 36),
        SizedBox(height: 4),
        Text('ไม่พบไฟล์รูปภาพ'),
      ],
    ),
  );

  Future<void> _showViewer(BuildContext context, String path) async {
    final owners = context
        .getInheritedWidgetOfExactType<RelioDependencyScope>()
        ?.dependencies
        .repositories
        .ownerContext;
    final owner = owners?.capture();
    final fileExists = await File(path).exists();
    if (!context.mounted) return;
    if (owners != null && !owners.isCurrent(owner!)) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StreamBuilder<Object?>(
        stream: owners?.changes,
        builder: (context, _) {
          if (owners != null && !owners.isCurrent(owner!)) {
            return const SizedBox.shrink();
          }
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(dialogContext).width - 32,
                    maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.8,
                  ),
                  child: fileExists
                      ? InteractiveViewer(
                          child: Image.file(
                            File(path),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('ไม่สามารถเปิดรูปภาพนี้ได้'),
                            ),
                          ),
                        )
                      : const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('ไม่สามารถเปิดรูปภาพนี้ได้'),
                        ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'ปิดรูปภาพ',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          );
        },
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
    this.freshnessLabel,
    this.accuracyMeters,
    super.key,
  });

  final String title;
  final double? latitude;
  final double? longitude;
  final DateTime? updatedAt;
  final String? freshnessLabel;
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
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
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
              freshnessLabel ??
                  (updatedAt == null
                      ? 'พิกัดเป็นข้อมูลเสริมและอาจไม่มีในโหมดออฟไลน์'
                      : 'อัปเดตเมื่อ ${updatedAt!.hour.toString().padLeft(2, '0')}:${updatedAt!.minute.toString().padLeft(2, '0')}'),
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
