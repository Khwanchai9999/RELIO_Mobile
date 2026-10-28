import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/environment.dart';
import '../../core/diagnostics/diagnostics_log_service.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/nearby/relio_packet.dart';
import '../../core/relio_dependencies.dart';
import '../../core/relay/relay_route_planner.dart';
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
  RelayTextRouteMode _routeMode = RelayTextRouteMode.automatic;
  RelayRoutePlan? _checkedPlan;
  String? _readyRoute;
  String _routeStatus = 'เลือกเครื่องกลางและปลายทาง';
  int _routeGeneration = 0;
  String _connectedSignature = '';
  String? _relayTestResult;
  bool _sendingRelayTest = false;
  bool _loaded = false;
  bool _changingQaPause = false;
  final Map<String, String> _peerLabels = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _dependencies = RelioDependencyScope.of(context);
    _routeMode = _dependencies.nearbyService.textRouteMode;
    _selectedMiddleId = _dependencies.nearbyService.forcedRelayMiddleDeviceId;
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
      _checkedPlan = null;
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
    _peerLabels[DiagnosticsLogService.peerAlias(
          await _dependencies.identity.getDeviceId(),
        )] =
        'เครื่องนี้';
    final conversations = await _dependencies.repositories.conversations
        .listConversations();
    final recipients = <_RelayRecipient>[];
    for (final conversation in conversations) {
      _peerLabels[DiagnosticsLogService.peerAlias(conversation.participantId)] =
          conversation.displayName;
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

  String _routeKey(_RelayRecipient recipient, String? middleId) =>
      '${_routeMode.name}:${middleId ?? '-'}:'
      '${recipient.conversation.participantId}';

  Future<void> _checkRoute(_RelayRecipient recipient) async {
    final middleId = _routeMode == RelayTextRouteMode.qaForcedRelay
        ? _selectedMiddleId
        : null;
    if (_routeMode == RelayTextRouteMode.qaForcedRelay && middleId == null) {
      return;
    }
    final generation = ++_routeGeneration;
    setState(() {
      _readyRoute = null;
      _checkedPlan = null;
      _routeStatus = 'กำลังตรวจสอบเส้นทางสด…';
    });
    await _dependencies.nearbyService.configureTextRouteMode(
      _routeMode,
      forcedMiddleDeviceId: middleId,
    );
    final plan = await _dependencies.nearbyService.planTextRoute(
      recipient.conversation.participantId,
    );
    if (!mounted || generation != _routeGeneration) return;
    setState(() {
      _checkedPlan = plan;
      _readyRoute = plan.ready ? _routeKey(recipient, middleId) : null;
      _routeStatus = switch (plan.kind) {
        RelayRouteKind.direct => 'พร้อม: ระบบจะส่งตรงไปยังปลายทาง',
        RelayRouteKind.relay => 'พร้อม: เครื่องกลางยืนยันว่าเชื่อมปลายทางอยู่',
        RelayRouteKind.unavailable =>
          'ยังไม่พบเส้นทาง Direct หรือ Relay ที่พร้อม',
      };
    });
  }

  String? _routeBlock(_RelayRecipient? recipient) {
    if (recipient == null) return 'เลือกผู้รับที่มี principal mapping ก่อน';
    if (_routeMode != RelayTextRouteMode.qaForcedRelay) return null;
    final matches = _dependencies.nearbyService.connectedPeers
        .where((peer) => peer.deviceId == _selectedMiddleId)
        .toList();
    if (matches.length != 1) return 'เลือกเครื่องกลางที่เชื่อมต่ออยู่';
    final peer = matches.single;
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
      _readyRoute = null;
    });
    try {
      await _dependencies.nearbyService.configureTextRouteMode(
        _routeMode,
        forcedMiddleDeviceId: _routeMode == RelayTextRouteMode.qaForcedRelay
            ? _selectedMiddleId
            : null,
      );
      final latestPlan = await _dependencies.nearbyService.planTextRoute(
        recipient.conversation.participantId,
      );
      if (!latestPlan.ready || _routeBlock(recipient) != null) {
        throw StateError('เส้นทางล่าสุดยังไม่พร้อม');
      }
      final identity = _dependencies.identity;
      final senderDeviceId = await identity.getDeviceId();
      final message = await _dependencies.repositories.ownerContext.run(
        () async {
          final saved = await _dependencies.repositories.messages
              .createOutgoingText(
                conversationId: recipient.conversation.id,
                senderId:
                    _dependencies.authService.identity?.userId ??
                    senderDeviceId,
                senderDeviceId: senderDeviceId,
                text: 'RELIO QA ROUTE TEST',
              );
          await _dependencies.nearbyService.sendMessage(saved);
          return saved;
        },
      );
      if (!mounted) return;
      setState(() {
        _relayTestResult =
            'เริ่ม Probe ${DiagnosticsLogService.peerAlias(message.id)} แล้ว '
            'ติดตามผล ACK ใน Chat และเหตุการณ์ด้านล่าง';
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
          if (RelioBuildInfo.isTest)
            Card(
              child: SwitchListTile(
                title: const Text('พักส่งต่อ Text ที่รับฝาก (QA)'),
                subtitle: Text(
                  _dependencies.qaTextForwardingPaused
                      ? 'กำลังรับฝากแต่พักส่งต่อ Text • คงค่านี้หลังเปิดแอปใหม่ • ไม่พัก SOS'
                      : 'ปิดอยู่ • ใช้ควบคุมการทดสอบรับฝากแล้วลิงก์หลุดเท่านั้น',
                ),
                value: _dependencies.qaTextForwardingPaused,
                onChanged: _changingQaPause
                    ? null
                    : (paused) async {
                        setState(() => _changingQaPause = true);
                        try {
                          await _dependencies.setQaTextForwardingPaused(paused);
                        } finally {
                          if (mounted) setState(() => _changingQaPause = false);
                        }
                      },
              ),
            ),
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
              'โหมดการส่งข้อความ Text (QA)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('ส่งข้อความทดสอบผ่าน Nearby จริง โดยไม่ส่ง SOS'),
            const Text(
              'ค่าที่เลือกใช้กับข้อความ Text ใน QA Chat ด้วย • รูป วิดีโอ และ SOS ใช้เส้นทางเดิม',
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
                final middlePeers = _dependencies.nearbyService.connectedPeers
                    .where(
                      (peer) =>
                          peer.deviceId != null &&
                          peer.deviceId !=
                              selected?.conversation.participantId &&
                          peer.capabilities.contains('relay-v1'),
                    )
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'อุปกรณ์ที่เชื่อมต่อ: ${_dependencies.nearbyService.connectedPeerCount} เครื่อง (ไม่นับเครื่องนี้)',
                    ),
                    FutureBuilder<String>(
                      future: _dependencies.identity.getDisplayName(),
                      builder: (context, snapshot) => Text(
                        'ต้นทาง: เครื่องนี้ • ${snapshot.data ?? 'กำลังโหลด…'}',
                      ),
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
                              child: Text(
                                '${item.conversation.displayName} • '
                                '${item.conversation.participantId.substring(0, item.conversation.participantId.length.clamp(0, 8))}',
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _sendingRelayTest
                          ? null
                          : (id) => setState(() {
                              _selectedConversationId = id;
                              _readyRoute = null;
                              _checkedPlan = null;
                              _routeGeneration++;
                            }),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'โหมดการส่ง',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    RadioGroup<RelayTextRouteMode>(
                      groupValue: _routeMode,
                      onChanged: _sendingRelayTest
                          ? (_) {}
                          : (mode) async {
                              if (mode == null) return;
                              setState(() {
                                _routeMode = mode;
                                _readyRoute = null;
                                _checkedPlan = null;
                                _routeStatus = 'กรุณาตรวจสอบเส้นทางสด';
                                _routeGeneration++;
                              });
                              if (mode != RelayTextRouteMode.qaForcedRelay) {
                                await _dependencies.nearbyService
                                    .configureTextRouteMode(mode);
                              }
                            },
                      child: const Column(
                        children: [
                          _RouteModeOption(
                            mode: RelayTextRouteMode.automatic,
                            title: 'เส้นทางอัตโนมัติ — แนะนำ',
                            subtitle:
                                'ส่งตรงก่อน หากส่งตรงไม่ได้จะใช้เครื่องกลางที่พร้อม\n'
                                'รองรับขณะเปิดแอปและ Nearby ทำงานอยู่',
                          ),
                          _RouteModeOption(
                            mode: RelayTextRouteMode.directOnly,
                            title: 'ส่งตรงเท่านั้น',
                            subtitle: 'ไม่ส่งข้อมูลผ่านเครื่องกลาง',
                          ),
                          _RouteModeOption(
                            mode: RelayTextRouteMode.qaForcedRelay,
                            title: 'QA: บังคับผ่านเครื่องกลาง',
                            subtitle:
                                'เลือกเครื่องกลางเองเพื่อทดสอบ แม้มีลิงก์ตรง',
                          ),
                        ],
                      ),
                    ),
                    if (_routeMode == RelayTextRouteMode.qaForcedRelay) ...[
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
                                  '${peer.name} • '
                                  '${peer.deviceId!.substring(0, peer.deviceId!.length.clamp(0, 8))}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _sendingRelayTest
                            ? null
                            : (id) async {
                                setState(() {
                                  _selectedMiddleId = id;
                                  _readyRoute = null;
                                  _checkedPlan = null;
                                  _routeGeneration++;
                                });
                                if (id != null) {
                                  await _dependencies.nearbyService
                                      .configureTextRouteMode(
                                        RelayTextRouteMode.qaForcedRelay,
                                        forcedMiddleDeviceId: id,
                                      );
                                }
                              },
                      ),
                    ],
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
                    if (selected != null &&
                        _routeMode == RelayTextRouteMode.qaForcedRelay &&
                        _selectedMiddleId != null &&
                        _dependencies.nearbyService.isDeviceConnected(
                          selected.conversation.participantId,
                        ))
                      const Text(
                        'มีลิงก์ตรง A–C แต่ probe นี้จะส่งผ่านเครื่องกลางที่เลือกเท่านั้น',
                      ),
                    if (_checkedPlan?.kind == RelayRouteKind.direct)
                      const Text(
                        'เส้นทางตรงพร้อม โหมดนี้มีผลกับข้อความ Text ที่ส่งจาก Chat',
                      ),
                    if (_relayTestResult != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(_relayTestResult!),
                    ],
                    const SizedBox(height: 8),
                    if (_checkedPlan?.ready == true)
                      FilledButton.icon(
                        onPressed:
                            selected == null ||
                                block != null ||
                                _sendingRelayTest ||
                                _readyRoute !=
                                    _routeKey(
                                      selected,
                                      _routeMode ==
                                              RelayTextRouteMode.qaForcedRelay
                                          ? _selectedMiddleId
                                          : null,
                                    )
                            ? null
                            : () => _sendSyntheticRelay(selected),
                        icon: const Icon(Icons.route_outlined),
                        label: Text(
                          _sendingRelayTest
                              ? 'กำลังส่ง…'
                              : 'เริ่ม QA Relay Probe',
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
      builder: (context, entries, _) {
        final groups = <String, List<Map<String, Object?>>>{};
        for (final entry in entries.reversed) {
          final key = entry['payloadAlias'] as String?;
          if (key == null) continue;
          groups.putIfAbsent(key, () => []).add(entry);
        }
        return Card(
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
                const Text(
                  'แต่ละกลุ่มเป็นข้อมูลหนึ่งรายการ • อ่านจากเก่าไปใหม่ • แสดงเฉพาะเหตุการณ์ในเครื่องนี้',
                ),
                if (groups.isEmpty) const Text('ยังไม่มีเหตุการณ์ส่งข้อมูล'),
                for (final group in groups.entries.toList().reversed)
                  ExpansionTile(
                    initiallyExpanded: group.key == groups.keys.last,
                    title: Text('ข้อมูล #${group.key}'),
                    subtitle: Text(_relayEventThai(group.value.last)),
                    children: [
                      for (final entry in group.value)
                        ListTile(
                          dense: true,
                          title: Text(_relayEventThai(entry)),
                          subtitle: Text(
                            '${entry['timestamp']} • '
                            'ซอง ${entry['relayPacketAlias'] ?? '-'} • '
                            'ข้อมูล ${entry['payloadAlias'] ?? '-'} • '
                            'ต้นทาง ${_peerLabel(entry['originAlias'])} • '
                            'ปลายทาง ${_peerLabel(entry['destinationAlias'])}'
                            '${entry['middleAlias'] == null ? '' : ' • กลาง ${_peerLabel(entry['middleAlias'])}'}'
                            '${entry['targetAlias'] == null ? '' : ' • ไป ${_peerLabel(entry['targetAlias'])}'}'
                            '${entry['hopCount'] == null ? '' : ' • hop ${entry['hopCount']}/${entry['maxHops']}'}',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _peerLabel(Object? alias) =>
      _peerLabels[alias] ?? alias?.toString() ?? '-';

  String _relayEventThai(Map<String, Object?> entry) =>
      switch (entry['event'] as String?) {
        'packet_enqueued' => 'บันทึกข้อมูลทดสอบแล้ว',
        'route_selected' => switch (entry['routeKind']) {
          'direct' => 'เลือกเส้นทางตรง',
          'relay' => 'เลือกเส้นทางผ่านเครื่องกลาง',
          _ => 'ยังไม่พบเส้นทางที่พร้อม',
        },
        'text_route_started' => 'เริ่มส่งข้อความผ่าน Relay',
        'text_direct_sent' => 'ส่งตรงออกแล้ว — รอ ACK จากปลายทาง',
        'direct_ack_received' => 'ปลายทางยืนยันรับและบันทึกข้อความตรงแล้ว',
        'envelope_stored' =>
          entry['nodeRole'] == 'destination'
              ? 'ปลายทางรับซองแล้ว — กำลังตรวจสอบ'
              : 'รับฝากแล้ว — บันทึกในเครื่อง รอส่งต่อ',
        'forward_attempt' => 'กำลังส่งซองไปยัง hop ถัดไป',
        'forward_sent' => 'ส่งต่อแล้ว — รอผลยืนยันจากเครื่องถัดไป',
        'payload_delivered' => 'ปลายทางรับและบันทึกข้อมูลแล้ว',
        'final_ack_propagated' => 'ส่งผลปลายทางย้อนกลับไปยังต้นทางแล้ว',
        'unexpected_ack_blocked' => 'ปฏิเสธ ACK ที่ไม่ตรงกับเส้นทาง',
        'ack_received' =>
          entry['ackStatus'] == 'stored'
              ? 'รับฝากแล้ว — ยังไม่ยืนยันว่าถึงปลายทาง'
              : entry['ackStatus'] == 'delivered'
              ? 'ถึงปลายทางแล้ว — ได้รับ ACK ยืนยัน'
              : 'เครื่องนี้ได้รับ ACK จากเพื่อนบ้าน',
        'ack_sent' =>
          entry['ackStatus'] == 'stored'
              ? 'เครื่องนี้ยืนยันการรับฝากกับต้นทางแล้ว'
              : entry['ackStatus'] == 'delivered'
              ? 'ส่ง ACK ยืนยันถึงปลายทางกลับเครื่องก่อนหน้าแล้ว'
              : 'เครื่องนี้ส่ง ACK ไปยังเพื่อนบ้าน',
        'duplicate_suppressed' => 'พบซองซ้ำและระงับแล้ว',
        'forward_failed' => 'ส่งต่อไม่สำเร็จ',
        'ack_failed' => 'ส่ง ACK ไม่สำเร็จ',
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

class _RouteModeOption extends StatelessWidget {
  const _RouteModeOption({
    required this.mode,
    required this.title,
    required this.subtitle,
  });

  final RelayTextRouteMode mode;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => RadioListTile<RelayTextRouteMode>(
    value: mode,
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
  );
}
