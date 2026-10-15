import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/connectivity/qa_internet_simulator.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  late Directory directory;
  late FakeCloudBackend backend;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('relio-offline-auth-');
    backend = FakeCloudBackend();
  });

  tearDown(() async {
    if (await directory.exists()) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // A failing assertion should remain the reported test failure.
      }
    }
  });

  RelioDependencies createDependencies({
    required bool offline,
    required FakeCloudDataSource cloud,
  }) => RelioDependencies(
    database: AppDatabase.withExecutor(
      NativeDatabase(File('${directory.path}/relio.sqlite')),
    ),
    cloudDataSource: cloud,
    internetSimulator: QaInternetSimulator.forTesting(),
    useMockTransport: true,
    androidPlatformOverride: false,
  )..internetSimulator.setSimulatedOffline(offline);

  Future<void> setOfflinePreference(RelioDependencies dependencies) async {
    await dependencies.repositories.settings.setBool(
      'qa_simulated_internet_offline',
      true,
    );
  }

  test(
    'restores authenticated principal, profile and chat scope offline',
    () async {
      final onlineCloud = FakeCloudDataSource(backend: backend);
      final online = createDependencies(offline: false, cloud: onlineCloud);
      await online.initializeAuth();
      await online.authService.register(
        email: 'jane@example.test',
        password: 'valid-password',
        displayName: 'Jane',
      );
      await online.identity.setDisplayName('Jane');
      final deviceId = await online.identity.getDeviceId();
      await online.repositories.nearbyDevices.upsert(
        deviceId: 'trusted-peer',
        displayName: 'Trusted peer',
        status: DeviceStatus.normal,
      );
      await online.repositories.nearbyDevices.setTrusted('trusted-peer', true);
      await online.repositories.nearbyDevices.setTrustedIdentity(
        deviceId: 'trusted-peer',
        publicIdentityKey: 'pinned-public-key',
        fingerprint: List.filled(64, 'a').join(),
      );
      final janeChat = await online.repositories.conversations
          .ensureConversation(
            id: 'jane-chat',
            participantId: 'peer-a',
            displayName: 'Contact A',
            participantStatus: DeviceStatus.normal,
          );
      final janeConversationId = janeChat.id;
      await online.repositories.messages.createIncomingText(
        conversationId: janeChat.id,
        senderId: 'peer-a',
        senderDeviceId: 'device-a',
        messageId: 'jane-message',
        text: 'Jane local history',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await setOfflinePreference(online);
      await online.dispose();

      final offlineCloud = FakeCloudDataSource(backend: backend);
      final offline = createDependencies(offline: false, cloud: offlineCloud);
      await Future.wait([offline.initializeAuth(), offline.initialize()]);

      expect(offline.internetSimulator.simulatedOffline, isTrue);
      expect(offline.hasAuthenticatedPrincipal, isTrue);
      expect(offline.hasOfflineAuthenticatedPrincipal, isTrue);
      expect(offline.authService.identity, isNull);
      expect(offline.authService.state, AuthState.guest);
      expect(offlineCloud.initializeCalls, 0);
      expect(offlineCloud.restoreSessionCalls, 0);
      expect(
        (await offline.repositories.profiles.current()).displayName,
        'Jane',
      );
      expect(
        (await offline.repositories.conversations.listConversations()).map(
          (chat) => chat.id,
        ),
        contains(janeConversationId),
      );
      expect(
        (await offline.repositories.messages.listMessages(
          janeConversationId,
        )).single.text,
        'Jane local history',
      );
      expect(await offline.identity.getDeviceId(), deviceId);
      final trustedPeer = await offline.repositories.nearbyDevices.getDevice(
        'trusted-peer',
      );
      expect(trustedPeer?.isTrusted, isTrue);
      expect(
        trustedPeer?.publicIdentityFingerprint,
        List.filled(64, 'a').join(),
      );
      await offline.dispose();
    },
  );

  test(
    'explicit logout clears offline principal before next startup',
    () async {
      final online = createDependencies(
        offline: false,
        cloud: FakeCloudDataSource(backend: backend),
      );
      await online.initializeAuth();
      await online.authService.register(
        email: 'jane@example.test',
        password: 'valid-password',
        displayName: 'Jane',
      );
      await online.authService.signOut();
      await setOfflinePreference(online);
      await online.dispose();

      final offlineCloud = FakeCloudDataSource(backend: backend);
      final restarted = createDependencies(offline: false, cloud: offlineCloud);
      await restarted.initializeAuth();
      expect(restarted.hasAuthenticatedPrincipal, isFalse);
      expect(restarted.repositories.ownerContext.capture().userId, isNull);
      expect(offlineCloud.initializeCalls, 0);
      await restarted.dispose();
    },
  );

  test(
    'failed account switch preserves the last successful principal',
    () async {
      final online = createDependencies(
        offline: false,
        cloud: FakeCloudDataSource(backend: backend),
      );
      await online.initializeAuth();
      await online.authService.register(
        email: 'jane@example.test',
        password: 'valid-password',
        displayName: 'Jane',
      );
      await expectLater(
        online.authService.signIn(
          email: 'minnie@example.test',
          password: 'wrong-password',
        ),
        throwsA(isA<CloudException>()),
      );
      await setOfflinePreference(online);
      await online.dispose();

      final restarted = createDependencies(
        offline: false,
        cloud: FakeCloudDataSource(backend: backend),
      );
      await restarted.initializeAuth();
      expect(restarted.repositories.ownerContext.capture().userId, 'fake-1');
      expect(
        (await restarted.repositories.profiles.current()).displayName,
        'Jane',
      );
      await restarted.dispose();
    },
  );

  test(
    'guest startup offline remains guest and does not authenticate locally',
    () async {
      final seed = createDependencies(
        offline: false,
        cloud: FakeCloudDataSource(backend: backend),
      );
      await seed.initializeAuth();
      await setOfflinePreference(seed);
      await seed.dispose();

      final offlineCloud = FakeCloudDataSource(backend: backend, offline: true);
      final restarted = createDependencies(offline: false, cloud: offlineCloud);
      await restarted.initializeAuth();
      expect(restarted.hasAuthenticatedPrincipal, isFalse);
      expect(restarted.repositories.ownerContext.capture().userId, isNull);
      await expectLater(
        restarted.authService.signIn(
          email: 'jane@example.test',
          password: 'valid-password',
        ),
        throwsA(isA<CloudException>()),
      );
      expect(restarted.hasAuthenticatedPrincipal, isFalse);
      await restarted.dispose();
    },
  );

  test('successful account switch replaces cached local owner', () async {
    final online = createDependencies(
      offline: false,
      cloud: FakeCloudDataSource(backend: backend),
    );
    await online.initializeAuth();
    await online.authService.register(
      email: 'jane@example.test',
      password: 'valid-password',
      displayName: 'Jane',
    );
    await online.repositories.conversations.ensureConversation(
      id: 'jane-only-chat',
      participantId: 'peer-jane',
      displayName: 'Jane Contact',
      participantStatus: DeviceStatus.normal,
    );
    await online.authService.signOut();
    await online.authService.register(
      email: 'minnie@example.test',
      password: 'valid-password',
      displayName: 'Minnie',
    );
    await online.identity.setDisplayName('Minnie');
    final minnieChat = await online.repositories.conversations
        .ensureConversation(
          id: 'minnie-only-chat',
          participantId: 'peer-minnie',
          displayName: 'Minnie Contact',
          participantStatus: DeviceStatus.normal,
        );
    await setOfflinePreference(online);
    await online.dispose();

    final restarted = createDependencies(
      offline: false,
      cloud: FakeCloudDataSource(backend: backend),
    );
    await restarted.initializeAuth();
    expect(restarted.repositories.ownerContext.capture().userId, 'fake-2');
    expect(
      (await restarted.repositories.profiles.current()).displayName,
      'Minnie',
    );
    final visibleChats = await restarted.repositories.conversations
        .listConversations();
    expect(visibleChats.map((chat) => chat.id), contains(minnieChat.id));
    expect(
      visibleChats.map((chat) => chat.displayName),
      isNot(contains('Jane Contact')),
    );
    await restarted.dispose();
  });

  test('invalid online session clears the offline principal safely', () async {
    final online = createDependencies(
      offline: false,
      cloud: FakeCloudDataSource(backend: backend),
    );
    await online.initializeAuth();
    await online.authService.register(
      email: 'jane@example.test',
      password: 'valid-password',
      displayName: 'Jane',
    );
    await setOfflinePreference(online);
    await online.dispose();

    final offlineCloud = FakeCloudDataSource(backend: backend);
    final restarted = createDependencies(offline: false, cloud: offlineCloud);
    await restarted.initializeAuth();
    final cleared = restarted.localAuthChanges.first;
    restarted.internetSimulator.setSimulatedOffline(false);
    await cleared.timeout(const Duration(seconds: 3));
    expect(restarted.hasAuthenticatedPrincipal, isFalse);
    expect(offlineCloud.initializeCalls, greaterThan(0));
    expect(offlineCloud.restoreSessionCalls, greaterThan(0));
    await restarted.dispose();
  });

  test('valid online restoration resumes Cloud under the same owner', () async {
    final online = createDependencies(
      offline: false,
      cloud: FakeCloudDataSource(backend: backend),
    );
    await online.initializeAuth();
    await online.authService.register(
      email: 'jane@example.test',
      password: 'valid-password',
      displayName: 'Jane',
    );
    final janeIdentity = online.authService.identity!;
    await setOfflinePreference(online);
    await online.dispose();

    final returningCloud = FakeCloudDataSource(
      backend: backend,
      restoreIdentityOnInitialize: janeIdentity,
    );
    final restarted = createDependencies(offline: false, cloud: returningCloud);
    await restarted.initializeAuth();
    expect(restarted.hasOfflineAuthenticatedPrincipal, isTrue);
    final authenticated = returningCloud.watchAuthState().firstWhere(
      (state) => state == AuthState.authenticated,
    );
    restarted.internetSimulator.setSimulatedOffline(false);
    await authenticated.timeout(const Duration(seconds: 3));
    expect(returningCloud.currentIdentity?.userId, janeIdentity.userId);
    expect(restarted.hasOfflineAuthenticatedPrincipal, isFalse);
    expect(
      restarted.repositories.ownerContext.capture().userId,
      janeIdentity.userId,
    );
    await restarted.dispose();
  });
}
