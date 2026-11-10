import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../identity/owner_context.dart';
import 'principal_profile_repository.dart';

class ProfileAvatarException implements Exception {
  const ProfileAvatarException(this.message);

  final String message;

  @override
  String toString() => 'ProfileAvatarException: $message';
}

class AvatarShareArtifact {
  const AvatarShareArtifact({required this.path, required this.revision});

  final String path;
  final String revision;
}

class ProfileAvatarRepository {
  ProfileAvatarRepository(
    this.db, {
    this.rootDirectory,
    PrincipalProfileRepository? profiles,
  }) : profiles =
           profiles ?? PrincipalProfileRepository(db, OwnerContext(null));
  PrincipalProfileRepository profiles;
  void bindProfiles(PrincipalProfileRepository value) {
    profiles = value;
  }

  final AppDatabase db;
  final Directory? rootDirectory;
  final Uuid _uuid = const Uuid();
  Future<void> _writeQueue = Future<void>.value();

  static const maxAvatarDimension = 256;
  static const maxStoredAvatarBytes = 128 * 1024;
  static const maxSharedAvatarBytes = 64 * 1024;
  static const maxCachedRemoteAvatars = 100;
  static const _maxSourceBytes = 20 * 1024 * 1024;

  Future<Directory> _root(String principal) async {
    final base = rootDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      path.join(
        base.path,
        'relio_profile',
        'avatars',
        Uri.encodeComponent(principal),
      ),
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<String?> getAvatarPath() async {
    final owner = profiles.owners.capture();
    final savedPath = (await profiles.current()).avatarPath;
    profiles.owners.requireCurrent(owner);
    if (savedPath == null || savedPath.isEmpty) return null;
    final exists = await File(savedPath).exists();
    profiles.owners.requireCurrent(owner);
    return exists ? savedPath : null;
  }

  Future<String> storePickedImage(XFile picked) {
    final owner = profiles.owners.capture();
    final completer = Completer<String>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await _storePickedImage(picked, owner));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<String> _storePickedImage(XFile picked, OwnerSnapshot owner) async {
    profiles.owners.requireCurrent(owner);
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

    profiles.owners.requireCurrent(owner);
    final profile = await profiles.current();
    final directory = await _root(profile.principalId);
    final oldPath = profile.avatarPath;
    final fileName = '${_uuid.v4()}.png';
    final temporary = File(path.join(directory.path, '$fileName.tmp'));
    final destination = File(path.join(directory.path, fileName));
    try {
      await temporary.writeAsBytes(normalized, flush: true);
      await temporary.rename(destination.path);
      profiles.owners.requireCurrent(owner);
      await profiles.setAvatar(destination.path, owner);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      if (await destination.exists()) await destination.delete();
      throw const ProfileAvatarException('บันทึกรูปโปรไฟล์ไม่สำเร็จ');
    }

    if (oldPath != null) await _deleteOwnedFile(oldPath, directory);

    return destination.path;
  }

  Future<void> removeAvatar() async {
    final owner = profiles.owners.capture();
    final profile = await profiles.current();
    final directory = await _root(profile.principalId);
    profiles.owners.requireCurrent(owner);
    await profiles.setAvatar(null, owner);
    if (profile.avatarPath != null) {
      await _deleteOwnedFile(profile.avatarPath!, directory);
    }
  }

  // เตรียมภาพย่อสำหรับแชร์ avatar แยกจากภาพต้นฉบับ และจำกัดขนาดก่อนส่ง Nearby
  Future<AvatarShareArtifact?> shareArtifact() async {
    final owner = profiles.owners.capture();
    final profile = await profiles.current();
    profiles.owners.requireCurrent(owner);
    final sourcePath = profile.avatarPath;
    if (sourcePath == null || sourcePath.isEmpty) return null;
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final thumbnail = File('$sourcePath.share.png');
    final revisionFile = File('$sourcePath.share.sha256');
    if (await thumbnail.exists() && await revisionFile.exists()) {
      final size = await thumbnail.length();
      final revision = (await revisionFile.readAsString()).trim();
      if (size > 0 &&
          size <= maxSharedAvatarBytes &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(revision)) {
        return AvatarShareArtifact(path: thumbnail.path, revision: revision);
      }
    }
    final sourceBytes = await source.readAsBytes();
    Uint8List? result;
    for (final dimension in const [128, 112, 96, 80, 64]) {
      ui.Codec? codec;
      ui.Image? image;
      try {
        codec = await ui.instantiateImageCodec(
          sourceBytes,
          targetWidth: dimension,
          targetHeight: dimension,
          allowUpscaling: false,
        );
        image = (await codec.getNextFrame()).image;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) continue;
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (bytes.lengthInBytes <= maxSharedAvatarBytes) {
          result = Uint8List.fromList(bytes);
          break;
        }
      } finally {
        image?.dispose();
        codec?.dispose();
      }
    }
    if (result == null) return null;
    profiles.owners.requireCurrent(owner);
    final revision = sha256.convert(result).toString();
    final temporary = File('${thumbnail.path}.tmp');
    await temporary.writeAsBytes(result, flush: true);
    await temporary.rename(thumbnail.path);
    await revisionFile.writeAsString(revision, flush: true);
    profiles.owners.requireCurrent(owner);
    return AvatarShareArtifact(path: thumbnail.path, revision: revision);
  }

