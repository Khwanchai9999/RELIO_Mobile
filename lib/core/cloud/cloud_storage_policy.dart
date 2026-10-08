// บังคับ path ให้ผูกกับเจ้าของก่อนส่งไฟล์ เพื่อให้ตรงกับกฎ RLS/Storage
abstract final class CloudStoragePathPolicy {
  static const bucket = 'relio-media';

  static String forAttachment({
    required String userId,
    required String messageId,
    required String attachmentId,
    required String fileName,
  }) {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return 'users/$userId/messages/$messageId/$attachmentId-$safeName';
  }

  static bool isOwnedBy(String storagePath, String userId) {
    final segments = storagePath.split('/');
    if (segments.length != 5 || segments[0] != 'users') return false;
    if (segments[1] != userId || segments[2] != 'messages') return false;
    if (segments[3].isEmpty || segments[4].isEmpty) return false;
    if (storagePath.contains('..') || storagePath.contains('\\')) return false;
    return segments.every(_isSafeSegment);
  }

  static bool _isSafeSegment(String segment) =>
      segment.isNotEmpty &&
      !segment.contains(RegExp(r'[\x00-\x1f\x7f]')) &&
      segment != '.' &&
      segment != '..';
}
