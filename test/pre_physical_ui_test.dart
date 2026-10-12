import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/shared/widgets/relio_widgets.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  testWidgets('message delivery and Cloud sync statuses stay distinct', (
    tester,
  ) async {
    const message = RelioMessage(
      id: 'queued-message',
      text: 'ข้อความทดสอบ',
      time: '10:00',
      outgoing: true,
      type: MessageType.text,
      status: DeliveryStatus.delivered,
      cloudSyncStatus: 'pending',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RelioMessageBubble(message: message)),
      ),
    );

    expect(find.text('ส่งแล้ว'), findsOneWidget);
    expect(find.text('รอซิงก์'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RelioMessageBubble(
            message: RelioMessage(
              id: 'synced-message',
              text: 'ข้อความทดสอบ',
              time: '10:00',
              outgoing: true,
              type: MessageType.text,
              status: DeliveryStatus.delivered,
              cloudSyncStatus: 'synced',
            ),
          ),
        ),
      ),
    );

    expect(find.text('ส่งแล้ว'), findsOneWidget);
    expect(find.text('ซิงก์แล้ว'), findsOneWidget);
  });

  testWidgets('image message opens a viewer and handles a missing local file', (
    tester,
  ) async {
    final missingPath = '${Directory.systemTemp.path}/relio-missing-image.png';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelioMessageBubble(
            message: RelioMessage(
              id: 'image-message',
              text: 'photo.png',
              time: '10:00',
              outgoing: false,
              type: MessageType.image,
              localFilePath: missingPath,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ไม่พบไฟล์รูปภาพ'), findsOneWidget);
    await tester.tap(find.byTooltip('เปิดรูปภาพเต็มจอ'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถเปิดรูปภาพนี้ได้'), findsOneWidget);
    expect(find.byTooltip('ปิดรูปภาพ'), findsOneWidget);
  });

  testWidgets(
    'image message without a stored path has an accessible fallback',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RelioMessageBubble(
              message: RelioMessage(
                id: 'missing-image-message',
                text: 'photo.png',
                time: '10:00',
                outgoing: true,
                type: MessageType.image,
              ),
            ),
          ),
        ),
      );

      expect(find.text('ไม่พบไฟล์รูปภาพ'), findsOneWidget);
      expect(find.byTooltip('เปิดรูปภาพเต็มจอ'), findsNothing);
    },
  );

  testWidgets('video message opens the native local playback control', (
    tester,
  ) async {
    const channel = MethodChannel('relio/media');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final file = File('${Directory.systemTemp.path}/relio-playback-test.mp4')
      ..writeAsBytesSync([0, 0, 0, 0]);
    addTearDown(() => file.deleteSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelioMessageBubble(
            message: RelioMessage(
              id: 'video-message',
              text: 'qa.mp4',
              time: '10:00',
              outgoing: false,
              type: MessageType.video,
              localFilePath: file.path,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('เล่นวิดีโอ'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'playLocalVideo');
    expect(calls.single.arguments, {'path': file.path});
  });

  testWidgets('video message reports when its local attachment is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RelioMessageBubble(
            message: RelioMessage(
              id: 'missing-video-message',
              text: 'qa.mp4',
              time: '10:00',
              outgoing: false,
              type: MessageType.video,
              localFilePath: '/missing/relio-video.mp4',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('เล่นวิดีโอ'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(find.text('ไม่พบไฟล์วิดีโอในเครื่อง'), findsOneWidget);
  });
}
