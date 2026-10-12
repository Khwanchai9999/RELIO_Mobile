import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

class ProfileAvatarException implements Exception {
  const ProfileAvatarException(this.message);

  final String message;

  @override
  String toString() => 'ProfileAvatarException: $message';
}

class ProfileAvatarRepository {
  ProfileAvatarRepository(this.db, {this.rootDirectory});

  final AppDatabase db;
  final Directory? rootDirectory;
  final Uuid _uuid = const Uuid();
  Future<void> _writeQueue = Future<void>.value();

  static const _settingKey = 'profile_avatar_path';
  static const maxAvatarDimension = 256;
  static const maxStoredAvatarBytes = 128 * 1024;
  static const _maxSourceBytes = 20 * 1024 * 1024;

  Future<Directory> _root() async {
    final base = rootDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      path.join(base.path, 'relio_profile', 'avatars'),
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<String?> getAvatarPath() async {
    final row = await (db.select(
      db.appSettings,
    )..where((setting) => setting.key.equals(_settingKey))).getSingleOrNull();
    final savedPath = row?.value;
    if (savedPath == null || savedPath.isEmpty) return null;
    if (await File(savedPath).exists()) return savedPath;
    await _deleteSetting();
    return null;
  }

  Future<String> storePickedImage(XFile picked) {
    final completer = Completer<String>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await _storePickedImage(picked));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<String> _storePickedImage(XFile picked) async {
    final Uint8List bytes;
    try {
      if (await picked.length() > _maxSourceBytes) {
        throw const ProfileAvatarException('ไฟล์รูปภาพมีขนาดใหญ่เกินไป');
      }
      bytes = await picked.readAsBytes();
    } on ProfileAvatarException {
      rethrow;
    } on Object {
      throw const ProfileAvatarException('อ่านรูปภาพที่เลือกไม่สำเร็จ');
    }
    if (bytes.isEmpty) {
      throw const ProfileAvatarException('ไฟล์รูปภาพว่างเปล่า');
    }

    if (!_isSupportedImage(bytes)) {
      throw const ProfileAvatarException('ไฟล์ที่เลือกไม่ใช่รูปภาพที่รองรับ');
    }
    final normalized = await _normalizeImage(bytes);

    final directory = await _root();
    final oldPath = await _savedPath();
    final fileName = '${_uuid.v4()}.png';
    final temporary = File(path.join(directory.path, '$fileName.tmp'));
    final destination = File(path.join(directory.path, fileName));
    try {
      await temporary.writeAsBytes(normalized, flush: true);
      await temporary.rename(destination.path);
      await _writeSetting(destination.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      if (await destination.exists()) await destination.delete();
      throw const ProfileAvatarException('บันทึกรูปโปรไฟล์ไม่สำเร็จ');
    }

    if (oldPath != null) await _deleteOwnedFile(oldPath, directory);
    await _removeOrphans(directory, keep: destination.path);
    return destination.path;
  }

  Future<void> removeAvatar() async {
    final directory = await _root();
    final oldPath = await _savedPath();
    await _deleteSetting();
    if (oldPath != null) await _deleteOwnedFile(oldPath, directory);
    await _removeOrphans(directory);
  }

  Future<String?> _savedPath() async {
    final row = await (db.select(
      db.appSettings,
    )..where((setting) => setting.key.equals(_settingKey))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _writeSetting(String value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _settingKey,
            value: value,
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<void> _deleteSetting() async {
    await (db.delete(
      db.appSettings,
    )..where((setting) => setting.key.equals(_settingKey))).go();
  }

  Future<void> _deleteOwnedFile(String filePath, Directory directory) async {
    final root = path.canonicalize(directory.path);
    final target = path.canonicalize(File(filePath).absolute.path);
    if (!path.isWithin(root, target)) return;
    final file = File(target);
    if (await file.exists()) await file.delete();
  }

  Future<void> _removeOrphans(Directory directory, {String? keep}) async {
    if (!await directory.exists()) return;
    for (final entity in await directory.list(followLinks: false).toList()) {
      if (entity is! File || (keep != null && entity.path == keep)) continue;
      await entity.delete();
    }
  }

  Future<Uint8List> _normalizeImage(Uint8List bytes) async {
    var source = bytes;
    for (final dimension in const [256, 192, 128, 96, 64]) {
      ui.Codec? codec;
      ui.Image? image;
      try {
        codec = await ui.instantiateImageCodec(
          source,
          targetWidth: dimension,
          targetHeight: dimension,
          allowUpscaling: false,
        );
        image = (await codec.getNextFrame()).image;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw const ProfileAvatarException('ปรับขนาดรูปโปรไฟล์ไม่สำเร็จ');
        }
        final normalized = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (normalized.lengthInBytes <= maxStoredAvatarBytes) {
          return normalized;
        }
        source = normalized;
      } on ProfileAvatarException {
        rethrow;
      } on Object {
        throw const ProfileAvatarException('ไฟล์รูปภาพอ่านไม่สำเร็จ');
      } finally {
        image?.dispose();
        codec?.dispose();
      }
    }
    throw const ProfileAvatarException('ลดขนาดรูปโปรไฟล์ให้เล็กพอไม่ได้');
  }

  bool _isSupportedImage(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return true;
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return true;
    }
    if (bytes.length >= 8 &&
        bytes.take(8).toList().join(',') ==
            const [137, 80, 78, 71, 13, 10, 26, 10].join(',')) {
      return true;
    }
    return false;
  }
}
