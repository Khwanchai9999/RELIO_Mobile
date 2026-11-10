import 'public_update_errors.dart';

// ตรวจ manifest และ URL ของ public QA updater ตาม allowlist ที่กำหนด
// การมี manifest เพียงอย่างเดียวไม่พอ ต้องตรวจ asset, version และ hash ก่อนส่งให้ installer
class PublicUpdateValidationException implements Exception {
  const PublicUpdateValidationException(this.code);

  final String code;

  String get classification => code == 'unapprovedApkUrl'
      ? PublicUpdateErrorCode.urlValidationError
      : PublicUpdateErrorCode.manifestValidationError;

  @override
  String toString() => 'Public update manifest validation failed: $code';
}

// จำกัด manifest และ asset ไว้ที่ origin ที่อนุมัติ ไม่เชื่อ URL จากข้อมูลภายนอกโดยตรง
class PublicUpdateUrlPolicy {
  const PublicUpdateUrlPolicy({
    required this.manifestUri,
    required this.githubOwner,
    this.githubRepository = defaultGithubRepository,
    this.channel = defaultChannel,
  });

  static const defaultGithubRepository = 'RELIO-Android-Updates';
  static const defaultChannel = 'qa-public';
  static final _approvedManifestUri = Uri.parse(
    'https://relio-17dc0.web.app/qa/latest.json',
  );

  final Uri manifestUri;
  final String githubOwner;
  final String githubRepository;
  final String channel;

  Uri get githubReleaseBaseUri => Uri.parse(
    'https://github.com/$githubOwner/$githubRepository/releases/download/',
  );

  bool isApprovedManifestUri(Uri actual) =>
      _sameUri(actual, manifestUri) && _sameUri(actual, _approvedManifestUri);

  bool isApprovedApkUrl(Uri actual) {
    final segments = actual.pathSegments;
    return actual.scheme.toLowerCase() == 'https' &&
        actual.host.toLowerCase() == 'github.com' &&
        !actual.hasPort &&
        actual.userInfo.isEmpty &&
        actual.query.isEmpty &&
        actual.fragment.isEmpty &&
        githubOwner.isNotEmpty &&
        segments.length == 6 &&
        segments[0] == githubOwner &&
        segments[1] == githubRepository &&
        segments[2] == 'releases' &&
        segments[3] == 'download' &&
        segments[4].isNotEmpty &&
        segments[5].endsWith('.apk');
  }

  bool isApprovedApkRedirect(Uri actual) {
    final host = actual.host.toLowerCase();
    return actual.scheme.toLowerCase() == 'https' &&
        actual.userInfo.isEmpty &&
        !actual.hasPort &&
        (host == 'github.com' ||
            host == 'release-assets.githubusercontent.com' ||
            host == 'objects.githubusercontent.com');
  }

  static bool _sameUri(Uri actual, Uri expected) =>
      actual.scheme.toLowerCase() == expected.scheme.toLowerCase() &&
      actual.host.toLowerCase() == expected.host.toLowerCase() &&
      actual.port == expected.port &&
      actual.userInfo.isEmpty &&
      actual.query.isEmpty &&
      actual.fragment.isEmpty &&
      actual.path == expected.path;
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
  static const expectedChannel = PublicUpdateUrlPolicy.defaultChannel;
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
    required PublicUpdateUrlPolicy urlPolicy,
  }) {
    final schemaVersion = _intValue(json['schemaVersion'], 'schemaVersion');
    if (schemaVersion != supportedSchemaVersion) {
      throw const PublicUpdateValidationException('unsupportedSchema');
    }
    final channel = _stringValue(json['channel'], 'channel');
    if (channel != urlPolicy.channel) {
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
    if (apkUrl == null || !urlPolicy.isApprovedApkUrl(apkUrl)) {
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
