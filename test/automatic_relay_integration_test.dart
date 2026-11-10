import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/relay/relay_engine.dart';
import 'package:relio_mobile/core/relay/relay_models.dart';
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
  final attempts = <String>[];
  String? failNextPeer;
  String? deliverThenFailPeer;
  String? omitHelloPrincipalFor;
  @override
  Future<String?> sendBytes(
    Uint8List bytes, {
    String? peerId,
    bool capturePayloadDiagnostics = false,
  }) async {
    final packet = RelioPacket.fromBytes(bytes);
    final outboundBytes =
        packet.type == RelioPacketType.hello && peerId == omitHelloPrincipalFor
        ? Uint8List.fromList(
            utf8.encode(jsonEncode(packet.toJson()..remove('senderPrincipal'))),
          )
        : bytes;
    if (peerId != null &&
        (packet.type == RelioPacketType.relayEnvelope ||
            packet.type == RelioPacketType.textMessage)) {
      attempts.add('$device->$peerId:${packet.type.name}');
      if (failNextPeer == peerId &&
          packet.type == RelioPacketType.textMessage) {
        failNextPeer = null;
        throw StateError('simulated direct transport failure');
      }
    }
    final failAfterDelivery =
        deliverThenFailPeer == peerId &&
        packet.type == RelioPacketType.textMessage;
    if (failAfterDelivery) deliverThenFailPeer = null;
    final result = await super.sendBytes(outboundBytes, peerId: peerId);
    if (peerId == null || !network.containsKey(peerId)) return result;
    if (packet.type == RelioPacketType.relayEnvelope ||
        packet.type == RelioPacketType.textMessage) {
      routes.add('$device->$peerId:${packet.type.name}');
    }
    scheduleMicrotask(() {
      final receiver = network[peerId];
      if (receiver == null || receiver.closing) return;
      receiver.wire.simulateIncoming(peerId: device, bytes: outboundBytes);
    });
    if (failAfterDelivery) {
      throw StateError('simulated ambiguous direct transport failure');
    }
    return result;
  }
}

