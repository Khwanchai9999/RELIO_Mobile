import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/environment.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/nearby/relio_packet.dart';
import '../../core/relio_dependencies.dart';
import '../../core/relay/relay_models.dart';
import '../../shared/widgets/relio_widgets.dart';

class RelayDiagnosticsScreen extends StatefulWidget {
  const RelayDiagnosticsScreen({super.key});

  @override
  State<RelayDiagnosticsScreen> createState() => _RelayDiagnosticsScreenState();
}

class _RelayDiagnosticsScreenState extends State<RelayDiagnosticsScreen> {
  late RelioDependencies _dependencies;
  Future<int>? _packetCount;
  Future<List<_RelayRecipient>>? _recipients;
  String? _selectedConversationId;
  String? _relayTestResult;
  bool _sendingRelayTest = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _dependencies = RelioDependencyScope.of(context);
    _refresh();
  }

  Future<List<_RelayRecipient>> _loadRecipients() async {
    final conversations = await _dependencies.repositories.conversations
        .listConversations();
    final recipients = <_RelayRecipient>[];
    for (final conversation in conversations) {
      final principal = await _dependencies.repositories.conversations
          .remotePrincipalForConversation(conversation.id);
      if (RelioPacket.validPrincipal(principal)) {
        recipients.add(
          _RelayRecipient(conversation: conversation, principalId: principal!),
        );
      }
    }
    return recipients;
  }

  void _refresh() {
    setState(() {
      _packetCount = _dependencies.relayRepository.packetCount();
      _recipients = _loadRecipients();
    });
  }

  String? _routeBlock(_RelayRecipient? recipient) {
    if (recipient == null) return 'เลือกผู้รับที่มี principal mapping ก่อน';
    final peers = _dependencies.nearbyService.connectedPeers;
    if (peers.length != 1) {
      return 'ต้องเชื่อมต่อ next-hop ที่ยืนยัน identity เพียงหนึ่งเครื่อง';
    }
    final peer = peers.single;
    if (peer.deviceId == recipient.conversation.participantId) {
      return 'ผู้รับเชื่อมต่อโดยตรงอยู่ จึงไม่ส่ง relay test';
    }
    if (peer.deviceId == null || !peer.capabilities.contains('relay-v1')) {
      return 'next-hop ไม่มี verified device identity หรือ relay-v1';
    }
    return null;
  }

  Future<void> _sendSyntheticRelay(_RelayRecipient recipient) async {
    final blocked = _routeBlock(recipient);
    if (blocked != null) {
      setState(() => _relayTestResult = 'BLOCKED: $blocked');
      return;
    }
    setState(() {
      _sendingRelayTest = true;
      _relayTestResult = null;
    });
    try {
      final identity = _dependencies.identity;
      final profile = await identity.profiles.current();
      final senderDeviceId = await identity.getDeviceId();
      final messageId = const Uuid().v4();
      final createdAt = DateTime.now().toUtc();
      final packet =
          RelioPacket.textMessage(
            senderDeviceId: senderDeviceId,
            senderUserId:
                _dependencies.cloudDataSource.currentIdentity?.userId ??
                senderDeviceId,
            messageId: messageId,
            conversationId: recipient.conversation.id,
            text: 'RELIO QA RELAY TEST $messageId',
            timestamp: createdAt,
          ).withPrincipals(
            profile.principalId,
            recipient.principalId,
            profileRevision: profile.revision,
          );
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: packet,
        destinationDeviceId: recipient.conversation.participantId,
      );
      final result = await _dependencies.relayEngine.enqueueEnvelope(envelope);
      final record = await _dependencies.relayRepository.getPacket(
        envelope.packetId,
      );
      if (!mounted) return;
      setState(() {
        _relayTestResult =
            'result=${result.name} state=${record?.state.name ?? 'missing'} '
            'packetId=${envelope.packetId} payloadId=$messageId';
        _packetCount = _dependencies.relayRepository.packetCount();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _relayTestResult = 'BLOCKED: $error');
    } finally {
      if (mounted) setState(() => _sendingRelayTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(
        title: 'Relay Diagnostics',
        subtitle: 'DEV / QA only • relay-v1',
        onBack: () => context.pop(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const ListTile(
              leading: Icon(Icons.route_outlined),
              title: Text('Bounded store-and-forward'),
              subtitle: Text(
                'ไม่แสดงข้อความ พิกัด หรือ payload ของ relay ใน diagnostics ปกติ',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<int>(
            future: _packetCount,
            builder: (context, snapshot) => RelioSettingTile(
              icon: Icons.inventory_2_outlined,
              title: 'Persisted relay packets',
              subtitle: snapshot.data?.toString() ?? 'กำลังโหลด...',
            ),
          ),
          _buildQaRelayProbe(),
          const SizedBox(height: 12),
          RelioSettingTile(
            icon: Icons.sync_outlined,
            title: 'Forward pending packets',
            subtitle: 'ส่งต่อผ่าน peer ที่ผ่าน hello และมี relay-v1 เท่านั้น',
            onTap: () async {
              await _dependencies.relayEngine.forwardPending();
              if (mounted) _refresh();
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildQaRelayProbe() {
    if (!RelioBuildInfo.isTest ||
        _dependencies.transport is MockNearbyTransport) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'QA-only relay probe',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'ส่งข้อความสังเคราะห์ relay-v1 เท่านั้น ต้องมี next-hop ที่ยืนยันแล้วหนึ่งเครื่อง และผู้รับต้องไม่เชื่อมต่อโดยตรง',
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<_RelayRecipient>>(
              future: _recipients,
              builder: (context, snapshot) {
                final recipients = snapshot.data ?? const <_RelayRecipient>[];
                final selected = recipients
                    .where(
                      (item) => item.conversation.id == _selectedConversationId,
                    )
                    .firstOrNull;
                final block = _routeBlock(selected);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedConversationId),
                      initialValue: selected?.conversation.id,
                      decoration: const InputDecoration(
                        labelText: 'Verified recipient',
                      ),
                      items: recipients
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.conversation.id,
                              child: Text(item.conversation.participantId),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _sendingRelayTest
                          ? null
                          : (id) =>
                                setState(() => _selectedConversationId = id),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.connectionState == ConnectionState.waiting
                          ? 'กำลังตรวจสอบ principal mapping…'
                          : block ??
                                'Route guard ผ่าน: ไม่มี direct recipient connection',
                    ),
                    if (_relayTestResult != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(_relayTestResult!),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed:
                          selected == null || block != null || _sendingRelayTest
                          ? null
                          : () => _sendSyntheticRelay(selected),
                      icon: const Icon(Icons.route_outlined),
                      label: Text(
                        _sendingRelayTest
                            ? 'กำลังส่ง…'
                            : 'Send synthetic relay text',
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RelayRecipient {
  const _RelayRecipient({
    required this.conversation,
    required this.principalId,
  });

  final RelioConversation conversation;
  final String principalId;
}
