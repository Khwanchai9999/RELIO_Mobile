import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/theme/relio_colors.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/sync/sync_engine.dart';
import 'package:relio_mobile/core/sync/sync_types.dart';
import 'package:relio_mobile/features/sync/sync_screen.dart';

class BlockingFakeCloudDataSource extends FakeCloudDataSource {
  bool blockPull = false;
  Completer<void>? pullGate;
  int pullCalls = 0;

  @override
  Future<List<CloudConversationDto>> listMyDirectConversations() async {
    pullCalls++;
    if (blockPull) await pullGate!.future;
    return super.listMyDirectConversations();
  }
}

RelioQueueItem queueItem(
  String status, {
  SyncOperation operation = SyncOperation.privateBackupUpsert,
  String owner = 'qa-owner',
}) => RelioQueueItem(
  id: 'private-backup-$status',
  entityType: 'private_backup_message',
  entityId: '${operation.value}-$status-$owner',
  operation: operation.value,
  status: status,
  ownerUserId: owner,
  attemptCount: 0,
  lastError: null,
  createdAt: DateTime.utc(2026, 11, 2),
  updatedAt: DateTime.utc(2026, 11, 2),
  nextAttemptAt: null,
);

SyncEngineSnapshot snapshot({
  SyncEngineState state = SyncEngineState.idle,
  CloudState cloud = CloudState.ready,
  AuthState auth = AuthState.authenticated,
  String? error,
}) => SyncEngineSnapshot(
  state: state,
  cloudState: cloud,
  authState: auth,
  queueSummary: const SyncQueueSummary.empty(),
  lastError: error,
);

