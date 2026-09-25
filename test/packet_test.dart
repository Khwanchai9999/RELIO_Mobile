import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
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
    );

    final decoded = RelioPacket.fromBytes(packet.toBytes());
    expect(decoded.type, RelioPacketType.sos);
    expect(decoded.payload['sosId'], 'sos-1');
    expect(decoded.payload['isActive'], isTrue);
    expect(decoded.payload['latitude'], 13.7);
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
