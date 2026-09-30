import 'dart:convert';
import 'dart:io';

import 'package:relio_mobile/core/app_update/public_update_manifest.dart';

void main(List<String> args) {
  if (args.length < 7) {
    stderr.writeln(
      'Usage: dart run tool/validate_public_qa_manifest.dart <manifest> '
      '<versionName> <versionCode> <apkUrl> <sha256> <sizeBytes> <signer> '
      '[installedBuild ...]',
    );
    exitCode = 64;
    return;
  }

  final file = File(args[0]);
  final versionName = args[1];
  final versionCode = int.parse(args[2]);
  final apkUrl = Uri.parse(args[3]);
  final sha256 = args[4].toLowerCase();
  final sizeBytes = int.parse(args[5]);
  final signer = args[6].replaceAll(':', '').toLowerCase();
  final installedBuilds = args.skip(7).map(int.parse);
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Manifest root must be a JSON object.');
  }

  final manifest = PublicQaUpdateManifest.fromJson(
    decoded,
    urlPolicy: PublicUpdateUrlPolicy(
      manifestUri: Uri.parse('https://relio-17dc0.web.app/qa/latest.json'),
      githubOwner: 'Khwanchai9999',
    ),
  );
  if (manifest.versionName != versionName ||
      manifest.versionCode != versionCode ||
      manifest.apkUrl != apkUrl ||
      manifest.sha256 != sha256 ||
      manifest.sizeBytes != sizeBytes ||
      manifest.signingCertSha256 != signer) {
    throw const FormatException(
      'Parsed manifest does not match the verified release artifact.',
    );
  }

  for (final installedBuild in installedBuilds) {
    final status = versionCode > installedBuild
        ? 'updateAvailable'
        : 'noUpdate';
    stdout.writeln('$installedBuild -> $status $versionCode');
  }
}
