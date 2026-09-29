import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

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
  }) : _client = client ?? HttpClient();

  final Uri manifestUri;
  final PublicUpdateUrlPolicy urlPolicy;
  final HttpClient _client;

  @override
  bool get isAvailable => true;

  @override
  Future<PublicQaUpdateManifest?> fetchLatest({
    required int currentBuild,
  }) async {
    if (!urlPolicy.isApprovedManifestUri(manifestUri)) {
      throw const PublicUpdateProviderException('manifestUrlNotApproved');
    }
    final request = await _client.getUrl(manifestUri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw const PublicUpdateProviderException('manifestUnavailable');
    }
    if (response.contentLength > 1024 * 1024) {
      await response.drain<void>();
      throw const PublicUpdateProviderException('manifestTooLarge');
    }
    final body = await response.transform(utf8.decoder).join();
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const PublicUpdateValidationException('manifestNotObject');
      }
      return PublicQaUpdateManifest.fromJson(decoded, urlPolicy: urlPolicy);
    } on PublicUpdateValidationException {
      rethrow;
    } on Object {
      throw const PublicUpdateProviderException('manifestMalformed');
    }
  }

  @override
  Future<AppUpdateDownloadResult> download(
    PublicQaUpdateManifest manifest, {
    required Directory directory,
    required bool Function() isCancelled,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
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
  const PublicUpdateProviderException(this.code);

  final String code;
}