  Future<String?> remoteAvatarPath({
    required String deviceId,
    required String remotePrincipal,
  }) async {
    if (!_validRemoteKey(deviceId, remotePrincipal)) return null;
    final owner = profiles.owners.capture();
    final profile = await profiles.current();
    profiles.owners.requireCurrent(owner);
    final file = await _remoteFile(
      profile.principalId,
      remotePrincipal,
      deviceId,
    );
    final revisionFile = File('${file.path}.sha256');
    if (!await file.exists() || !await revisionFile.exists()) return null;
    if (await file.length() > maxSharedAvatarBytes) return null;
    profiles.owners.requireCurrent(owner);
    return file.path;
  }

  Future<String?> cachedRemoteRevision({
    required String deviceId,
    required String remotePrincipal,
  }) async {
    if (!_validRemoteKey(deviceId, remotePrincipal)) return null;
    final owner = profiles.owners.capture();
    final profile = await profiles.current();
    profiles.owners.requireCurrent(owner);
    final file = await _remoteFile(
      profile.principalId,
      remotePrincipal,
      deviceId,
    );
    final revisionFile = File('${file.path}.sha256');
    if (!await file.exists() || !await revisionFile.exists()) return null;
    if (await file.length() > maxSharedAvatarBytes) return null;
    final revision = (await revisionFile.readAsString()).trim();
    profiles.owners.requireCurrent(owner);
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(revision) ? revision : null;
  }

  Future<String?> storeRemoteAvatar({
    required String deviceId,
    required String remotePrincipal,
    required String revision,
    required String sourcePath,
  }) async {
    if (!_validRemoteKey(deviceId, remotePrincipal) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(revision)) {
      return null;
    }
    final owner = profiles.owners.capture();
    final input = File(sourcePath);
    if (!await input.exists()) return null;
    final length = await input.length();
    if (length == 0 || length > maxSharedAvatarBytes) return null;
    final bytes = await input.readAsBytes();
    if (sha256.convert(bytes).toString() != revision ||
        !_isSupportedImage(bytes)) {
      return null;
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
      if (image.width > 128 || image.height > 128) return null;
    } on Object {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
    final profile = await profiles.current();
    profiles.owners.requireCurrent(owner);
    final destination = await _remoteFile(
      profile.principalId,
      remotePrincipal,
      deviceId,
    );
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
    await File(
      '${destination.path}.sha256',
    ).writeAsString(revision, flush: true);
    await _pruneRemoteCache(destination.parent, destination);
    profiles.owners.requireCurrent(owner);
    return destination.path;
  }

  Future<void> _pruneRemoteCache(Directory directory, File keep) async {
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        files.add(entity);
      }
    }
    if (files.length <= maxCachedRemoteAvatars) return;
    final modified = <File, DateTime>{};
    for (final file in files.toList()) {
      modified[file] = await file.lastModified();
    }
    files.sort((a, b) => modified[a]!.compareTo(modified[b]!));
    for (final file in files.toList()) {
      if (files.length <= maxCachedRemoteAvatars) break;
      if (file.path == keep.path) continue;
      if (await file.exists()) await file.delete();
      final revisionFile = File('${file.path}.sha256');
      if (await revisionFile.exists()) await revisionFile.delete();
      files.remove(file);
    }
  }

  Future<void> removeRemoteAvatar({
    required String deviceId,
    required String remotePrincipal,
  }) async {
    if (!_validRemoteKey(deviceId, remotePrincipal)) return;
    final owner = profiles.owners.capture();
    final profile = await profiles.current();
    profiles.owners.requireCurrent(owner);
    final file = await _remoteFile(
      profile.principalId,
      remotePrincipal,
      deviceId,
    );
    for (final candidate in [file, File('${file.path}.sha256')]) {
      if (await candidate.exists()) await candidate.delete();
    }
    profiles.owners.requireCurrent(owner);
  }

  bool _validRemoteKey(String deviceId, String remotePrincipal) =>
      deviceId.isNotEmpty &&
      deviceId.length <= 128 &&
      RegExp(r'^(account|guest):[a-zA-Z0-9_-]+$').hasMatch(remotePrincipal) &&
      remotePrincipal.length <= 160;

  Future<File> _remoteFile(
    String principalId,
    String remotePrincipal,
    String deviceId,
  ) async {
    final peerKey = sha256
        .convert(utf8.encode('$remotePrincipal\u0000$deviceId'))
        .toString();
    final base = rootDirectory ?? await getApplicationSupportDirectory();
    return File(
      path.join(
        base.path,
        'relio_profile',
        'avatars',
        Uri.encodeComponent(principalId),
        'nearby',
        '$peerKey.png',
      ),
    );
  }

  Future<void> _deleteOwnedFile(String filePath, Directory directory) async {
    final root = path.canonicalize(directory.path);
    final target = path.canonicalize(File(filePath).absolute.path);
    if (!path.isWithin(root, target)) return;
    for (final candidate in [
      File(target),
      File('$target.share.png'),
      File('$target.share.sha256'),
    ]) {
      if (await candidate.exists()) await candidate.delete();
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
