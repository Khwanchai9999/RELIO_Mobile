import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/shared/widgets/relio_widgets.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
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
}
