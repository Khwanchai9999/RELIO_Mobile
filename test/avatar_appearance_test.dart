import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/presentation/avatar_appearance.dart';
import 'package:relio_mobile/core/presentation/peer_connection_presence.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/shared/widgets/relio_widgets.dart';

void main() {
  test('avatar palette is deterministic and distributed across identities', () {
    const identities = [
      'device-alpha',
      'device-bravo',
      'device-charlie',
      'device-delta',
      'device-echo',
      'device-foxtrot',
      'device-golf',
      'device-hotel',
    ];
    final colors = identities.map(AvatarAppearanceResolver.colorFor).toSet();

    expect(colors, hasLength(identities.length));
    expect(
      AvatarAppearanceResolver.colorFor(' DEVICE-ALPHA '),
      AvatarAppearanceResolver.colorFor('device-alpha'),
    );
    for (final identity in identities) {
      expect(
        AvatarAppearanceResolver.colorFor(identity),
        AvatarAppearanceResolver.colorFor(identity),
      );
    }
  });

  test('presence changes appearance without changing the identity color', () {
    final base = AvatarAppearanceResolver.colorFor('verified-device-id');
    final online = AvatarAppearanceResolver.displayColor(
      base,
      PeerConnectionPresence.online,
    );
    final offline = AvatarAppearanceResolver.displayColor(
      base,
      PeerConnectionPresence.offline,
    );
    final unknown = AvatarAppearanceResolver.displayColor(
      base,
      PeerConnectionPresence.unknown,
    );

    expect(online, base);
    expect(offline, isNot(base));
    expect(unknown, isNot(base));
  });

  testWidgets('Chat and Nearby share a peer color and truthful presence UI', (
    tester,
  ) async {
    const identity = 'verified-device-1234';
    const chat = RelioChatPreview(
      id: 'local-chat-id',
      name: 'Peer',
      message: 'Recent message',
      time: '12:45',
      status: DeviceStatus.normal,
      unread: 2,
      identityKey: identity,
      presence: PeerConnectionPresence.online,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelioChatListTile(chat: chat, onTap: () {}),
        ),
      ),
    );

    final chatAvatarColor = _avatarOutlineColor(tester);
    expect(find.text('ออนไลน์'), findsOneWidget);
    expect(find.text('ปกติ'), findsNothing);
    expect(find.text('Recent message'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('ออนไลน์')).dx,
      lessThan(tester.getTopLeft(find.text('12:45')).dx),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RelioDeviceCard(
            device: RelioDevice(
              id: identity,
              name: 'Peer',
              status: DeviceStatus.normal,
              signalQuality: 80,
              isConnected: true,
              isDemo: false,
              presence: PeerPresence.connected,
            ),
            peerIdentifier: 'RELIO-1234',
          ),
        ),
      ),
    );

    expect(_avatarOutlineColor(tester), chatAvatarColor);
    expect(find.text('ออนไลน์'), findsOneWidget);
    expect(find.text('REAL'), findsNothing);
    expect(find.text('ปกติ'), findsNothing);
    expect(
      tester.getTopLeft(find.text('ออนไลน์')).dx,
      greaterThan(tester.getTopLeft(find.text('Peer')).dx),
    );
  });

  testWidgets('SOS avatar meaning remains visible beside Offline presence', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              RelioUserAvatar(
                name: 'Urgent peer',
                identityKey: 'urgent-peer',
                status: DeviceStatus.sos,
                presence: PeerConnectionPresence.offline,
              ),
              RelioPresenceChip(presence: PeerConnectionPresence.offline),
              RelioPresenceChip(presence: PeerConnectionPresence.unknown),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    expect(find.text('ออฟไลน์'), findsOneWidget);
    expect(find.text('ยังไม่ทราบสถานะ'), findsOneWidget);
  });
}

Color _avatarOutlineColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(RelioUserAvatar),
          matching: find.byType(Container),
        )
        .first,
  );
  return (container.decoration! as BoxDecoration).border!.top.color;
}
