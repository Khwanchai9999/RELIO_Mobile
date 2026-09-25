import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_spacing.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

class NearbyDiagnosticsScreen extends StatefulWidget {
  const NearbyDiagnosticsScreen({super.key});

  @override
  State<NearbyDiagnosticsScreen> createState() =>
      _NearbyDiagnosticsScreenState();
}

class _NearbyDiagnosticsScreenState extends State<NearbyDiagnosticsScreen> {
  late final RelioDependencies _dependencies;
  late Future<String> _deviceId;
  late Future<NearbyPermissionSnapshot> _permissions;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _dependencies = RelioDependencyScope.of(context);
    _deviceId = _dependencies.identity.getDeviceId();
    _permissions = _dependencies.permissionService.readNearbyPermissions();
  }

  void _refreshPermissions() {
    setState(() {
      _permissions = _dependencies.permissionService.readNearbyPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nearby = _dependencies.nearbyService;
    final transport = _dependencies.transport;
    return Scaffold(
      appBar: RelioAppBar(
        title: 'Nearby Diagnostics',
        subtitle: 'Developer / technical spike',
        onBack: () => context.pop(),
      ),
      body: AnimatedBuilder(
        animation: nearby,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(
            RelioSpacing.lg,
            16,
            RelioSpacing.lg,
            28,
          ),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: Icon(Icons.developer_mode_outlined),
                title: Text('Development-only screen'),
                subtitle: Text(
                  'Mock transport ไม่ใช่การค้นหาอุปกรณ์จริง และยังไม่มีการยืนยันด้วยโทรศัพท์สองเครื่อง',
                ),
                trailing: transport is MockNearbyTransport
                    ? const Chip(label: Text('MOCK TRANSPORT'))
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            FutureBuilder<String>(
              future: _deviceId,
              builder: (context, snapshot) => RelioSettingTile(
                icon: Icons.fingerprint_rounded,
                title: 'Local device ID',
                subtitle: snapshot.data ?? 'กำลังโหลด...',
              ),
            ),
            const SizedBox(height: 8),
            RelioSettingTile(
              icon: Icons.settings_ethernet_rounded,
              title: 'Transport implementation',
              subtitle: transport.implementationName,
            ),
            const SizedBox(height: 8),
            FutureBuilder<NearbyPermissionSnapshot>(
              future: _permissions,
              builder: (context, snapshot) => RelioSettingTile(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Permission state',
                subtitle: snapshot.hasData
                    ? (snapshot.data!.allGranted ? 'Granted' : 'Needs review')
                    : 'กำลังตรวจสอบ...',
                onTap: () async {
                  await _dependencies.permissionService
                      .requestNearbyPermissions();
                  _refreshPermissions();
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Transport controls',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: nearby.startAdvertising,
                  icon: const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('Start Advertising'),
                ),
                OutlinedButton.icon(
                  onPressed: nearby.stopAdvertising,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Advertising'),
                ),
                FilledButton.icon(
                  onPressed: nearby.startDiscovery,
                  icon: const Icon(Icons.radar_outlined),
                  label: const Text('Start Discovery'),
                ),
                OutlinedButton.icon(
                  onPressed: nearby.stopDiscovery,
                  icon: const Icon(Icons.radar_outlined),
                  label: const Text('Stop Discovery'),
                ),
                FilledButton.tonalIcon(
                  onPressed: nearby.sendHello,
                  icon: const Icon(Icons.waving_hand_outlined),
                  label: const Text('Send Hello RELIO'),
                ),
                FilledButton.tonalIcon(
                  onPressed: nearby.sendTestText,
                  icon: const Icon(Icons.textsms_outlined),
                  label: const Text('Send test text'),
                ),
                FilledButton.tonalIcon(
                  onPressed: nearby.sendTestSos,
                  icon: const Icon(Icons.warning_amber_outlined),
                  label: const Text('Send test SOS'),
                ),
                FilledButton.tonalIcon(
                  onPressed: nearby.sendTestRescue,
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Send test Rescue'),
                ),
                OutlinedButton.icon(
                  onPressed: nearby.clearLog,
                  icon: const Icon(Icons.clear_all_outlined),
                  label: const Text('Clear log'),
                ),
              ],
            ),
            if (transport is MockNearbyTransport) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => transport.simulatePeer(
                  id: 'mock-peer-01',
                  name: 'Mock Peer 01',
                ),
                icon: const Icon(Icons.devices_other_outlined),
                label: const Text('Simulate peer discovered'),
              ),
            ],
            const SizedBox(height: 18),
            Text('State', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('State: ${nearby.applicationState.name}')),
                const Chip(label: Text('Protocol v1')),
                Chip(
                  label: Text(
                    nearby.isAdvertising ? 'Advertising ON' : 'Advertising OFF',
                  ),
                ),
                Chip(
                  label: Text(
                    nearby.isDiscovering ? 'Discovery ON' : 'Discovery OFF',
                  ),
                ),
                Chip(label: Text('${nearby.discoveredPeers.length} peers')),
                Chip(label: Text('ACK ${nearby.acknowledgementCount}')),
                Chip(
                  label: Text('Protocol errors ${nearby.protocolErrorCount}'),
                ),
                Chip(
                  label: Text('Transport errors ${nearby.transportErrorCount}'),
                ),
              ],
            ),
            if (nearby.discoveredPeers.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...nearby.discoveredPeers.map(
                (peer) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_search_outlined),
                    title: Text(peer.name),
                    subtitle: Text(
                      'endpoint: ${peer.endpointId}\n'
                      'device: ${nearby.deviceIdForEndpoint(peer.endpointId) ?? 'รอ handshake'}\n'
                      'state: ${nearby.peerStates[peer.endpointId]?.name ?? 'discovered'}',
                    ),
                    trailing: Wrap(
                      children: [
                        FilledButton(
                          onPressed: () => nearby.connect(peer.id),
                          child: const Text('Connect'),
                        ),
                        IconButton(
                          onPressed: () => nearby.disconnect(peer.id),
                          icon: const Icon(Icons.link_off_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Media transfers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FutureBuilder(
              future: _dependencies.repositories.attachments.listAll(),
              builder: (context, snapshot) {
                final attachments = snapshot.data;
                if (attachments == null || attachments.isEmpty) {
                  return const RelioSettingTile(
                    icon: Icons.perm_media_outlined,
                    title: 'No media transfers',
                    subtitle: 'ยังไม่มี attachment ในฐานข้อมูลท้องถิ่น',
                  );
                }
                return Column(
                  children: attachments
                      .map(
                        (attachment) => Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.insert_drive_file_outlined,
                            ),
                            title: Text(attachment.fileName),
                            subtitle: Text(
                              'transfer: ${attachment.transferId}\n'
                              '${attachment.transferStatus.name} • '
                              '${attachment.bytesTransferred}/${attachment.byteSize} bytes',
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
            const SizedBox(height: 8),
            RelioSettingTile(
              icon: Icons.location_searching_outlined,
              title: 'Location service',
              subtitle: _dependencies.locationService.runtimeType.toString(),
            ),
            const SizedBox(height: 18),
            Text('Packets', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RelioSettingTile(
              icon: Icons.upload_outlined,
              title: 'Last sent packet',
              subtitle: nearby.lastSentPacket ?? 'ยังไม่มี packet',
            ),
            const SizedBox(height: 8),
            RelioSettingTile(
              icon: Icons.download_outlined,
              title: 'Last received packet',
              subtitle: nearby.lastReceivedPacket ?? 'ยังไม่มี packet',
            ),
            const SizedBox(height: 18),
            Text(
              'Event / error log',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (nearby.lastError != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(nearby.lastError!),
                ),
              ),
            if (nearby.eventLog.isEmpty)
              const RelioEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'ยังไม่มี event',
                subtitle: 'กดปุ่มด้านบนเพื่อเริ่ม technical spike',
              )
            else
              ...nearby.eventLog.map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    event,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
