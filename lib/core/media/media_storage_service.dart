import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class MediaValidationResult {
  const MediaValidationResult({
    required this.mimeType,
    required this.mediaType,
    required this.byteSize,
  });

  final String mimeType;
  final String mediaType;
  final int byteSize;
}

class MediaStorageException implements Exception {
  const MediaStorageException(this.message);
  final String message;

  @override
  String toString() => 'MediaStorageException: $message';
}

class MediaTransferPolicy {
  const MediaTransferPolicy({
    this.maxImageBytes = 15 * 1024 * 1024,
    this.maxVideoBytes = 100 * 1024 * 1024,
  });

  final int maxImageBytes;
  final int maxVideoBytes;

  int maxFor(String mediaType) =>
      mediaType == 'video' ? maxVideoBytes : maxImageBytes;
}

class MediaStorageService {
  MediaStorageService({
    this.rootDirectory,
    this.policy = const MediaTransferPolicy(),
  });

  final Directory? rootDirectory;
  final MediaTransferPolicy policy;
  final _uuid = const Uuid();

  Future<Directory> _root() async {
    final root =
        rootDirectory ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'relio_media',
          ),
        );
    if (!root.existsSync()) await root.create(recursive: true);
    return root;
  }

  Future<MediaValidationResult> validateFile(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw const MediaStorageException('ไม่พบไฟล์สื่อที่เลือก');
    }
    final size = await file.length();
    if (size <= 0) throw const MediaStorageException('ไฟล์สื่อว่างเปล่า');
    final bytes = await _readHeader(file);
    final detected = lookupMimeType(sourcePath, headerBytes: bytes);
    final mediaType = _mediaTypeFor(detected);
    if (mediaType == null || detected == null) {
      throw const MediaStorageException('ไม่รองรับชนิดไฟล์นี้');
    }
    if (size > policy.maxFor(mediaType)) {
      throw MediaStorageException(
        mediaType == 'video'
            ? 'วิดีโอมีขนาดเกิน ${_mb(policy.maxVideoBytes)} MB'
            : 'รูปภาพมีขนาดเกิน ${_mb(policy.maxImageBytes)} MB',
      );
    }
    if (!_matchesSignature(mediaType, detected, bytes)) {
      throw const MediaStorageException('เนื้อหาไฟล์ไม่ตรงกับชนิดไฟล์');
    }
    return MediaValidationResult(
      mimeType: detected,
      mediaType: mediaType,
      byteSize: size,
    );
  }

  Future<String> copySelectedFile(String sourcePath) async {
    final validation = await validateFile(sourcePath);
    final root = await _root();
    final extension = _extensionFor(validation.mimeType, sourcePath);
    final destination = File(path.join(root.path, '${_uuid.v4()}$extension'));
    await File(sourcePath).copy(destination.path);
    return destination.path;
  }

  Future<String> storeIncomingFile({
    required String sourcePath,
    required String fileName,
    required String expectedMimeType,
    required int expectedBytes,
  }) async {
    final validation = await validateFile(sourcePath);
    if (validation.mimeType != expectedMimeType ||
        validation.byteSize != expectedBytes) {
      throw const MediaStorageException('ไฟล์ที่ได้รับไม่ตรงกับ metadata');
    }
    final root = await _root();
    final extension = _extensionFor(validation.mimeType, fileName);
    final destination = File(path.join(root.path, '${_uuid.v4()}$extension'));
    await File(sourcePath).copy(destination.path);
    return destination.path;
  }

  /// Stores bytes returned by a cloud adapter without exposing filesystem
  /// details to the UI or cloud implementation.
  Future<String> storeDownloadedBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (bytes.isEmpty) {
      throw const MediaStorageException('ไฟล์ที่ดาวน์โหลดว่างเปล่า');
    }
    final mediaType = _mediaTypeFor(mimeType);
    if (mediaType == null || bytes.length > policy.maxFor(mediaType)) {
      throw const MediaStorageException(
        'ไฟล์ที่ดาวน์โหลดไม่รองรับหรือมีขนาดเกินกำหนด',
      );
    }
    final root = await _root();
    final destination = File(
      path.join(root.path, '${_uuid.v4()}${_extensionFor(mimeType, fileName)}'),
    );
    await destination.writeAsBytes(bytes, flush: true);
    return destination.path;
  }

  Future<bool> fileExists(String filePath) => File(filePath).exists();

  Future<void> deleteManagedFile(String filePath) async {
    final root = await _root();
    final file = File(filePath);
    final rootPath = path.canonicalize(root.path);
    final fileCanonical = path.canonicalize(file.path);
    if (!path.isWithin(rootPath, fileCanonical)) return;
    if (await file.exists()) await file.delete();
  }

  Future<Uint8List> _readHeader(File file) async {
    final handle = await file.open();
    try {
      return await handle.read(64);
    } finally {
      await handle.close();
    }
  }

  String? _mediaTypeFor(String? mimeType) {
    if (mimeType == 'image/jpeg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/webp') {
      return 'image';
    }
    if (mimeType == 'video/mp4' || mimeType == 'video/quicktime') {
      return 'video';
    }
    return null;
  }

  bool _matchesSignature(String mediaType, String mimeType, Uint8List bytes) {
    if (mediaType == 'image' && mimeType == 'image/jpeg') {
      return bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8;
    }
    if (mediaType == 'image' && mimeType == 'image/png') {
      return bytes.length >= 8 &&
          bytes.take(8).toList().join(',') ==
              const [137, 80, 78, 71, 13, 10, 26, 10].join(',');
    }
    if (mediaType == 'image' && mimeType == 'image/webp') {
      return bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    }
    if (mediaType == 'video') {
      return bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp';
    }
    return false;
  }

  String _extensionFor(String mimeType, String source) => switch (mimeType) {
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'image/webp' => '.webp',
    'video/mp4' => '.mp4',
    'video/quicktime' => '.mov',
    _ => path.extension(source).replaceAll(RegExp(r'[^a-zA-Z0-9.]'), ''),
  };

  int _mb(int bytes) => (bytes / (1024 * 1024)).ceil();
}
