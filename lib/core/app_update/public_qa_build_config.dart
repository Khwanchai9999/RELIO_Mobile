/// Compile-time settings required by the public QA update channel.
class PublicQaBuildConfig {
  const PublicQaBuildConfig({
    required this.enabled,
    required this.manifestUrl,
    required this.githubOwner,
    required this.githubRepository,
    required this.channel,
  }) : assert(
         !enabled || manifestUrl == expectedManifestUrl,
         'QA public update manifest URL is missing or unapproved.',
       ),
       assert(
         !enabled || githubOwner == expectedGithubOwner,
         'QA public update GitHub owner is missing or unapproved.',
       ),
       assert(
         !enabled || githubRepository == expectedGithubRepository,
         'QA public update GitHub repository is missing or unapproved.',
       ),
       assert(
         !enabled || channel == expectedChannel,
         'QA public update channel is missing or unapproved.',
       );

  static const expectedManifestUrl =
      'https://relio-17dc0.web.app/qa/latest.json';
  static const expectedGithubOwner = 'Khwanchai9999';
  static const expectedGithubRepository = 'RELIO-Android-Updates';
  static const expectedChannel = 'qa-public';

  final bool enabled;
  final String manifestUrl;
  final String githubOwner;
  final String githubRepository;
  final String channel;

  void validate() {
    if (!enabled) return;
    if (manifestUrl != expectedManifestUrl) {
      throw ArgumentError.value(manifestUrl, 'manifestUrl');
    }
    if (githubOwner != expectedGithubOwner) {
      throw ArgumentError.value(githubOwner, 'githubOwner');
    }
    if (githubRepository != expectedGithubRepository) {
      throw ArgumentError.value(githubRepository, 'githubRepository');
    }
    if (channel != expectedChannel) {
      throw ArgumentError.value(channel, 'channel');
    }
  }
}
