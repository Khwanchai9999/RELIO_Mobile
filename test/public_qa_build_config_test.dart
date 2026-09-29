import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/app_update/public_qa_build_config.dart';

PublicQaBuildConfig _config({
  String manifestUrl = PublicQaBuildConfig.expectedManifestUrl,
  String githubOwner = PublicQaBuildConfig.expectedGithubOwner,
  String githubRepository = PublicQaBuildConfig.expectedGithubRepository,
  String channel = PublicQaBuildConfig.expectedChannel,
  bool enabled = true,
}) => PublicQaBuildConfig(
  enabled: enabled,
  manifestUrl: manifestUrl,
  githubOwner: githubOwner,
  githubRepository: githubRepository,
  channel: channel,
);

void main() {
  test('valid QA public updater configuration passes', () {
    expect(() => _config().validate(), returnsNormally);
  });

  test('empty owner fails QA configuration validation', () {
    expect(
      () => _config(githubOwner: '').validate(),
      throwsA(isA<AssertionError>()),
    );
  });

  test('wrong or empty repository fails QA configuration validation', () {
    for (final repository in ['', 'other-repository']) {
      expect(
        () => _config(githubRepository: repository).validate(),
        throwsA(isA<AssertionError>()),
      );
    }
  });

  test('missing or unapproved manifest URL fails QA configuration', () {
    for (final manifestUrl in ['', 'https://example.com/latest.json']) {
      expect(
        () => _config(manifestUrl: manifestUrl).validate(),
        throwsA(isA<AssertionError>()),
      );
    }
  });

  test('wrong channel fails QA configuration validation', () {
    expect(
      () => _config(channel: 'other-channel').validate(),
      throwsA(isA<AssertionError>()),
    );
  });

  test('disabled non-QA builds may omit public updater configuration', () {
    expect(
      () => _config(
        enabled: false,
        manifestUrl: '',
        githubOwner: '',
        githubRepository: '',
        channel: '',
      ).validate(),
      returnsNormally,
    );
  });
}
