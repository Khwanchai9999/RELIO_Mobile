import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';

import 'public_update_errors.dart';
import 'public_update_manifest.dart';

class AppUpdateDownloadResult {
  const AppUpdateDownloadResult({
    required this.path,
    required this.sizeBytes,
    required this.sha256,
  });

  final String path;
  final int sizeBytes;
  final String sha256;
}

abstract interface class PublicUpdateProvider {
  bool get isAvailable;

  Future<PublicQaUpdateManifest?> fetchLatest({required int currentBuild});

  Future<AppUpdateDownloadResult> download(
    PublicQaUpdateManifest manifest, {
    required Directory directory,
    required bool Function() isCancelled,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  });
}

class PublicQaUpdateProvider implements PublicUpdateProvider {
  PublicQaUpdateProvider({
    required this.manifestUri,
    required this.urlPolicy,
    HttpClient? client,
    this.diagnosticLogging = false,
  }) : _client = client ?? HttpClient();

  final Uri manifestUri;
  final PublicUpdateUrlPolicy urlPolicy;
  final bool diagnosticLogging;
  final HttpClient _client;

  @override
  bool get isAvailable => true;

  @override
  Future<PublicQaUpdateManifest?> fetchLatest({
    required int currentBuild,
  }) async {
    _log('update check start installedVersionCode=$currentBuild');
    try {
      if (!urlPolicy.isApprovedManifestUri(manifestUri)) {
        throw const PublicUpdateProviderException(
          PublicUpdateErrorCode.urlValidationError,
        );
      }
      _log('manifest request start uri=$manifestUri');
      final request = await _client.getUrl(manifestUri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      _log(
        'HTTP response status=${response.statusCode} '
        'contentType=${response.headers.contentType?.mimeType ?? 'unknown'} '
        'contentLength=${response.contentLength}',
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw PublicUpdateProviderException(
          PublicUpdateErrorCode.httpError,
          httpStatus: response.statusCode,
        );
      }
      if (response.contentLength > 1024 * 1024) {
        await response.drain<void>();
        throw const PublicUpdateProviderException('manifestTooLarge');
      }
      final body = await response.transform(utf8.decoder).join();
      _log('manifest response bytes=${utf8.encode(body).length}');
      _log('JSON decode start');
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const PublicUpdateProviderException(
          PublicUpdateErrorCode.jsonError,
        );
      }
      _log('JSON decode success; manifest validation start');
      final manifest = PublicQaUpdateManifest.fromJson(
        decoded,
        urlPolicy: urlPolicy,
      );
      _log(
        'manifest validation success remoteVersionCode=${manifest.versionCode}',
      );
      return manifest;
    } on PublicUpdateValidationException catch (error, stackTrace) {
      _logError(error.classification, error, stackTrace);
      rethrow;
    } on PublicUpdateProviderException catch (error, stackTrace) {
      _logError(
        error.code,
        error.cause ?? error,
        error.stackTrace ?? stackTrace,
      );
      rethrow;
    } on Object catch (error, stackTrace) {
      final classified = PublicUpdateProviderException.fromError(
        error,
        stackTrace,
      );
      _logError(classified.code, error, stackTrace);
      throw classified;
    }
  }

  void _log(String message) {
    if (diagnosticLogging) debugPrint('[RELIO][QA_UPDATE] $message');
  }

  void _logError(String code, Object error, StackTrace stackTrace) {
    if (!diagnosticLogging) return;
    debugPrint(
      '[RELIO][QA_UPDATE] error code=$code '
      'type=${error.runtimeType} message=$error',
    );
    if (code == PublicUpdateErrorCode.unexpectedError) {
      debugPrint('[RELIO][QA_UPDATE] stackTrace=$stackTrace');
    }
  }

  @override
  Future<AppUpdateDownloadResult> download(
    PublicQaUpdateManifest manifest, {
    required Directory directory,
    required bool Function() isCancelled,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    // ตรวจ URL, ขนาด และ SHA-256 ให้ตรง manifest ก่อนคืนไฟล์ไปยังตัวติดตั้ง
    await directory.create(recursive: true);
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path.toLowerCase().endsWith('.apk') &&
          entity.path !=
              '${directory.path}${Platform.pathSeparator}${manifest.fileName}') {
        await entity.delete();
      }
    }