class _Node {
  _Node(this.id, this.network, {this.strictQa = false});
  final String id;
  final Map<String, _Node> network;
  final bool strictQa;
  late AppDatabase db;
  late RelioRepositories repos;
  late RelioDeviceIdentityRepository identity;
  late _Wire wire;
  late NearbyService service;
  late RelayEngine relay;
  bool reachabilityAllowed = false;
  bool forwardingPaused = false;
  bool closing = false;
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
      secureRelayEnabled: strictQa ? () => false : null,
      qaPlaintextTextAllowed: strictQa
          ? () => service.qaPlaintextTextEnabled
          : null,
      relayParticipationAllowed: strictQa
          ? () async => reachabilityAllowed
          : null,
      qaTextForwardingPaused: () => forwardingPaused,
      connectedPeers: () => service.authenticatedConnectedPeers,
      deviceIdForEndpoint: (endpoint) => service.deviceIdForEndpoint(endpoint),
      nextHopHasRoute: (nextHop, destination, maxHops) =>
          service.checkQaRelayRoute(
            middleDeviceId: nextHop,
            destinationDeviceId: destination,
            maxHops: maxHops,
          ),
    );
    service = NearbyService(
      transport: wire,
      messages: repos.messages,
      conversations: repos.conversations,
      identity: identity,
      nearbyDevices: repos.nearbyDevices,
      settings: repos.settings,
      relayEngine: relay,
      reachabilityRelayAllowed: () async => reachabilityAllowed,
    );
    await service.initialize();
    await relay.initialize();
  }

  Future<void> close() async {
    closing = true;
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
  test(
    'plaintext envelope is rejected before storage when QA mode is off',
    () async {
      final network = <String, _Node>{};
      final destination = network['B'] = _Node('B', network, strictQa: true);
      await destination.initialize();
      addTearDown(destination.close);
      if (!RelioBuildInfo.isTest) {
        await expectLater(
          destination.service.configureTextRouteMode(
            RelayTextRouteMode.automatic,
          ),
          throwsStateError,
        );
      }
      final packet =
          RelioPacket.textMessage(
            senderDeviceId: 'A',
            senderUserId: 'A',
            messageId: 'plain-text',
            conversationId: 'chat',
            text: 'QA-only',
            timestamp: DateTime.now(),
          ).withPrincipals(
            'guest:origin',
            (await destination.repos.profiles.current()).principalId,
          );
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: packet,
        destinationDeviceId: destination.id,
      ).copyWith(hopCount: 1, previousHopDeviceId: 'A');
      final outer = RelioPacket.relayEnvelope(
        senderDeviceId: 'A',
        senderUserId: 'relay',
        relayPacketId: envelope.packetId,
        relayPayload: envelope.toJson(),
      );
      expect(
        await destination.relay.handleIncomingPacket('A', outer),
        RelayResult.blocked,
      );
      expect(
        await destination.relay.repository.getPacket(envelope.packetId),
        isNull,
      );
      expect(await destination.repos.messages.getMessage('plain-text'), isNull);
    },
  );
  for (final size in [3, 4]) {
    test(
      'discovered QA chat delivers ordered text across $size devices',
      () async {
        final network = <String, _Node>{};
        for (final id in ['A', 'B', 'C', if (size == 4) 'D']) {
          final node = network[id] = _Node(id, network, strictQa: true);
          await node.initialize();
          addTearDown(node.close);
        }
        final nodes = network.values.toList();
        final a = nodes.first;
        final b = nodes[1];
        final c = nodes[2];
        final destination = nodes.last;
        expect(a.service.qaPlaintextTextEnabled, isFalse);
        for (final node in nodes) {
          node.reachabilityAllowed = node != a && node != destination;
          await node.service.configureTextRouteMode(
            RelayTextRouteMode.automatic,
          );
        }
        for (var i = 1; i < nodes.length; i++) {
          await _link(nodes[i - 1], nodes[i]);
        }
        await waitFor(
          () => a.service.remoteReachablePeers.any(
            (peer) => peer.deviceId == destination.id,
          ),
        );
        final chat = (await a.service.openRemoteTextConversation(
          destination.id,
        ))!;
        expect(
          await a.repos.conversations.remotePrincipalForConversation(chat.id),
          (await destination.repos.profiles.current()).principalId,
        );
        b.reachabilityAllowed = false;
        expect(
          await a.service.openRemoteTextConversation(destination.id),
          isNull,
        );
        final first = await a.repos.messages.createOutgoingText(
          conversationId: chat.id,
          senderId: a.id,
          senderDeviceId: a.id,
          text: 'first',
        );
        await a.service.sendMessage(first);
        expect(
          (await a.repos.messages.getMessage(first.id))?.status,
          DeliveryStatus.pending,
        );
        expect(a.wire.routes, isEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 15));
        final second = await a.repos.messages.createOutgoingText(
          conversationId: chat.id,
          senderId: a.id,
          senderDeviceId: a.id,
          text: 'second',
        );
        b.reachabilityAllowed = true;
        b.forwardingPaused = true;
        await Future.wait([
          a.service.sendMessage(first),
          a.service.sendMessage(second),
        ]);
        await waitFor(
          () async =>
              (await a.repos.messages.getMessage(first.id))?.status ==
                  DeliveryStatus.nearbySent &&
              (await a.repos.messages.getMessage(second.id))?.status ==
                  DeliveryStatus.nearbySent,
        );
        expect(b.wire.routes, isEmpty);
        b.wire.simulateConnectionLoss(c.id);
        c.wire.simulateConnectionLoss(b.id);
        await waitFor(() => !b.service.isDeviceConnected(c.id));
        b.reachabilityAllowed = false;
        b.forwardingPaused = false;
        await b.relay.forwardPending();
        expect(
          (await a.repos.messages.getMessage(first.id))?.status,
          DeliveryStatus.nearbySent,
        );
        await _link(b, c);
        await b.relay.forwardPending();
        expect(b.wire.routes, isEmpty);
        b.wire.simulateConnectionLoss(c.id);
        c.wire.simulateConnectionLoss(b.id);
        await waitFor(() => !b.service.isDeviceConnected(c.id));
        b.reachabilityAllowed = true;
        await _link(b, c);
        await waitFor(
          () async =>
              (await a.repos.messages.getMessage(first.id))?.status ==
                  DeliveryStatus.delivered &&
              (await a.repos.messages.getMessage(second.id))?.status ==
                  DeliveryStatus.delivered,
        );
        final received = [
          for (final chat
              in await destination.repos.conversations.listConversations())
            ...await destination.repos.messages.listMessages(chat.id),
        ];
        expect(received.map((message) => message.text), ['first', 'second']);
        final lastHop = nodes[size - 2];
        final duplicate = lastHop.wire.sentPayloads.firstWhere(
          (bytes) =>
              RelioPacket.fromBytes(bytes).type ==
              RelioPacketType.relayEnvelope,
        );
        expect(
          await destination.relay.handleIncomingBytes(lastHop.id, duplicate),
          RelayResult.duplicate,
        );
        expect(
          (await destination.repos.messages.getMessage(first.id))?.text,
          'first',
        );
        for (final middle in nodes.skip(1).take(size - 2)) {
          for (final chat
              in await middle.repos.conversations.listConversations()) {
            expect(await middle.repos.messages.listMessages(chat.id), isEmpty);
          }
        }
      },
      skip: !RelioBuildInfo.isTest,
    );
  }
  test(
    'Nearby discovers A-B-C-D with consent and withdraws broken routes',
    () async {
      final network = <String, _Node>{};
      for (final id in ['A', 'B', 'C', 'D']) {
        final node = network[id] = _Node(id, network);
        await node.initialize();
        addTearDown(node.close);
      }
      final a = network['A']!;
      final b = network['B']!;
      final c = network['C']!;
      final d = network['D']!;
      await _link(a, b);
      await _link(b, c);
      await _link(c, d);
      expect(a.service.reachablePeerCount, 1);
      b.reachabilityAllowed = true;
      c.reachabilityAllowed = true;
      b.service.refreshReachabilityConsent();
      c.service.refreshReachabilityConsent();
      await waitFor(() => a.service.reachablePeerCount == 3);
      expect(a.service.connectedPeerCount, 1);
      expect(
        a.service.remoteReachablePeers.map(
          (peer) => (peer.deviceId, peer.hops),
        ),
        [('C', 2), ('D', 3)],
      );

      await _link(a, c);
      expect(a.service.reachablePeerCount, 3);
      expect(a.service.connectedPeerCount, 2);
      await waitFor(
        () => a.service.remoteReachablePeers.singleOrNull?.hops == 2,
      );
      a.wire.simulateConnectionLoss(c.id);
      c.wire.simulateConnectionLoss(a.id);
      await waitFor(
        () =>
            a.service.connectedPeerCount == 1 &&
            a.service.remoteReachablePeers.any(
              (peer) => peer.deviceId == 'D' && peer.hops == 3,
            ),
      );

      c.wire.simulateConnectionLoss(d.id);
      d.wire.simulateConnectionLoss(c.id);
      await waitFor(() => a.service.reachablePeerCount == 2);
      await _link(c, d);
      await waitFor(() => a.service.reachablePeerCount == 3);
      b.reachabilityAllowed = false;
      b.service.refreshReachabilityConsent();
      await waitFor(() => a.service.reachablePeerCount == 1);
    },
  );
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

  test(
    'QA automatic routing discovers and sends through a multi-hop chain',
    () async {
      final network = <String, _Node>{};
      for (final id in [
        'device-a',
        'device-b',
        'device-c',
        'device-d',
        'device-e',
      ]) {
        network[id] = _Node(id, network);
        await network[id]!.initialize();
      }
      addTearDown(() async {
        for (final node in network.values) {
          await node.close();
        }
      });

      final a = network['device-a']!;
      final b = network['device-b']!;
      final c = network['device-c']!;
      final d = network['device-d']!;
      final e = network['device-e']!;
      await _link(a, b);
      await _link(b, c);
      await _link(c, d);

      final recipientPrincipal = (await e.repos.profiles.current()).principalId;
      final conversation = await a.repos.conversations.ensureConversation(
        id: 'four-hop-chain',
        participantId: e.id,
        remotePrincipalId: recipientPrincipal,
        displayName: 'Final recipient',
        participantStatus: DeviceStatus.normal,
      );
      final message = await a.repos.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: a.id,
        senderDeviceId: a.id,
        text: 'RELIO QA MULTI HOP',
      );

      await a.service.configureTextRouteMode(RelayTextRouteMode.automatic);
      final beforeFinalLink = await a.service.planTextRoute(e.id);
      expect(beforeFinalLink.kind, RelayRouteKind.unavailable);

      await _link(d, e);
      final discovered = await a.service.planTextRoute(e.id);
      expect(discovered.kind, RelayRouteKind.relay);
      expect(discovered.firstHopDeviceId, b.id);

      await a.service.sendMessage(message);
      await waitFor(
        () async =>
            (await a.repos.messages.getMessage(message.id))?.status ==
            DeliveryStatus.delivered,
      );

      expect(
        (await a.relay.repository.getForPayload(
          a.id,
          message.id,
        ))?.envelope.maxHops,
        RelayPolicy.qaAutomaticTextMaxHops,
      );
      for (final node in [b, c, d]) {
        expect(await node.repos.messages.getMessage(message.id), isNull);
      }

      final received = await e.repos.messages.getMessage(message.id);
      expect(received?.text, message.text);
      expect(
        (await e.repos.messages.listMessages(
          received!.conversationId!,
        )).where((item) => item.id == message.id),
        hasLength(1),
      );
      for (final node in [b, c, d]) {
        expect(await node.repos.messages.getMessage(message.id), isNull);
      }
      expect(a.wire.routes, contains('device-a->device-b:relayEnvelope'));
      expect(b.wire.routes, contains('device-b->device-c:relayEnvelope'));
      expect(c.wire.routes, contains('device-c->device-d:relayEnvelope'));
      expect(d.wire.routes, contains('device-d->device-e:relayEnvelope'));
    },
    skip: !RelioBuildInfo.isTest,
  );

  test(
    'automatic QA route does not require the middle to map the destination principal',
    () async {
      final network = <String, _Node>{};
      for (final id in ['device-a', 'device-b', 'device-c']) {
        network[id] = _Node(id, network, strictQa: true);
        await network[id]!.initialize();
        await network[id]!.service.configureTextRouteMode(
          RelayTextRouteMode.automatic,
        );
      }
      addTearDown(() async {
        for (final node in network.values) {
          await node.close();
        }
      });
      final a = network['device-a']!;
      final b = network['device-b']!;
      final c = network['device-c']!;
      b.reachabilityAllowed = true;
      // Simulate a verified C session at B whose Hello has not supplied a
      // usable principal mapping. The final recipient identity remains known
      // to A through the existing trusted conversation.
      c.wire.omitHelloPrincipalFor = b.id;
      await _link(a, b);
      await _link(b, c);
      await waitFor(
        () =>
            a.service.remoteReachablePeers.any((peer) => peer.deviceId == c.id),
      );
      final destinationPrincipal =
          (await c.repos.profiles.current()).principalId;
      final conversation = await a.repos.conversations.ensureConversation(
        id: 'missing-middle-principal',
        participantId: c.id,
        remotePrincipalId: destinationPrincipal,
        displayName: 'Final recipient',
        participantStatus: DeviceStatus.normal,
      );

      final plan = await a.service.planTextRoute(
        c.id,
        expectedPrincipal: destinationPrincipal,
      );
      expect(plan.kind, RelayRouteKind.relay);
      expect(plan.firstHopDeviceId, b.id);

      final message = await a.repos.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: a.id,
        senderDeviceId: a.id,
        text: 'QA automatic route principal propagation regression',
      );
      await a.service.sendMessage(message);
      await waitFor(
        () async =>
            (await a.repos.messages.getMessage(message.id))?.status ==
            DeliveryStatus.delivered,
      );
      expect(await c.repos.messages.getMessage(message.id), isNotNull);
      expect(b.wire.routes, contains('device-b->device-c:relayEnvelope'));
    },
    skip: !RelioBuildInfo.isTest,
  );

  test(
    'automatic route falls back to relay when direct send fails',
    () async {
      final network = <String, _Node>{};
      for (final id in ['device-a', 'device-b', 'device-c']) {
        network[id] = _Node(id, network);
        await network[id]!.initialize();
      }
      addTearDown(() async {
        for (final node in network.values) {
          await node.close();
        }
      });
      final a = network['device-a']!;
      final b = network['device-b']!;
      final c = network['device-c']!;
      await _link(a, b);
      await _link(b, c);
      await _link(a, c);
      a.wire.failNextPeer = c.id;

      final principal = (await c.repos.profiles.current()).principalId;
      final conversation = await a.repos.conversations.ensureConversation(
        id: 'fallback-to-c',
        participantId: c.id,
        remotePrincipalId: principal,
        displayName: 'C',
        participantStatus: DeviceStatus.normal,
      );
      final message = await a.repos.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: a.id,
        senderDeviceId: a.id,
        text: 'RELIO QA DIRECT FALLBACK',
      );

      await a.service.configureTextRouteMode(RelayTextRouteMode.automatic);
      await a.service.sendMessage(message);
      await waitFor(
        () async =>
            (await a.repos.messages.getMessage(message.id))?.status ==
            DeliveryStatus.delivered,
      );

      expect(a.wire.attempts.first, 'device-a->device-c:textMessage');
      expect(
        a.wire.routes.where((route) => route.endsWith('relayEnvelope')),
        contains('device-a->device-b:relayEnvelope'),
      );
      expect(
        b.wire.routes.where((route) => route.endsWith('relayEnvelope')),
        contains('device-b->device-c:relayEnvelope'),
      );
      expect(await c.repos.messages.getMessage(message.id), isNotNull);
      expect(await b.repos.messages.getMessage(message.id), isNull);
    },
    skip: !RelioBuildInfo.isTest,
  );

  test(
    'ambiguous direct failure and relay fallback materialize one recipient message',
    () async {
      final network = <String, _Node>{};
      for (final id in ['device-a', 'device-b', 'device-c']) {
        network[id] = _Node(id, network);
        await network[id]!.initialize();
      }
      addTearDown(() async {
        for (final node in network.values) {
          await node.close();
        }
      });
      final a = network['device-a']!;
      final b = network['device-b']!;
      final c = network['device-c']!;
      await _link(a, b);
      await _link(b, c);
      await _link(a, c);
      a.wire.deliverThenFailPeer = c.id;

      final principal = (await c.repos.profiles.current()).principalId;
      final conversation = await a.repos.conversations.ensureConversation(
        id: 'ambiguous-fallback-to-c',
        participantId: c.id,
        remotePrincipalId: principal,
        displayName: 'C',
        participantStatus: DeviceStatus.normal,
      );
      final message = await a.repos.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: a.id,
        senderDeviceId: a.id,
        text: 'RELIO QA AMBIGUOUS DIRECT FALLBACK',
      );

      await a.service.configureTextRouteMode(RelayTextRouteMode.automatic);
      await a.service.sendMessage(message);
      await waitFor(
        () async =>
            (await a.relay.repository.getForPayload(a.id, message.id))?.state ==
            RelayPacketState.delivered,
      );

      expect(a.wire.routes, contains('device-a->device-c:textMessage'));
      expect(a.wire.routes, contains('device-a->device-b:relayEnvelope'));
      expect(b.wire.routes, contains('device-b->device-c:relayEnvelope'));
      final received = await c.repos.messages.getMessage(message.id);
      expect(received, isNotNull);
      final recipientMessages = await c.repos.messages.listMessages(
        received!.conversationId!,
      );
      expect(
        recipientMessages.where((item) => item.id == message.id),
        hasLength(1),
      );
      expect(await b.repos.messages.getMessage(message.id), isNull);
    },
    skip: !RelioBuildInfo.isTest,
  );
}
