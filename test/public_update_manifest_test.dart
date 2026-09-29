import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/app_update/public_update_manifest.dart';

const _baseUri = 'https://relio-17dc0.web.app/qa/';
const _sha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _signer =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

Map<String, dynamic> _validJson() => {
  'schemaVersion': 1,
  'channel': 'qa-public',
  'packageName': 'com.relio.relio_mobile.test',
  'versionName': '0.8.6',
  'versionCode': 12,
  'apkUrl': '${_baseUri}relio-test-0.8.6+12.apk',
  'sha256': _sha,
  'sizeBytes': 1024,
  'signingCertSha256': _signer,
  'publishedAt': '2026-09-29T10:00:00Z',
  'releaseNotes': ['Public QA update channel'],
};

void main() {
  test('parses the supported public QA manifest schema', () {
    final manifest = PublicQaUpdateManifest.fromJson(
      _validJson(),
      approvedBaseUri: Uri.parse(_baseUri),
    );

    expect(manifest.versionCode, 12);
    expect(manifest.packageName, 'com.relio.relio_mobile.test');
    expect(manifest.fileName, 'relio-test-0.8.6+12.apk');
    expect(manifest.signingCertSha256, _signer);
  });

  test('rejects unsupported schema, channel, and package', () {
    for (final change in [
      (key: 'schemaVersion', value: 2, code: 'unsupportedSchema'),
      (key: 'channel', value: 'wrong-channel', code: 'wrongChannel'),
      (key: 'packageName', value: 'com.example.other', code: 'wrongPackage'),
    ]) {
      final json = _validJson()..[change.key] = change.value;
      expect(
        () => PublicQaUpdateManifest.fromJson(
          json,
          approvedBaseUri: Uri.parse(_baseUri),
        ),
        throwsA(
          isA<PublicUpdateValidationException>().having(
            (error) => error.code,
            'code',
            change.code,
          ),
        ),
      );
    }
  });

  test('rejects HTTP, unapproved host, and unapproved path URLs', () {
    for (final url in [
      'http://relio-17dc0.web.app/qa/relio-test-0.8.6+12.apk',
      'https://example.com/qa/relio-test-0.8.6+12.apk',
      'https://relio-17dc0.web.app/other/relio-test-0.8.6+12.apk',
    ]) {
      final json = _validJson()..['apkUrl'] = url;
      expect(
        () => PublicQaUpdateManifest.fromJson(
          json,
          approvedBaseUri: Uri.parse(_baseUri),
        ),
        throwsA(
          isA<PublicUpdateValidationException>().having(
            (error) => error.code,
            'code',
            'unapprovedApkUrl',
          ),
        ),
      );
    }
  });

  test('rejects malformed hash, signer, size, and version fields', () {
    for (final change in [
      (key: 'sha256', value: 'not-a-hash', code: 'invalidSha256'),
      (
        key: 'signingCertSha256',
        value: 'not-a-signer',
        code: 'invalidSigningFingerprint',
      ),
      (key: 'sizeBytes', value: 0, code: 'invalidSizeBytes'),
      (key: 'versionName', value: 'latest', code: 'invalidVersionName'),
      (key: 'versionCode', value: 0, code: 'invalidVersionCode'),
    ]) {
      final json = _validJson()..[change.key] = change.value;
      expect(
        () => PublicQaUpdateManifest.fromJson(
          json,
          approvedBaseUri: Uri.parse(_baseUri),
        ),
        throwsA(
          isA<PublicUpdateValidationException>().having(
            (error) => error.code,
            'code',
            change.code,
          ),
        ),
      );
    }
  });
}
