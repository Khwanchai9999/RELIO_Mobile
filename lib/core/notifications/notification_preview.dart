String notificationPreviewBody({
  required bool enabled,
  required String? content,
  required String fallback,
  int maxRunes = 160,
}) {
  // ใช้ข้อความทั่วไปเมื่อผู้ใช้ปิด preview เพื่อไม่เผยเนื้อหาข้อความในการแจ้งเตือน
  if (!enabled || content == null || maxRunes < 1) return fallback;
  final normalized = content
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) return fallback;
  final runes = normalized.runes;
  if (runes.length <= maxRunes) return normalized;
  return '${String.fromCharCodes(runes.take(maxRunes - 1))}…';
}
