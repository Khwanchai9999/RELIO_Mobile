String notificationPreviewBody({
  required bool enabled,
  required String? content,
  required String fallback,
  int maxRunes = 160,
}) {
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
