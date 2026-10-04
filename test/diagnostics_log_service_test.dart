import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/diagnostics/diagnostics_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const shareChannel = MethodChannel('relio/diagnostics');
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('relio-diagnostics-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async => root.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(pathChannel, null)
      ..setMockMethodCallHandler(shareChannel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('export archive redacts secret-like fields and private content', () async {
    final logs = DiagnosticsLogService(
      directory: Directory('${root.path}/logs'),
    );
    await logs.initialize();
    logs.record(
      'connection',
      'native_failure',
      nativeMessage:
          'access_token=FAKE_ACCESS refresh_token=FAKE_REFRESH FCM_TOKEN=FAKE_FCM',
      detailsSummary: 'service_role=FAKE_ROLE password=FAKE_PASSWORD',
      fields: {
        'message_body': 'FAKE_MESSAGE_BODY',
        'private_key': 'FAKE_PRIVATE_KEY',
        'safeFlag': true,
      },
    );
    final file = await logs.exportZip(
      appInfo: const {'version': '0.9.0', 'build': '27'},
      deviceState: const {'nearbyReady': true},
      summary: 'safe summary',
    );
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final text = archive.files
        .where((entry) => entry.isFile)
        .map((entry) => utf8.decode(entry.content as List<int>))
        .join('\n');

    for (final secret in [
      'FAKE_ACCESS',
      'FAKE_REFRESH',
      'FAKE_FCM',
      'FAKE_ROLE',
      'FAKE_PASSWORD',
      'FAKE_MESSAGE_BODY',
      'FAKE_PRIVATE_KEY',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    expect(text, contains('"safeFlag":true'));
    expect(
      archive.files.map((entry) => entry.name),
      isNot(contains('database.sqlite')),
    );
    await file.delete();
  });

  test('production build disables diagnostics at compile time', () {
    const expected = bool.fromEnvironment(
      'EXPECT_DIAGNOSTICS',
      defaultValue: true,
    );
    expect(DiagnosticsLogService().enabled, expected);
  });

  test(
    'export sanitizes summary and nested metadata and excludes media',
    () async {
      final logs = DiagnosticsLogService(
        directory: Directory('${root.path}/logs'),
      );
      await logs.initialize();
      await File(
        '${logs.directory!.path}/private-photo.png',
      ).writeAsString('PRIVATE_IMAGE_BYTES');
      final zip = await logs.exportZip(
        appInfo: {
          'version': '0.9.0',
          'versionCode': 32,
          'password': 'EXPORT_PASSWORD',
        },
        deviceState: {
          'nested': {
            'access_token': 'EXPORT_ACCESS',
            'refresh_token': 'EXPORT_REFRESH',
            'service_role': 'EXPORT_ROLE',
            'fcmToken': 'EXPORT_FCM',
            'privateKey': 'EXPORT_KEY',
            'authorization': 'Basic EXPORT_AUTH',
            'chatBody': 'EXPORT_CHAT',
            'imageBytes': [91, 92, 93],
            'payload': [91, 92, 93],
            'localPath': '/private/photo.png',
          },
          'sizeBytes': 68,
          'mimeType': 'image/png',
          'transferState': 'completed',
        },
        summary:
            'password=SUMMARY_PASSWORD\nAuthorization: Basic SUMMARY_AUTH\nmessage_body=SUMMARY_CHAT\n-----BEGIN PRIVATE KEY-----\nSUMMARY_KEY\n-----END PRIVATE KEY-----',
      );
      final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      final text = archive.files
          .where((e) => e.isFile)
          .map((e) => utf8.decode(e.content as List<int>))
          .join('\n');
      for (final marker in [
        'EXPORT_PASSWORD',
        'EXPORT_ACCESS',
        'EXPORT_REFRESH',
        'EXPORT_ROLE',
        'EXPORT_FCM',
        'EXPORT_KEY',
        'EXPORT_AUTH',
        'EXPORT_CHAT',
        'SUMMARY_PASSWORD',
        'SUMMARY_AUTH',
        'SUMMARY_CHAT',
        'SUMMARY_KEY',
        'PRIVATE_IMAGE_BYTES',
        '/private/photo.png',
        'imageBytes',
        '[91,92,93]',
      ]) {
        expect(text, isNot(contains(marker)), reason: marker);
      }
      expect(text, contains('image/png'));
      expect(text, contains('completed'));
      await zip.delete();
    },
  );
}
