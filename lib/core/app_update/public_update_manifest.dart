class PublicUpdateValidationException implements Exception {
  const PublicUpdateValidationException(this.code);

  final String code;

  @override
  String toString() => 'Public update manifest validation failed: $code';
}

class PublicQaUpdateManifest {
  const PublicQaUpdateManifest({
    required this.schemaVersion,
    required this.channel,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.signingCertSha256,
    required this.publishedAt,
    required this.releaseNotes,
  });

  static const supportedSchemaVersion = 1;
  static const expectedChannel = 'qa-public';
  static const expectedPackageName = 'com.relio.relio_mobile.test';
  static const maxApkSizeBytes = 200 * 1024 * 1024;

  final int schemaVersion;
  final String channel;
  final String packageName;
  final String versionName;
  final int versionCode;
  final Uri apkUrl;
  final String sha256;
  final int sizeBytes;
  final String signingCertSha256;
  final DateTime publishedAt;
  final List<String> releaseNotes;

  String get fileName => apkUrl.pathSegments.last;

  factory PublicQaUpdateManifest.fromJson(
    Map<String, dynamic> json, {
    required Uri approvedBaseUri,
  }) {
    final schemaVersion = _intValue(json['schemaVersion'], 'schemaVersion');
    if (schemaVersion != supportedSchemaVersion) {
      throw const PublicUpdateValidationException('unsupportedSchema');
    }
    final channel = _stringValue(json['channel'], 'channel');
    if (channel != expectedChannel) {
      throw const PublicUpdateValidationException('wrongChannel');
    }
    final packageName = _stringValue(json['packageName'], 'packageName');
    if (packageName != expectedPackageName) {
      throw const PublicUpdateValidationException('wrongPackage');
    }

    final versionName = _stringValue(json['versionName'], 'versionName');
    if (!RegExp(
      r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$',
    ).hasMatch(versionName)) {
      throw const PublicUpdateValidationException('invalidVersionName');
    }

    final versionCode = _intValue(json['versionCode'], 'versionCode');
    if (versionCode <= 0) {
      throw const PublicUpdateValidationException('invalidVersionCode');
    }

    final apkUrl = Uri.tryParse(_stringValue(json['apkUrl'], 'apkUrl'));
    if (apkUrl == null || !_isApprovedApkUrl(apkUrl, approvedBaseUri)) {
      throw const PublicUpdateValidationException('unapprovedApkUrl');
    }

    final sha256 = _stringValue(json['sha256'], 'sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const PublicUpdateValidationException('invalidSha256');
    }

    final sizeBytes = _intValue(json['sizeBytes'], 'sizeBytes');
    if (sizeBytes <= 0 || sizeBytes > maxApkSizeBytes) {
      throw const PublicUpdateValidationException('invalidSizeBytes');
    }

    final signingCertSha256 = _normaliseFingerprint(
      _stringValue(json['signingCertSha256'], 'signingCertSha256'),
    );
    if (signingCertSha256 == null) {
      throw const PublicUpdateValidationException('invalidSigningFingerprint');
    }

    final publishedAtValue = _stringValue(json['publishedAt'], 'publishedAt');
    final publishedAt = DateTime.tryParse(publishedAtValue)?.toUtc();
    if (publishedAt == null) {
      throw const PublicUpdateValidationException('invalidPublishedAt');
    }

    final rawNotes = json['releaseNotes'];
    if (rawNotes is! List || rawNotes.length > 20) {
      throw const PublicUpdateValidationException('invalidReleaseNotes');
    }
    final releaseNotes = <String>[];
    for (final note in rawNotes) {
      if (note is! String || note.trim().isEmpty || note.length > 500) {
        throw const PublicUpdateValidationException('invalidReleaseNotes');
      }
      releaseNotes.add(note.trim());
    }

    return PublicQaUpdateManifest(
      schemaVersion: schemaVersion,
      channel: channel,
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: apkUrl,
      sha256: sha256,
      sizeBytes: sizeBytes,
      signingCertSha256: signingCertSha256,
      publishedAt: publishedAt,
      releaseNotes: List.unmodifiable(releaseNotes),
    );
  }

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'channel': channel,
    'packageName': packageName,
    'versionName': versionName,
    'versionCode': versionCode,
    'apkUrl': apkUrl.toString(),
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'signingCertSha256': signingCertSha256,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'releaseNotes': releaseNotes,
  };

  static bool _isApprovedApkUrl(Uri actual, Uri approvedBaseUri) {
    final expectedPath = approvedBaseUri.path.endsWith('/')
        ? approvedBaseUri.path
        : '${approvedBaseUri.path}/';
    final actualPort = actual.hasPort ? actual.port : 443;
    final expectedPort = approvedBaseUri.hasPort ? approvedBaseUri.port : 443;
    return actual.scheme.toLowerCase() == 'https' &&
        actual.host.toLowerCase() == approvedBaseUri.host.toLowerCase() &&
        actualPort == expectedPort &&
        actual.query.isEmpty &&
        actual.fragment.isEmpty &&
        actual.path.startsWith(expectedPath) &&
        actual.pathSegments.last.endsWith('.apk');
  }

  static String _stringValue(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw PublicUpdateValidationException('invalid$field');
    }
    return value.trim();
  }

  static int _intValue(Object? value, String field) {
    if (value is! int || value is bool) {
      throw PublicUpdateValidationException('invalid$field');
    }
    return value;
  }

  static String? _normaliseFingerprint(String value) {
    final compact = value.replaceAll(':', '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(compact)) return null;
    return compact;
  }
}
