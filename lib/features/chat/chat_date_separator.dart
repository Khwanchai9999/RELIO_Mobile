import 'package:flutter/material.dart';

const _thaiMonths = <String>[
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
];

DateTime _localDay(DateTime date) {
  final local = date.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}

String formatChatDateSeparator(DateTime date, {DateTime? now}) {
  final localDate = date.toLocal();
  final today = _localDay(now ?? DateTime.now());
  final day = _localDay(localDate);
  final difference = today.difference(day).inDays;
  final formatted =
      '${localDate.day} ${_thaiMonths[localDate.month - 1]} '
      '${localDate.year + 543}';
  if (difference == 0) return 'วันนี้ · $formatted';
  if (difference == 1) return 'เมื่อวาน · $formatted';
  return formatted;
}

bool shouldShowChatDateSeparator(DateTime? current, DateTime? previous) {
  if (current == null) return false;
  if (previous == null) return true;
  return _localDay(current) != _localDay(previous);
}

class ChatDateSeparator extends StatelessWidget {
  const ChatDateSeparator({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = formatChatDateSeparator(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: colors.outlineVariant, height: 1)),
          const SizedBox(width: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant, width: 0.5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: colors.outlineVariant, height: 1)),
        ],
      ),
    );
  }
}