    final file = File(
      '${directory.path}${Platform.pathSeparator}${manifest.fileName}',
    );
    IOSink? sink;
    try {
      if (!urlPolicy.isApprovedApkUrl(manifest.apkUrl)) {
        throw const PublicUpdateProviderException('unapprovedApkUrl');
      }
      final response = await _openApkResponse(manifest.apkUrl);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw const PublicUpdateProviderException('downloadUnavailable');
      }
      if (response.contentLength > PublicQaUpdateManifest.maxApkSizeBytes) {
        await response.drain<void>();
        throw const PublicUpdateProviderException('downloadTooLarge');
      }

      final digestSink = AccumulatorSink<Digest>();
      final digestInput = sha256.startChunkedConversion(digestSink);
      sink = file.openWrite();
      var receivedBytes = 0;
      await for (final chunk in response) {
        if (isCancelled()) {
          throw const PublicUpdateProviderException('downloadCancelled');
        }
        receivedBytes += chunk.length;
        if (receivedBytes > manifest.sizeBytes ||
            receivedBytes > PublicQaUpdateManifest.maxApkSizeBytes) {
          throw const PublicUpdateProviderException('downloadSizeMismatch');
        }
        sink.add(chunk);
        digestInput.add(chunk);
        onProgress?.call(receivedBytes, manifest.sizeBytes);
      }
      digestInput.close();
      await sink.flush();
      await sink.close();
      sink = null;

      final digest = digestSink.events.single.toString();
      if (receivedBytes != manifest.sizeBytes || digest != manifest.sha256) {
        throw const PublicUpdateProviderException('hashMismatch');
      }
      return AppUpdateDownloadResult(
        path: file.path,
        sizeBytes: receivedBytes,
        sha256: digest,
      );
    } on Object {
      await sink?.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  void close() => _client.close(force: true);

  Future<HttpClientResponse> _openApkResponse(Uri initialUri) async {
    var uri = initialUri;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final request = await _client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.android.package-archive',
      );
      final response = await request.close();
      if (response.statusCode < 300 || response.statusCode >= 400) {
        return response;
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null || redirectCount == 5) {
        throw const PublicUpdateProviderException('downloadRedirectFailed');
      }
      final nextUri = uri.resolve(location);
      if (!urlPolicy.isApprovedApkRedirect(nextUri)) {
        throw const PublicUpdateProviderException('unapprovedApkRedirect');
      }
      uri = nextUri;
    }
    throw const PublicUpdateProviderException('downloadRedirectFailed');
  }
}

class PublicUpdateProviderException implements Exception {
  const PublicUpdateProviderException(
    this.code, {
    this.cause,
    this.stackTrace,
    this.httpStatus,
  });

  factory PublicUpdateProviderException.fromError(
    Object error,
    StackTrace stackTrace,
  ) => PublicUpdateProviderException(
    classifyPublicUpdateError(error),
    cause: error,
    stackTrace: stackTrace,
  );

  final String code;
  final Object? cause;
  final StackTrace? stackTrace;
  final int? httpStatus;
}

String classifyPublicUpdateError(Object error) {
  if (error is PublicUpdateProviderException) return error.code;
  if (error is PublicUpdateValidationException) return error.classification;
  if (error is HandshakeException) return PublicUpdateErrorCode.tlsError;
  if (error is TimeoutException) return PublicUpdateErrorCode.timeoutError;
  if (error is SocketException) {
    final osErrorCode = error.osError?.errorCode;
    if (osErrorCode != null &&
        const {1, 2, 4, 7, 11001, 11002}.contains(osErrorCode)) {
      return PublicUpdateErrorCode.dnsError;
    }
    return PublicUpdateErrorCode.socketError;
  }
  if (error is FormatException) return PublicUpdateErrorCode.jsonError;
  if (error is HttpException) return PublicUpdateErrorCode.providerError;
  return PublicUpdateErrorCode.unexpectedError;
}
