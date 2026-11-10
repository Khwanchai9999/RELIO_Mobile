import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/settings/settings_screen.dart';

void main() {
  testWidgets('relay participation requires informed QA consent', (
    tester,
  ) async {
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RelioThemeScope(
          notifier: RelioThemeController(),
          child: RelioDependencyScope(
            dependencies: dependencies,
            child: const SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final consentSwitch = find.byKey(
      const ValueKey('relay-participation-consent'),
    );
    await tester.scrollUntilVisible(
      find.text('ช่วยค้นหาอุปกรณ์ผ่านรีเลย์'),
      250,
    );
    await tester.ensureVisible(consentSwitch);
    await tester.pumpAndSettle();
    await tester.tap(consentSwitch);
    await tester.pumpAndSettle();

    if (RelioBuildInfo.isTest) {
      expect(find.text('อนุญาต QA Relay หรือไม่?'), findsOneWidget);
      expect(
        find.textContaining('เครื่องกลางที่ช่วยส่งต่อ อาจอ่านข้อความได้'),
        findsOneWidget,
      );
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(await dependencies.getRelayParticipationConsent(), isFalse);

      await tester.tap(consentSwitch);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยอมรับและเปิด QA Relay'));
      await tester.pumpAndSettle();
      expect(await dependencies.getRelayParticipationConsent(), isTrue);
    } else {
      expect(find.text('อนุญาต QA Relay หรือไม่?'), findsNothing);
      expect(await dependencies.getRelayParticipationConsent(), isTrue);
    }

    await tester.tap(consentSwitch);
    await tester.pumpAndSettle();
    expect(await dependencies.getRelayParticipationConsent(), isFalse);
    expect(find.text('อนุญาต QA Relay หรือไม่?'), findsNothing);
  });
}
