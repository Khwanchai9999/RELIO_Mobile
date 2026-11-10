import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/identity/owner_context.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/repositories/principal_profile_repository.dart';
import 'package:relio_mobile/core/repositories/profile_avatar_repository.dart';
import 'package:relio_mobile/features/profile/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'profile edits the local Nearby name without changing Cloud profile',
    (tester) async {
      final cloud = FakeCloudDataSource();
      await cloud.register(
        email: 'qa-profile@example.test',
        password: 'RelioDemo123!',
        displayName: 'Cloud member name',
      );
      final cloudIdentity = cloud.currentIdentity!;
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(autoAcknowledge: false),
        cloudDataSource: cloud,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: dependencies,
            child: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final generatedName = await dependencies.identity.getDisplayName();
      expect(generatedName, matches(RegExp(r'^ผู้ใช้ RELIO \d{4}$')));
      expect(find.text(generatedName), findsOneWidget);
      expect(
        find.text('แนะนำให้ใช้ชื่อจริงหรือชื่อที่คนใกล้ตัวรู้จัก'),
        findsOneWidget,
      );
      expect(find.text('เข้าสู่ระบบ'), findsNothing);
      expect(find.text('ออกจากโหมดออฟไลน์'), findsNothing);
      expect(find.text('ออกจากระบบ'), findsOneWidget);

      await tester.tap(find.byTooltip('แก้ไขชื่อ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  RELIO QA ชื่อ  ');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('RELIO QA ชื่อ'), findsOneWidget);
      expect(
        find.text('แนะนำให้ใช้ชื่อจริงหรือชื่อที่คนใกล้ตัวรู้จัก'),
        findsNothing,
      );
      expect(await dependencies.identity.getDisplayName(), 'RELIO QA ชื่อ');
      expect(
        cloud.profiles[cloudIdentity.userId]?.displayName,
        'Cloud member name',
      );
    },
  );

  testWidgets(
    'Profile verifies a Member email change without changing owner ID',
    (tester) async {
      final cloud = FakeCloudDataSource();
      final original = await cloud.register(
        email: 'profile-before@example.test',
        password: 'RelioDemo123!',
      );
      cloud.backend.requireBothEmailConfirmations = true;
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(autoAcknowledge: false),
        cloudDataSource: cloud,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: dependencies,
            child: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('รายละเอียดบัญชี'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('เปลี่ยนอีเมลบัญชี'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เปลี่ยนอีเมลบัญชี'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'profile-after@example.test',
      );
      await tester.tap(find.text('ส่งรหัสยืนยัน'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '111111');
      await tester.enterText(find.byType(TextField).at(1), '222222');
      await tester.tap(find.widgetWithText(FilledButton, 'ยืนยันอีเมล'));
      await tester.pumpAndSettle();

      expect(cloud.currentIdentity?.userId, original.userId);
      expect(cloud.currentIdentity?.email, 'profile-after@example.test');
      expect(cloud.currentIdentity?.isAnonymous, isFalse);
    },
  );

  testWidgets(
    'Guest Profile no longer offers the canceled email recovery menu',
    (tester) async {
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(autoAcknowledge: false),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.dispose();
      });
      await dependencies.resumeGuestMode();
      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: dependencies,
            child: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('เพิ่มอีเมลกู้คืนบัญชี Guest'), findsNothing);
      expect(find.text('เปลี่ยนอีเมลบัญชี'), findsNothing);
      expect(find.text('ข้อมูลฉุกเฉิน'), findsOneWidget);
      expect(find.text('ออกจากโหมดออฟไลน์'), findsOneWidget);
    },
  );
  testWidgets('blank name and cancelled edit preserve the current profile', (
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
        home: RelioDependencyScope(
          dependencies: dependencies,
          child: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final originalName = await dependencies.identity.getDisplayName();
    expect(find.text('เข้าสู่ระบบ'), findsOneWidget);

    await tester.tap(find.byTooltip('แก้ไขชื่อ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(find.text('กรุณาระบุชื่อที่แสดง'), findsOneWidget);
    expect(await dependencies.identity.getDisplayName(), originalName);
    expect(
      find.text('แนะนำให้ใช้ชื่อจริงหรือชื่อที่คนใกล้ตัวรู้จัก'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('แก้ไขชื่อ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Another Name');
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(await dependencies.identity.getDisplayName(), originalName);
    expect(find.text(originalName), findsOneWidget);
  });

  test(
    'avatar replacement and removal touch only RELIO-owned copies',
    () async {
      final database = AppDatabase.memory();
      final parent = await Directory.systemTemp.createTemp(
        'relio-avatar-test-',
      );
      addTearDown(() async {
        await database.close();
        await parent.delete(recursive: true);
      });
      final appFiles = Directory('${parent.path}${Platform.pathSeparator}app');
      await appFiles.create();
      final sourceFile = File(
        '${parent.path}${Platform.pathSeparator}original.png',
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1, 1));
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..color = Colors.teal,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(1, 1);
      final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
      final png = pngData!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      await sourceFile.writeAsBytes(png);
      final repository = ProfileAvatarRepository(
        database,
        rootDirectory: appFiles,
      );

      final firstPath = await repository.storePickedImage(
        XFile(sourceFile.path),
      );
      expect(await repository.getAvatarPath(), firstPath);
      expect(await File(firstPath).length(), lessThan(10 * 1024));
      expect(await sourceFile.exists(), isTrue);

      final noisyBytes = Uint8List(256 * 256 * 4);
      final random = math.Random(42);
      for (var i = 0; i < noisyBytes.length; i++) {
        noisyBytes[i] = random.nextInt(256);
      }
      final imageCompleter = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        noisyBytes,
        256,
        256,
        ui.PixelFormat.rgba8888,
        imageCompleter.complete,
      );
      final noisyImage = await imageCompleter.future;
      final noisyData = await noisyImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      noisyImage.dispose();
      final noisySource = File(
        '${parent.path}${Platform.pathSeparator}large.png',
      );
      await noisySource.writeAsBytes(noisyData!.buffer.asUint8List());

      var currentPath = await repository.storePickedImage(
        XFile(noisySource.path),
      );
      expect(await File(currentPath).length(), lessThanOrEqualTo(128 * 1024));
      expect(currentPath, endsWith('.png'));
      var storedCodec = await ui.instantiateImageCodec(
        await File(currentPath).readAsBytes(),
      );
      var storedImage = (await storedCodec.getNextFrame()).image;
      expect(storedImage.width, lessThanOrEqualTo(256));
      expect(storedImage.height, lessThanOrEqualTo(256));
      expect(storedImage.width, lessThan(256));
      storedImage.dispose();
      storedCodec.dispose();
      expect(await noisySource.exists(), isTrue);

      final unreadableFile = File(
        '${parent.path}${Platform.pathSeparator}invalid.png',
      );
      await unreadableFile.writeAsString('not an image');
      await expectLater(
        repository.storePickedImage(XFile(unreadableFile.path)),
        throwsA(isA<ProfileAvatarException>()),
      );
      expect(await repository.getAvatarPath(), currentPath);
      expect(await File(currentPath).exists(), isTrue);

      final secondPath = await repository.storePickedImage(
        XFile(sourceFile.path),
      );
      expect(secondPath, isNot(currentPath));
      expect(
        await Directory('${appFiles.path}/relio_profile/avatars').list().length,
        1,
      );
      expect(await File(currentPath).exists(), isFalse);

      await repository.removeAvatar();
      expect(await repository.getAvatarPath(), isNull);
      expect(await sourceFile.exists(), isTrue);
      expect(
        await Directory(
          '${appFiles.path}/relio_profile/avatars',
        ).list(recursive: true).where((entry) => entry is File).isEmpty,
        isTrue,
      );
    },
  );

  test(
    'Nearby avatar derivative is bounded, hash validated and cached by peer',
    () async {
      final database = AppDatabase.memory();
      final root = await Directory.systemTemp.createTemp('relio-avatar-cache-');
      String? activeUserId;
      final owners = OwnerContext(() => activeUserId);
      addTearDown(() async {
        await database.close();
        await owners.dispose();
        await root.delete(recursive: true);
      });
      final source = File('${root.path}/source.png');
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 8, 8));
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 8, 8),
        Paint()..color = Colors.teal,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(8, 8);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await source.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();

      final repository = ProfileAvatarRepository(
        database,
        rootDirectory: root,
        profiles: PrincipalProfileRepository(database, owners),
      );
      await repository.storePickedImage(XFile(source.path));
      final first = await repository.shareArtifact();
      final second = await repository.shareArtifact();
      expect(first, isNotNull);
      expect(first!.revision, second!.revision);
      expect(await File(first.path).length(), lessThanOrEqualTo(64 * 1024));
      final cachedPath = await repository.storeRemoteAvatar(
        deviceId: 'verified-device-a',
        remotePrincipal: 'guest:peer-owner',
        revision: first.revision,
        sourcePath: first.path,
      );
      expect(cachedPath, isNotNull);
      expect(
        await repository.cachedRemoteRevision(
          deviceId: 'verified-device-a',
          remotePrincipal: 'guest:peer-owner',
        ),
        first.revision,
      );
      expect(
        await repository.remoteAvatarPath(
          deviceId: 'verified-device-b',
          remotePrincipal: 'guest:peer-owner',
        ),
        isNull,
      );
      expect(
        await repository.remoteAvatarPath(
          deviceId: 'verified-device-a',
          remotePrincipal: 'account:peer-member-a',
        ),
        isNull,
      );
      activeUserId = 'qa-member-a';
      expect(
        await repository.remoteAvatarPath(
          deviceId: 'verified-device-a',
          remotePrincipal: 'guest:peer-owner',
        ),
        isNull,
      );
      activeUserId = 'qa-member-b';
      expect(
        await repository.remoteAvatarPath(
          deviceId: 'verified-device-a',
          remotePrincipal: 'guest:peer-owner',
        ),
        isNull,
      );
      activeUserId = null;
      expect(
        await repository.remoteAvatarPath(
          deviceId: 'verified-device-a',
          remotePrincipal: 'guest:peer-owner',
        ),
        cachedPath,
      );
      expect(
        await repository.storeRemoteAvatar(
          deviceId: 'verified-device-a',
          remotePrincipal: 'guest:peer-owner',
          revision: '0' * 64,
          sourcePath: first.path,
        ),
        isNull,
      );
      await repository.removeRemoteAvatar(
        deviceId: 'verified-device-a',
        remotePrincipal: 'guest:peer-owner',
      );
      expect(
        await repository.remoteAvatarPath(
          deviceId: 'verified-device-a',
          remotePrincipal: 'guest:peer-owner',
        ),
        isNull,
      );
    },
  );

  test(
    'missing avatar file falls back safely and clears its stale setting',
    () async {
      final database = AppDatabase.memory();
      final parent = await Directory.systemTemp.createTemp(
        'relio-missing-avatar-',
      );
      addTearDown(() async {
        await database.close();
        await parent.delete(recursive: true);
      });
      await database
          .into(database.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'profile_avatar_path',
              value: '${parent.path}/missing.jpg',
              updatedAt: DateTime(2025),
            ),
          );

      final repository = ProfileAvatarRepository(
        database,
        rootDirectory: parent,
      );
      expect(await repository.getAvatarPath(), isNull);
      expect(await repository.getAvatarPath(), isNull);
    },
  );
}
