import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/relay/relay_engine.dart';
import 'package:relio_mobile/core/relay/relay_repository.dart';
import 'package:relio_mobile/core/relay/relay_route_planner.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

import 'support/nearby_pair.dart' show waitFor;

class _Wire extends MockNearbyTransport {
  _Wire(this.device, this.network) : super(autoAcknowledge: false);
  final String device;
  final Map<String, _Node> network;
  final routes = <String>[];
  @override
  Future<String?> sendBytes(
    Uint8List bytes, {
    String? peerId,
    bool capturePayloadDiagnostics = false,
  }) async {
    final result = await super.sendBytes(bytes, peerId: peerId);
    if (peerId == null || !network.containsKey(peerId)) return result;
    final packet = RelioPacket.fromBytes(bytes);
    if (packet.type == RelioPacketType.relayEnvelope ||
        packet.type == RelioPacketType.textMessage) {
      routes.add('$device->$peerId:${packet.type.name}');
    }
    scheduleMicrotask(
      () =>
          network[peerId]!.wire.simulateIncoming(peerId: device, bytes: bytes),
    );
    return result;
  }
}

class _Node {
  _Node(this.id, this.network);
  final String id;
  final Map<String, _Node> network;
  late AppDatabase db;
  late RelioRepositories repos;
  late RelioDeviceIdentityRepository identity;
  late _Wire wire;
  late NearbyService service;
  late RelayEngine relay;
  Future<void> initialize() async {
    db = AppDatabase.memory();
    repos = RelioRepositories(db);
    await repos.settings.setValue('device_id', id);
    identity = RelioDeviceIdentityRepository(db, profiles: repos.profiles);
    wire = _Wire(id, network);
    relay = RelayEngine(
      transport: wire,
      identity: identity,
      repository: DriftRelayRepository(db),
      messages: repos.messages,
      conversations: repos.conversations,
      connectedPeers: () => service.connectedPeers,
      deviceIdForEndpoint: (endpoint) => service.deviceIdForEndpoint(endpoint),
    );
    service = NearbyService(
      transport: wire,
      messages: repos.messages,
      conversations: repos.conversations,
      identity: identity,
      nearbyDevices: repos.nearbyDevices,
      settings: repos.settings,
      relayEngine: relay,
    );
    await service.initialize();
    await relay.initialize();
  }

  Future<void> close() async {
    await relay.dispose();
    await service.close();
    repos.profiles.dispose();
    await repos.ownerContext.dispose();
    await db.close();
  }
}

Future<void> _link(_Node a, _Node b) async {
  a.wire.simulatePeer(id: b.id, name: b.id);
  b.wire.simulatePeer(id: a.id, name: a.id);
  await Future<void>.delayed(Duration.zero);
  await a.service.connect(b.id);
  await b.service.connect(a.id);
  await waitFor(
    () =>
        a.service.isDeviceConnected(b.id) && b.service.isDeviceConnected(a.id),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [2, 3, 4, 5]) {
    test(
      'QA automatic text delivery with $size nodes preserves local-first and one route',
      () async {
        final network = <String, _Node>{};
        for (var index = 0; index < size; index++) {
          final id = 'device-$index';
          network[id] = _Node(id, network);
          await network[id]!.initialize();
        }
        addTearDown(() async {
          for (final node in network.values) {
            await node.close();
          }
        });
        final a = network['device-0']!;
        final c = network['device-${size - 1}']!;
        if (size == 2) {
          await _link(a, c);
        } else {
          for (var index = 1; index < size - 1; index++) {
            await _link(a, network['device-$index']!);
            await _link(network['device-$index']!, c);
          }
        }
        final principal = (await c.repos.profiles.current()).principalId;
        final conversation = await a.repos.conversations.ensureConversation(
          id: 'to-final',
          participantId: c.id,
          remotePrincipalId: principal,
          displayName: 'Final recipient',
          participantStatus: DeviceStatus.normal,
        );
        final message = await a.repos.messages.createOutgoingText(
          conversationId: conversation.id,
          senderId: a.id,
          senderDeviceId: a.id,
          text: 'RELIO QA AUTOMATIC ROUTE',
        );
        expect(
          (await a.repos.messages.getMessage(message.id))!.status,
          DeliveryStatus.pending,
        );
        await a.service.configureTextRouteMode(RelayTextRouteMode.automatic);
        await a.service.sendMessage(message);
        await waitFor(
          () async =>
              (await a.repos.messages.getMessage(message.id))?.status ==
              DeliveryStatus.delivered,
        );
        expect(
          (await c.repos.messages.getMessage(message.id))?.text,
          message.text,
        );
        if (size > 2) {
          expect(
            a.wire.routes
                .where((route) => route.endsWith('relayEnvelope'))
                .single,
            'device-0->device-1:relayEnvelope',
          );
          expect(
            await network['device-1']!.repos.messages.getMessage(message.id),
            isNull,
          );
          await a.service.sendMessage(message);
          expect(
            a.wire.routes.where((route) => route.endsWith('relayEnvelope')),
            hasLength(1),
          );
          await a.service.configureTextRouteMode(RelayTextRouteMode.directOnly);
          final waiting = await a.repos.messages.createOutgoingText(
            conversationId: conversation.id,
            senderId: a.id,
            senderDeviceId: a.id,
            text: 'RELIO QA DIRECT ONLY WAIT',
          );
          await a.service.sendMessage(waiting);
          expect(
            (await a.repos.messages.getMessage(waiting.id))?.status,
            DeliveryStatus.pending,
          );
          expect(
            a.wire.routes.where((route) => route.endsWith('relayEnvelope')),
            hasLength(1),
          );
          await _link(a, c);
          await waitFor(
            () async =>
                (await a.repos.messages.getMessage(waiting.id))?.status ==
                DeliveryStatus.delivered,
          );
          expect(
            a.wire.routes.where((route) => route.endsWith('textMessage')),
            isNotEmpty,
          );

          await a.service.configureTextRouteMode(
            RelayTextRouteMode.qaForcedRelay,
            forcedMiddleDeviceId: size > 3 ? 'device-2' : 'device-1',
          );
          final forced = await a.repos.messages.createOutgoingText(
            conversationId: conversation.id,
            senderId: a.id,
            senderDeviceId: a.id,
            text: 'RELIO QA CHANGE MIDDLE',
          );
          await a.service.sendMessage(forced);
          await waitFor(
            () async =>
                (await a.repos.messages.getMessage(forced.id))?.status ==
                DeliveryStatus.delivered,
          );
          final lastEnvelopeRoute = a.wire.routes
              .where((route) => route.endsWith('relayEnvelope'))
              .last;
          expect(
            lastEnvelopeRoute,
            'device-0->${size > 3 ? 'device-2' : 'device-1'}:relayEnvelope',
          );
          final locked = await a.relay.repository.getForPayload(
            a.id,
            forced.id,
          );
          expect(locked?.envelope.maxHops, 2);
          await a.service.configureTextRouteMode(RelayTextRouteMode.automatic);
          await a.service.sendMessage(forced);
          expect(
            (await a.relay.repository.getForPayload(
              a.id,
              forced.id,
            ))?.envelope.packetId,
            locked?.envelope.packetId,
          );
        }
      },
      skip: !RelioBuildInfo.isTest,
    );
  }
}
