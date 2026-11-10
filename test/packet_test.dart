import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/nearby/peer_identity_crypto.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/core/relay/relay_models.dart';

void main() {
  test('avatar file transfer metadata is bounded and backward tolerant', () {
    final revision = 'a' * 64;
    final request = RelioPacket.deviceStatus(
      senderDeviceId: 'device-a',
      senderUserId: 'user-a',
      displayName: 'A',
      status: DeviceStatus.normal,
      avatarRevision: revision,
      avatarAction: 'request',
    );
    expect(
      RelioPacket.fromBytes(request.toBytes()).payload['avatarAction'],
      'request',
    );

    final transfer = RelioPacket.deviceStatus(
      senderDeviceId: 'device-a',
      senderUserId: 'user-a',
      displayName: 'A',
      status: DeviceStatus.normal,
      avatarRevision: revision,
      avatarAction: 'transfer',
      avatarTransferId: 'transfer-a',
      avatarPayloadId: '17',
      avatarByteSize: 16 * 1024,
      avatarSha256: revision,
    );
    expect(
      RelioPacket.fromBytes(transfer.toBytes()).payload['avatarByteSize'],
      16 * 1024,
    );
    final malformed =
        jsonDecode(utf8.decode(transfer.toBytes())) as Map<String, dynamic>;
    (malformed['payload'] as Map<String, dynamic>)['avatarByteSize'] =
        65 * 1024;
    expect(
      () => RelioPacket.fromBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(malformed))),
      ),
      throwsA(isA<RelioPacketException>()),
    );
  });

  test('QA relay route check fields are bounded and typed', () {
    final check = RelioPacket.deviceStatus(
      senderDeviceId: 'device-a',
      senderUserId: 'user-a',
      displayName: 'A',
      status: DeviceStatus.normal,
      qaRelayCheckId: '12345678-1234-1234-1234-123456789abc',
      qaRelayDestinationHash: 'a' * 64,
      qaRelayConnected: true,
    );
    expect(
      RelioPacket.fromBytes(check.toBytes()).payload['qaRelayConnected'],
      isTrue,
    );
    final malformed =
        jsonDecode(utf8.decode(check.toBytes())) as Map<String, dynamic>;
    (malformed['payload'] as Map<String, dynamic>)['qaRelayConnected'] = 'yes';
    expect(
      () => RelioPacket.fromBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(malformed))),
      ),
      throwsA(isA<RelioPacketException>()),
    );
    (malformed['payload'] as Map<String, dynamic>)['qaRelayConnected'] = true;
    (malformed['payload'] as Map<String, dynamic>)['qaRelayDestinationHash'] =
        'bad';
    expect(
      () => RelioPacket.fromBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(malformed))),
      ),
      throwsA(isA<RelioPacketException>()),
    );
  });

  test('QA relay route request path is bounded and sender-bound', () {
    final request = RelioPacket.deviceStatus(
      senderDeviceId: 'device-a',
      senderUserId: 'user-a',
      displayName: 'A',
      status: DeviceStatus.normal,
      qaRelayCheckId: '12345678-1234-1234-1234-123456789abc',
      qaRelayDestinationHash: 'a' * 64,
      qaRelayPath: const ['device-origin', 'device-a'],
      qaRelayMaxHops: 7,
    );
    expect(RelioPacket.fromBytes(request.toBytes()).payload['qaRelayPath'], [
      'device-origin',
      'device-a',
    ]);

    final malformed =
        jsonDecode(utf8.decode(request.toBytes())) as Map<String, dynamic>;
    (malformed['payload'] as Map<String, dynamic>)['qaRelayPath'] = [
      'device-origin',
      'device-b',
    ];
    expect(
      () => RelioPacket.fromBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(malformed))),
      ),
      throwsA(isA<RelioPacketException>()),
    );
  });

  test('identity challenge packet is versioned and bounded', () {
    final nonce = List.filled(43, 'A').join();
    final packet = RelioPacket.identityChallenge(
      senderDeviceId: 'device-a',
      senderUserId: 'user-a',
      challengeId: 'challenge-1',
      nonce: nonce,
      targetDeviceId: 'device-b',
      expiresAt: DateTime.utc(2026, 9, 30, 12),
    );
    final decoded = RelioPacket.fromBytes(packet.toBytes());
    expect(decoded.protocolVersion, 2);
    expect(decoded.type, RelioPacketType.identityChallenge);
    expect(decoded.payload['nonce'], nonce);
  });

  test(
    'first-contact identity challenge permits an unknown target device ID',
    () {
      final packet = RelioPacket.identityChallenge(
        senderDeviceId: 'device-a',
        senderUserId: 'user-a',
        challengeId: 'first-contact',
        nonce: List.filled(43, 'B').join(),
        targetDeviceId: '',
        expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
      );

      final decoded = RelioPacket.fromBytes(packet.toBytes());
      expect(decoded.payload['targetDeviceId'], isEmpty);
    },
  );

  test(
    'protocol v2 cannot be used to bypass identity proof for chat packets',
    () {
      final json =
          jsonDecode(
                utf8.decode(
                  RelioPacket.hello(
                    senderDeviceId: 'device-a',
                    senderUserId: 'user-a',
                    displayName: 'RELIO',
                  ).toBytes(),
                ),
              )
              as Map<String, dynamic>;
      json['protocolVersion'] = 2;
      expect(
        () => RelioPacket.fromJson(json),
        throwsA(isA<RelioPacketException>()),
      );
    },
  );

  test('identity signature context changes with either peer or nonce', () {
    final original = identityChallengeMessage(
      challengeId: 'challenge',
      nonce: 'nonce',
      challengerDeviceId: 'device-a',
      responderDeviceId: 'device-b',
    );
    expect(
      identityChallengeMessage(
        challengeId: 'challenge',
        nonce: 'changed',
        challengerDeviceId: 'device-a',
        responderDeviceId: 'device-b',
      ),
      isNot(equals(original)),
    );
    expect(
      identityChallengeMessage(
        challengeId: 'challenge',
        nonce: 'nonce',
        challengerDeviceId: 'device-a',
        responderDeviceId: 'device-c',
      ),
      isNot(equals(original)),
    );
  });

  test('hello packet encodes and decodes with protocol version 1', () {
    final packet = RelioPacket.hello(
      senderDeviceId: 'device-1',
      senderUserId: 'minnie',
      displayName: 'มินนี่',
    );

    final decoded = RelioPacket.fromBytes(packet.toBytes());
    expect(decoded.protocolVersion, 1);
    expect(decoded.packetId, packet.packetId);
    expect(decoded.type, RelioPacketType.hello);
    expect(decoded.payload['displayName'], 'มินนี่');
  });

  test('text message packet contains persistence fields', () {
    final packet = RelioPacket.textMessage(
      senderDeviceId: 'device-1',
      senderUserId: 'minnie',
      messageId: 'message-1',
      conversationId: 'conversation-1',
      text: 'Hello RELIO',
      timestamp: DateTime.utc(2026, 9, 24, 10, 20),
    );

    final json =
        jsonDecode(utf8.decode(packet.toBytes())) as Map<String, dynamic>;
    final decoded = RelioPacket.fromJson(json);
    expect(decoded.payload['messageId'], 'message-1');
    expect(decoded.payload['conversationId'], 'conversation-1');
    expect(decoded.payload['text'], 'Hello RELIO');
  });

  test('ack packet references packet and message', () {
    final packet = RelioPacket.ack(
      senderDeviceId: 'device-2',
      senderUserId: 'peer',
      acknowledgedPacketId: 'packet-1',
      messageId: 'message-1',
    );

    expect(RelioPacket.fromBytes(packet.toBytes()).payload, {
      'packetId': 'packet-1',
      'messageId': 'message-1',
    });
  });

  test('hello and device status carry stable peer identity and status', () {
    final hello = RelioPacket.hello(
      senderDeviceId: 'device-1',
      senderUserId: 'minnie',
      displayName: 'มินนี่',
      status: DeviceStatus.rescue,
    );
    final decodedHello = RelioPacket.fromBytes(hello.toBytes());
    expect(decodedHello.payload['status'], 'rescue');
    expect(decodedHello.payload['capabilities'], isA<List<dynamic>>());

    final status = RelioPacket.deviceStatus(
      senderDeviceId: 'device-1',
      senderUserId: 'minnie',
      displayName: 'มินนี่',
      status: DeviceStatus.sos,
    );
    expect(RelioPacket.fromBytes(status.toBytes()).payload['status'], 'sos');
  });

  test('SOS packet encodes optional location and active state', () {
    final packet = RelioPacket.sos(
      senderDeviceId: 'device-1',
      senderUserId: 'minnie',
      displayName: 'มินนี่',
      sosId: 'sos-1',
      message: 'need help',
      latitude: 13.7,
      longitude: 100.5,
      createdAt: DateTime.utc(2026, 9, 25),
      isActive: true,
      stateRevision: 4,
    );

    final decoded = RelioPacket.fromBytes(packet.toBytes());
    expect(decoded.type, RelioPacketType.sos);
    expect(decoded.payload['sosId'], 'sos-1');
    expect(decoded.payload['isActive'], isTrue);
    expect(decoded.payload['latitude'], 13.7);
    expect(decoded.payload['stateRevision'], 4);
  });

  test('rescue status packet is bounded and supported by relay envelopes', () {
    final packet = RelioPacket.rescueStatus(
      senderDeviceId: 'device-a',
      senderUserId: 'user-a',
      rescueId: 'rescue-a-1',
      displayName: 'A',
      rescueActive: true,
      updatedAt: DateTime.utc(2026, 11, 10),
      stateRevision: 1,
    );
    final decoded = RelioPacket.fromBytes(packet.toBytes());
    expect(decoded.type, RelioPacketType.rescueStatus);
    expect(decoded.payload['rescueActive'], isTrue);

    final envelope = RelayEnvelope.fromPayloadPacket(
      packet: packet,
      destinationDeviceId: 'device-c',
      maxHops: 2,
    );
    expect(const RelayPolicy().validate(envelope), isNull);
    expect(envelope.toPayloadPacket().payload['stateRevision'], 1);
  });

  test(
    'malformed, unknown, unsupported, and incomplete packets fail safely',
    () {
      expect(
        () => RelioPacket.fromBytes(Uint8List.fromList(utf8.encode('{bad'))),
        throwsA(isA<RelioPacketException>()),
      );
      expect(
        () => RelioPacket.fromJson({
          'protocolVersion': 1,
          'packetId': 'p1',
          'type': 'unknown',
          'senderDeviceId': 'd1',
          'senderUserId': 'u1',
          'createdAt': DateTime.now().toIso8601String(),
          'payload': {},
        }),
        throwsA(isA<RelioPacketException>()),
      );
      expect(
        () => RelioPacket.fromJson({
          'protocolVersion': 1,
          'packetId': 'p1',
          'type': 'sos',
          'senderDeviceId': 'd1',
          'senderUserId': 'u1',
          'createdAt': DateTime.now().toIso8601String(),
          'payload': {
            'sosId': 's1',
            'ownerDeviceId': 'd1',
            'ownerUserId': 'u1',
            'displayName': 'Peer',
            'isActive': 'yes',
            'createdAt': DateTime.now().toIso8601String(),
          },
        }),
        throwsA(isA<RelioPacketException>()),
      );
      expect(
        () => RelioPacket.fromJson({'protocolVersion': 2}),
        throwsA(isA<RelioPacketException>()),
      );
      expect(
        () => RelioPacket.fromJson({
          'protocolVersion': 1,
          'packetId': 'p1',
          'type': 'textMessage',
          'senderDeviceId': 'd1',
          'senderUserId': 'u1',
          'createdAt': DateTime.now().toIso8601String(),
          'payload': {},
        }),
        throwsA(isA<RelioPacketException>()),
      );
    },
  );
}