Future<void> pumpStatusCard(
  WidgetTester tester, {
  required SyncEngineSnapshot state,
  required List<RelioQueueItem> items,
  bool isRunning = false,
  int? confirmedCount = 0,
  ThemeMode themeMode = ThemeMode.light,
  bool reduceMotion = false,
}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: RelioColors.primary),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: CloudSyncStatusCard(
              snapshot: state,
              privateItems: items,
              isRunning: isRunning,
              confirmedCount: confirmedCount,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  Future<void> pumpSummary(
    WidgetTester tester,
    SyncEngineState state,
    List<RelioQueueItem> items, {
    String? owner = 'qa-owner',
    bool loaded = true,
    double scale = 1,
    bool dark = false,
    bool reduceMotion = false,
    int? confirmedBackupCount = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SyncStatusSummary(
                snapshot: snapshot(state: state),
                items: items,
                ownerUserId: owner,
                queueLoaded: loaded,
                confirmedBackupCount: owner == null
                    ? null
                    : confirmedBackupCount,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String count(WidgetTester tester, int row) =>
      tester.widget<Text>(find.byKey(ValueKey('sync-status-count-$row'))).data!;

  testWidgets(
    'summary separates unique waiting, failed and server backup counts',
    (tester) async {
      final items = [
        for (final operation in [
          SyncOperation.messageUpsert,
          SyncOperation.sosUpsert,
          SyncOperation.attachmentMetadataUpsert,
          SyncOperation.attachmentUpload,
          SyncOperation.readReceiptUpsert,
        ])
          queueItem('completed', operation: operation),
        for (final operation in [
          SyncOperation.privateBackupUpsert,
          SyncOperation.profileUpsert,
          SyncOperation.conversationUpsert,
          SyncOperation.attachmentDownload,
        ])
          queueItem('completed', operation: operation),
        queueItem(
          'completed',
          operation: SyncOperation.messageUpsert,
          owner: 'other-owner',
        ),
        queueItem('pending', operation: SyncOperation.messageUpsert),
        queueItem('processing', operation: SyncOperation.attachmentUpload),
        queueItem('pending'),
        queueItem('pending', operation: SyncOperation.attachmentDownload),
        queueItem('failed', operation: SyncOperation.sosUpsert),
      ];
      await pumpSummary(tester, SyncEngineState.idle, items);
      expect(count(tester, 0), '3');
      expect(count(tester, 1), '1');
      expect(count(tester, 2), '0');
      expect(find.byKey(const ValueKey('sync-status-spinner')), findsNothing);
      await pumpSummary(
        tester,
        SyncEngineState.idle,
        items,
        owner: 'other-owner',
      );
      expect(count(tester, 0), '0');
      expect(count(tester, 1), '0');
      expect(count(tester, 2), '0');
      await pumpSummary(tester, SyncEngineState.idle, items, owner: null);
      expect(count(tester, 0), '0');
      expect(count(tester, 1), '0');
      expect(count(tester, 2), '—');
      await pumpSummary(tester, SyncEngineState.idle, items, loaded: false);
      expect(count(tester, 1), '—');
      expect(count(tester, 2), '0');
    },
  );

  testWidgets(
    'only engine running animates the 22dp slot including zero-upload pull',
    (tester) async {
      await pumpSummary(tester, SyncEngineState.idle, []);
      final waitingHeight = tester
          .getSize(find.byKey(const ValueKey('sync-status-row-0')))
          .height;
      await pumpSummary(tester, SyncEngineState.running, []);
      expect(find.text('ข้อมูลที่รอหรือกำลังส่งขึ้น Cloud'), findsOneWidget);
      expect(count(tester, 0), '0');
      expect(
        tester.getSize(find.byKey(const ValueKey('sync-status-icon-1'))),
        const Size(22, 22),
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byKey(const ValueKey('sync-status-spinner')),
            )
            .value,
        isNull,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('sync-status-row-0'))).height,
        waitingHeight,
      );
      for (final state in [
        SyncEngineState.waitingForCloud,
        SyncEngineState.waitingForBinding,
        SyncEngineState.waitingForOwnership,
        SyncEngineState.completed,
        SyncEngineState.error,
      ]) {
        await pumpSummary(tester, state, [
          queueItem('pending', operation: SyncOperation.messageUpsert),
        ]);
        expect(find.byKey(const ValueKey('sync-status-spinner')), findsNothing);
      }
    },
  );

  testWidgets('top backup summary matches Cloud-confirmed status count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                CloudSyncStatusCard(
                  snapshot: snapshot(),
                  privateItems: [queueItem('completed')],
                  isRunning: false,
                  confirmedCount: 7,
                ),
                SyncStatusSummary(
                  snapshot: snapshot(),
                  items: [queueItem('completed')],
                  ownerUserId: 'qa-owner',
                  confirmedBackupCount: 7,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('จำนวนข้อมูลที่ยืนยันบน Cloud: 7 รายการ'), findsOneWidget);
    expect(count(tester, 2), '7');
  });

  testWidgets(
    'compact rows remain equal at narrow widths and accessible text scales',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [280.0, 360.0]) {
        tester.view.physicalSize = Size(width, 1000);
        for (final scale in [1.0, 1.5, 2.0]) {
          await pumpSummary(
            tester,
            SyncEngineState.running,
            [],
            scale: scale,
            dark: scale > 1,
            reduceMotion: true,
          );
          final height = tester
              .getSize(find.byKey(const ValueKey('sync-status-row-0')))
              .height;
          for (var row = 0; row < 3; row++) {
            expect(
              tester
                  .getSize(find.byKey(ValueKey('sync-status-row-$row')))
                  .height,
              height,
            );
            expect(
              tester.getSize(find.byKey(ValueKey('sync-status-icon-$row'))),
              const Size(22, 22),
            );
          }
          expect(
            tester
                .widget<CircularProgressIndicator>(
                  find.byKey(const ValueKey('sync-status-spinner')),
                )
                .value,
            isNotNull,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('shows truthful pending, offline, failure and success states', (
    tester,
  ) async {
    await pumpStatusCard(
      tester,
      state: snapshot(),
      items: [queueItem('pending')],
    );
    expect(find.text('รอการสำรองข้อมูล'), findsOneWidget);
    expect(find.text('รออยู่ 1 รายการ'), findsOneWidget);

    await pumpStatusCard(
      tester,
      state: snapshot(cloud: CloudState.offline),
      items: [queueItem('pending')],
    );
    expect(find.text('รออินเทอร์เน็ต'), findsOneWidget);
    expect(find.text('ข้อมูลยังอยู่ในเครื่องอย่างปลอดภัย'), findsOneWidget);

    await pumpStatusCard(
      tester,
      state: snapshot(state: SyncEngineState.error, error: 'storage'),
      items: [queueItem('failed')],
    );
    expect(find.text('สำรองข้อมูลไม่สำเร็จ'), findsOneWidget);
    expect(
      find.text('ตรวจสอบไฟล์สำรองไม่ผ่าน ข้อมูลเดิมยังอยู่ในเครื่อง'),
      findsOneWidget,
    );

    await pumpStatusCard(
      tester,
      state: snapshot(state: SyncEngineState.waitingForBinding),
      items: [queueItem('completed')],
      confirmedCount: 1,
    );
    expect(find.text('สำรองข้อมูลล่าสุดแล้ว'), findsOneWidget);
    expect(
      find.text('ข้อมูลส่วนตัวของคุณถูกเก็บบน Cloud แล้ว'),
      findsOneWidget,
    );
    expect(find.textContaining('รอเชื่อมบทสนทนา'), findsNothing);
  });

  testWidgets('shows real busy spinner and clears it after completion', (
    tester,
  ) async {
    await pumpStatusCard(
      tester,
      state: snapshot(state: SyncEngineState.running),
      items: [queueItem('processing')],
      isRunning: true,
    );
    expect(find.text('กำลังสำรองข้อมูล'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pumpStatusCard(
      tester,
      state: snapshot(state: SyncEngineState.completed),
      items: [queueItem('completed')],
      confirmedCount: 1,
    );
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('supports light/dark themes and reduced-motion transitions', (
    tester,
  ) async {
    await pumpStatusCard(
      tester,
      state: snapshot(),
      items: [queueItem('pending')],
      reduceMotion: true,
    );
    expect(tester.takeException(), isNull);
    await pumpStatusCard(
      tester,
      state: snapshot(),
      items: [queueItem('pending')],
      themeMode: ThemeMode.dark,
      reduceMotion: true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sync details are collapsed and repeated backup cards are gone', (
    tester,
  ) async {
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
      cloudDataSource: FakeCloudDataSource(configured: false),
      androidPlatformOverride: false,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
    });
    await dependencies.initialize();
    await tester.pumpWidget(
      RelioDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: ThemeData(colorSchemeSeed: RelioColors.primary),
          darkTheme: ThemeData.dark(useMaterial3: true),
          home: const SyncScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('สถานะการซิงก์'), findsOneWidget);
    expect(find.text('รายละเอียดเพิ่มเติม'), findsOneWidget);
    expect(find.text('สำรองบัญชีส่วนตัว'), findsNothing);
    expect(find.text('ข้อมูลที่สำรองแล้ว'), findsNothing);
    expect(find.text('ข้อมูลยังอยู่ในเครื่อง'), findsOneWidget);
    expect(find.text('จำนวนข้อมูลที่ยืนยันบน Cloud: —'), findsOneWidget);
    expect(find.text('กำลังตรวจสอบจำนวนข้อมูลบน Cloud'), findsNothing);

    await tester.tap(find.text('รายละเอียดเพิ่มเติม'));
    await tester.pumpAndSettle();
    expect(find.text('ข้อมูลที่สำรองแล้ว'), findsOneWidget);
    expect(find.text('ข้อมูลรอสำรอง'), findsOneWidget);
    expect(find.text('แชท Cloud'), findsOneWidget);
    expect(find.text('แชทกับบัญชีอื่น'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('automatic-private-backup-switch')),
      findsOneWidget,
    );
    expect(
      await dependencies.repositories.settings.getNullableBool(
        'automatic_private_backup_enabled',
      ),
      isNull,
    );
    expect(find.byType(ExpansionTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sync Now ignores duplicate taps while a sync is active', (
    tester,
  ) async {
    final cloud = BlockingFakeCloudDataSource();
    cloud.createTestIdentity(email: 'sync-ui@example.invalid');
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
      cloudDataSource: cloud,
      androidPlatformOverride: false,
    );
    addTearDown(() async {
      cloud.blockPull = false;
      if (cloud.pullGate case final gate? when !gate.isCompleted) {
        gate.complete();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
    });
    await dependencies.initialize();
    await cloud.signIn(email: 'sync-ui@example.invalid', password: 'password');
    await dependencies.syncEngine.run();
    await dependencies.repositories.settings.setBool(
      'automatic_private_backup_enabled',
      false,
    );
    cloud.pullCalls = 0;
    cloud.pullGate = Completer<void>();
    cloud.blockPull = true;

    await tester.pumpWidget(
      RelioDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(home: const SyncScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายละเอียดเพิ่มเติม'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('sync-now-button')));
    await tester.pumpAndSettle();
    expect(cloud.pullCalls, 0);
    expect(
      await dependencies.repositories.settings.getNullableBool(
        'automatic_private_backup_enabled',
      ),
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('automatic-private-backup-switch')),
          )
          .value,
      isFalse,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('sync-now-button')));
    await tester.tap(find.byKey(const ValueKey('sync-now-button')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.text('กำลังซิงก์...'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sync-now-button')))
          .onPressed,
      isNull,
    );
    expect(cloud.pullCalls, 1);
    await tester.tap(
      find.byKey(const ValueKey('sync-now-button')),
      warnIfMissed: false,
    );
    expect(cloud.pullCalls, 1);

    cloud.blockPull = false;
    cloud.pullGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('กำลังซิงก์...'), findsNothing);
    expect(cloud.pullCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
