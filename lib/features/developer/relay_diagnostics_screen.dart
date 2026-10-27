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
  String? _selectedMiddleId;
  String? _readyRoute;
  String _routeStatus = 'เลือกเครื่องกลางและปลายทาง';
  int _routeGeneration = 0;
  String _connectedSignature = '';
  String? _relayTestResult;
  bool _sendingRelayTest = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _dependencies = RelioDependencyScope.of(context);
    _connectedSignature = _currentConnectedSignature();
    _dependencies.nearbyService.addListener(_onNearbyChanged);
    _refresh();
  }

  @override
  void dispose() {
    _dependencies.nearbyService.removeListener(_onNearbyChanged);
    super.dispose();
  }

  void _onNearbyChanged() {
    if (!mounted) return;
    final current = _currentConnectedSignature();
    if (current == _connectedSignature) return;
    _connectedSignature = current;
    setState(() {
      _routeGeneration++;
      _readyRoute = null;
      _routeStatus = 'เส้นทางเปลี่ยน กรุณาตรวจสอบอีกครั้ง';
    });
  }

  String _currentConnectedSignature() {
    final peers =
        _dependencies.nearbyService.connectedPeers
            .map((peer) => '${peer.endpointId}:${peer.deviceId}')
            .toList()
          ..sort();
    return peers.join('|');
  }

  Future<List<_RelayRecipient>> _loadRecipients() async {
    final conversations = await _dependencies.repositories.conversations
        .listConversations();
    final recipients = <_RelayRecipient>[];
    for (final conversation in conversations) {
      final principal = await _dependencies.repositories.conversations
          .remotePrincipalForConversation(conversation.id);
      final known = await _dependencies.repositories.nearbyDevices.getDevice(
        conversation.participantId,
      );
      if (RelioPacket.validPrincipal(principal) && known?.isTrusted == true) {
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
      _routeGeneration++;
      _readyRoute = null;
    });
  }

  String _routeKey(_RelayRecipient recipient, String middleId) =>
      '$middleId:${recipient.conversation.participantId}';

  Future<void> _checkRoute(_RelayRecipient recipient) async {
    final middleId = _selectedMiddleId;
    if (middleId == null) return;
    final generation = ++_routeGeneration;
    setState(() {
      _readyRoute = null;
      _routeStatus = 'กำลังถามเครื่องกลางว่าเชื่อมปลายทางอยู่หรือไม่…';
    });
    final ready = await _dependencies.nearbyService.checkQaRelayRoute(
      middleDeviceId: middleId,
      destinationDeviceId: recipient.conversation.participantId,
    );
    if (!mounted || generation != _routeGeneration) return;
    setState(() {
      _readyRoute = ready ? _routeKey(recipient, middleId) : null;
      _routeStatus = ready
          ? 'พร้อมทดสอบ: เครื่องกลางยืนยันว่าต่อปลายทางอยู่'
          : 'เส้นทางยังไม่พร้อม: เครื่องกลางไม่ยืนยันการเชื่อมต่อ';
    });
  }

  String? _routeBlock(_RelayRecipient? recipient) {
    if (recipient == null) return 'เลือกผู้รับที่มี principal mapping ก่อน';
    final matches = _dependencies.nearbyService.connectedPeers
        .where((peer) => peer.deviceId == _selectedMiddleId)
        .toList();
    if (_dependencies.nearbyService.connectedPeers.length != 1) {
      return 'ต้นทางต้องเชื่อมต่อเครื่องกลางเพียงเครื่องเดียว เพื่อกำหนด next hop แน่นอน';
    }
    if (matches.length != 1) return 'เลือกเครื่องกลางที่เชื่อมต่ออยู่';
    final peer = matches.single;
    if (peer.deviceId == recipient.conversation.participantId) {
      return 'ผู้รับเชื่อมต่อโดยตรงอยู่ จึงไม่ส่ง relay test';
    }
    if (peer.deviceId == null || !peer.capabilities.contains('relay-v1')) {
      return 'next-hop ไม่มี verified device identity หรือ relay-v1';
    }
    if (_dependencies.nearbyService.isDeviceConnected(
      recipient.conversation.participantId,
    )) {
      return 'ปลายทางเชื่อมต่อโดยตรงอยู่';
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
      _readyRoute = null;
    });
    try {
      final middleId = _selectedMiddleId;
      if (middleId == null ||
          !await _dependencies.nearbyService.checkQaRelayRoute(
            middleDeviceId: middleId,
            destinationDeviceId: recipient.conversation.participantId,
          ) ||
          _routeBlock(recipient) != null) {
        throw StateError('เครื่องกลางไม่ยืนยันเส้นทางล่าสุด');
      }
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
            'บันทึก probe แล้ว: ${result.name} / '
            '${record?.state.name ?? 'ไม่พบข้อมูล'} • '
            'รหัส ${envelope.packetId.substring(0, 8)}';
        _packetCount = _dependencies.relayRepository.packetCount();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _relayTestResult = 'ส่งไม่ได้: $error');
    } finally {
      if (mounted) setState(() => _sendingRelayTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(
        title: 'ทดสอบ Relay',
        subtitle: 'QA • relay-v1',
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
          _buildRelayLog(),
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
              'ทดสอบส่งผ่านเครื่องกลาง',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('ส่งข้อความทดสอบผ่าน Nearby จริง โดยไม่ส่ง SOS'),
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
                final middlePeers = _dependencies.nearbyService.connectedPeers
                    .where(
                      (peer) =>
                          peer.deviceId != null &&
                          peer.capabilities.contains('relay-v1'),
                    )
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FutureBuilder<String>(
                      future: _dependencies.identity.getDisplayName(),
                      builder: (context, snapshot) => Text(
                        'เครื่องต้นทาง: ${snapshot.data ?? 'กำลังโหลด…'}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('middle-$_selectedMiddleId'),
                      initialValue:
                          middlePeers.any(
                            (peer) => peer.deviceId == _selectedMiddleId,
                          )
                          ? _selectedMiddleId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'เครื่องกลาง',
                      ),
                      items: middlePeers
                          .map(
                            (peer) => DropdownMenuItem(
                              value: peer.deviceId!,
                              child: Text(
                                '${peer.name} • ${peer.deviceId!.substring(0, peer.deviceId!.length.clamp(0, 8))}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _sendingRelayTest
                          ? null
                          : (id) => setState(() {
                              _selectedMiddleId = id;
                              _readyRoute = null;
                              _routeGeneration++;
                            }),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedConversationId),
                      initialValue: selected?.conversation.id,
                      decoration: const InputDecoration(labelText: 'ปลายทาง'),
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
                          : (id) => setState(() {
                              _selectedConversationId = id;
                              _readyRoute = null;
                              _routeGeneration++;
                            }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.connectionState == ConnectionState.waiting
                          ? 'กำลังตรวจสอบ principal mapping…'
                          : block ?? _routeStatus,
                    ),
                    if (selected != null && block == null)
                      OutlinedButton(
                        onPressed: _sendingRelayTest
                            ? null
                            : () => _checkRoute(selected),
                        child: const Text('ตรวจสอบเส้นทางสด'),
                      ),
                    if (_relayTestResult != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(_relayTestResult!),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed:
                          selected == null ||
                              block != null ||
                              _sendingRelayTest ||
                              _selectedMiddleId == null ||
                              _readyRoute !=
                                  _routeKey(selected, _selectedMiddleId!)
                          ? null
                          : () => _sendSyntheticRelay(selected),
                      icon: const Icon(Icons.route_outlined),
                      label: Text(
                        _sendingRelayTest ? 'กำลังส่ง…' : 'ส่งข้อมูลทดสอบ',
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

  Widget _buildRelayLog() {
    if (!RelioBuildInfo.isTest) return const SizedBox.shrink();
    return ValueListenableBuilder<List<Map<String, Object?>>>(
      valueListenable: _dependencies.diagnostics.qaRelayEvents,
      builder: (context, entries, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'เหตุการณ์ Relay จริงในเครื่องนี้',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty) const Text('ยังไม่มีเหตุการณ์ Relay'),
              for (final entry in entries.take(30))
                ListTile(
                  dense: true,
                  title: Text(_relayEventThai(entry)),
                  subtitle: Text(
                    '${entry['timestamp']} • '
                    'ซอง ${entry['relayPacketAlias'] ?? '-'} • '
                    'ต้นทาง ${entry['originAlias'] ?? '-'} • '
                    'ปลายทาง ${entry['destinationAlias'] ?? '-'}',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _relayEventThai(Map<String, Object?> entry) =>
      switch (entry['event'] as String?) {
        'packet_enqueued' => 'บันทึกข้อมูลทดสอบแล้ว',
        'envelope_stored' => 'เครื่องนี้รับและบันทึกซองแล้ว',
        'forward_sent' => 'เครื่องนี้ส่งต่อแล้ว',
        'payload_delivered' => 'เครื่องนี้บันทึกถึงปลายทางแล้ว',
        'ack_received' =>
          entry['ackStatus'] == 'stored'
              ? 'เพื่อนบ้านยืนยันว่ารับฝากซองแล้ว'
              : entry['ackStatus'] == 'delivered'
              ? 'ปลายทางยืนยันการรับกับเครื่องนี้แล้ว'
              : 'เครื่องนี้ได้รับ ACK จากเพื่อนบ้าน',
        'ack_sent' =>
          entry['ackStatus'] == 'stored'
              ? 'เครื่องนี้ยืนยันการรับฝากกับต้นทางแล้ว'
              : entry['ackStatus'] == 'delivered'
              ? 'เครื่องนี้ยืนยันการรับกับเครื่องกลางแล้ว'
              : 'เครื่องนี้ส่ง ACK ไปยังเพื่อนบ้าน',
        'duplicate_suppressed' => 'พบซองซ้ำและระงับแล้ว',
        'forward_failed' => 'ส่งต่อไม่สำเร็จ',
        _ => 'Relay: ${entry['event'] ?? 'ไม่ทราบเหตุการณ์'}',
      };
}

class _RelayRecipient {
  const _RelayRecipient({
    required this.conversation,
    required this.principalId,
  });

  final RelioConversation conversation;
  final String principalId;
}
