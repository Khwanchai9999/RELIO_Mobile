import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/media/media_preview_layout.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/shared/widgets/relio_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mediaChannel = MethodChannel('relio/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('relio-chat-media-');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(mediaChannel, null);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  });

  final landscape = File('assets/maps/sprites/light@2x.png').absolute;
  final portrait = File('test/goldens/sos-pre-activation.png').absolute;
  final square = File('assets/branding/relio-logo-master.png').absolute;

  for (final (name, source) in [
    ('landscape', const Size(512, 228)),
    ('portrait', const Size(360, 800)),
    ('square', const Size(400, 400)),
    ('very tall', const Size(40, 2400)),
  ]) {
    test('$name preview layout preserves ratio and stays within bounds', () {
      final size = fitMediaPreviewSize(source, const Size(280, 360));
      expect(
        size.width / size.height,
        closeTo(source.width / source.height, 1e-9),
      );
      expect(size.width, lessThanOrEqualTo(280));
      expect(size.height, lessThanOrEqualTo(360));
    });
  }

  RelioMessage message({
    required String id,
    required MessageType type,
    required String path,
  }) => RelioMessage(
    id: id,
    text: '',
    time: '11:37',
    outgoing: true,
    type: type,
    localFilePath: path,
    status: DeliveryStatus.delivered,
  );

  Future<void> pumpBubble(WidgetTester tester, RelioMessage item) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: RelioMessageBubble(message: item)),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('shared location bubble exposes its compact map action', (
    tester,
  ) async {
    var opened = false;
    final location = RelioMessage(
      id: 'location-a',
      text: 'ตำแหน่งที่แชร์',
      time: '18:56',
      outgoing: false,
      type: MessageType.location,
      createdAt: DateTime(2026, 11, 3, 18, 56),
      latitude: 14.041375,
      longitude: 100.739633,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelioMessageBubble(
            message: location,
            onOpenLocation: () => opened = true,
          ),
        ),
      ),
    );
    expect(find.text('ตำแหน่งที่แชร์'), findsOneWidget);
    await tester.tap(find.text('เปิดดูตำแหน่ง'));
    expect(opened, isTrue);
  });

  for (final (name, file) in [
    ('landscape', landscape),
    ('portrait', portrait),
    ('square', square),
  ]) {
    testWidgets('$name image retains its visual aspect ratio', (tester) async {
      await pumpBubble(
        tester,
        message(id: name, type: MessageType.image, path: file.path),
      );
      expect(find.byType(FutureBuilder<Size>), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.widget<InkWell>(find.byType(InkWell).first).onTap,
        isNotNull,
      );
      expect(find.text('11:37'), findsOneWidget);
    });
  }

  testWidgets('image remains tappable and missing media falls back safely', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      message(id: 'tap', type: MessageType.image, path: portrait.path),
    );
    expect(tester.widget<InkWell>(find.byType(InkWell).first).onTap, isNotNull);

    await pumpBubble(
      tester,
      message(id: 'missing', type: MessageType.image, path: ''),
    );
    expect(find.text('ไม่พบไฟล์รูปภาพ'), findsOneWidget);
  });

  testWidgets(
    'video thumbnail cache uses stable media identity and play still works',
    (tester) async {
      final video = File('${temporary.path}/sample.mp4')
        ..writeAsBytesSync([0, 0, 0, 0]);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(mediaChannel, (call) async {
        calls.add(call);
        if (call.method == 'videoThumbnail') {
          return {'path': landscape.path, 'width': 512, 'height': 228};
        }
        return null;
      });

      await pumpBubble(
        tester,
        message(id: 'video-one', type: MessageType.video, path: video.path),
      );
      for (var i = 0; i < 10; i++) {
        if (calls.any((call) => call.method == 'videoThumbnail')) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call.method == 'videoThumbnail'),
        hasLength(1),
      );
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                RelioMessageBubble(
                  message: message(
                    id: 'video-one',
                    type: MessageType.video,
                    path: video.path,
                  ),
                ),
                RelioMessageBubble(
                  message: message(
                    id: 'video-two',
                    type: MessageType.video,
                    path: video.path,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final thumbnailCalls = calls
          .where((call) => call.method == 'videoThumbnail')
          .toList();
      expect(thumbnailCalls, hasLength(1));

      await tester.tap(find.byTooltip('เล่นวิดีโอ').first);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(calls.last.method, 'playLocalVideo');
    },
  );
}
