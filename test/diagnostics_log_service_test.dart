import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/environment.dart';
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

  test('QA logcat sink receives sanitized Nearby events only', () async {
    final entries = <String>[];
    final logs = DiagnosticsLogService(
      directory: Directory('${root.path}/logs'),
      qaLogcatSink: entries.add,
    );
    logs.record(
      'connection',
      'native_connection_initiated_received',
      peerIdentifier: 'temporary-endpoint',
      fields: {
        'role': 'responder',
        'authenticationToken': 'QA_VERIFICATION_MATERIAL',
        'authenticationCodeAvailable': true,
      },
    );
    logs.record('app', 'ordinary_event');

    expect(entries, hasLength(1));
    expect(entries.single, contains('native_connection_initiated_received'));
    expect(entries.single, contains('peerAlias'));
    expect(entries.single, isNot(contains('temporary-endpoint')));
    expect(entries.single, isNot(contains('QA_VERIFICATION_MATERIAL')));
    expect(entries.single, isNot(contains('authenticationToken')));
    expect(entries.single, contains('"role":"responder"'));
    await logs.flush();
  });

  test(
    'QA SOS diagnostics expose lifecycle without private payload data',
    () async {
      final entries = <String>[];
      final logs = DiagnosticsLogService(qaLogcatSink: entries.add);

      logs.record(
        'sos',
        'outbound_send_failure',
        reason: 'transport_send_failed',
        fields: {
          'stateRevision': 4,
          'isActive': true,
          'transport': 'Nearby',
          'message_body': 'private distress text',
          'latitude': 14.0,
          'longitude': 100.0,
        },
      );

      expect(entries, hasLength(1));
      expect(entries.single, contains('outbound_send_failure'));
      expect(entries.single, contains('"stateRevision":4'));
      expect(entries.single, contains('"isActive":true'));
      expect(entries.single, isNot(contains('private distress text')));
      expect(entries.single, isNot(contains('latitude')));
      expect(entries.single, isNot(contains('longitude')));
      await logs.flush();
    },
  );

  test(
    'media payload diagnostics reach QA logcat without private content',
    () async {
      final entries = <String>[];
      final logs = DiagnosticsLogService(qaLogcatSink: entries.add);
      logs.record(
        'media',
        'FILE_SUCCESS',
        fields: {
          'traceId': 'transfer-1',
          'messageId': 'message-1',
          'attachmentId': 'attachment-1',
          'payloadId': 42,
          'payloadType': 'FILE',
          'direction': 'TX',
          'bytesTransferred': 2048,
          'message_body': 'PRIVATE_CHAT_CONTENT',
          'filePath': r'C:\private\photo.jpg',
        },
      );

      expect(entries, hasLength(1));
      expect(entries.single, contains('FILE_SUCCESS'));
      expect(entries.single, contains('"payloadType":"FILE"'));
      expect(entries.single, contains('"payloadId":42'));
      expect(entries.single, isNot(contains('PRIVATE_CHAT_CONTENT')));
      expect(entries.single, isNot(contains(r'C:\private\photo.jpg')));
      await logs.flush();
    },
  );

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
    'QA USB snapshot is sanitized, bounded to one archive and flavor gated',
    () async {
      final external = Directory('${root.path}/external');
      final logs = DiagnosticsLogService(
        directory: Directory('${root.path}/logs'),
        qaExportDirectory: external,
      );
      await logs.initialize();
      logs.record(
        'media',
        'media_receive_failed',
        fields: {
          'checkpoint': 'file_validation_and_storage',
          'password': 'QA_SECRET_MUST_NOT_EXPORT',
        },
      );
      for (var index = 0; index < 2; index++) {
        await logs.exportZip(
          appInfo: const {},
          deviceState: const {},
          summary: 'QA snapshot',
        );
      }
      final mirror = Directory('${external.path}/qa-diagnostics');
      expect(await mirror.exists(), RelioBuildInfo.isTest);
      if (RelioBuildInfo.isTest) {
        final entries = await mirror.list().toList();
        expect(entries, hasLength(1));
        expect(entries.single.uri.pathSegments.last, 'latest.zip');
        final bytes = await (entries.single as File).readAsBytes();
        expect(bytes.length, lessThanOrEqualTo(6 * 1024 * 1024));
        final archive = ZipDecoder().decodeBytes(bytes);
        final text = archive.files
            .map((entry) => utf8.decode(entry.content as List<int>))
            .join('\n');
        expect(text, contains('file_validation_and_storage'));
        expect(text, isNot(contains('QA_SECRET_MUST_NOT_EXPORT')));
      }
    },
  );

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
