import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

class RelayDiagnosticsScreen extends StatefulWidget {
  const RelayDiagnosticsScreen({super.key});

  @override
  State<RelayDiagnosticsScreen> createState() => _RelayDiagnosticsScreenState();
}

class _RelayDiagnosticsScreenState extends State<RelayDiagnosticsScreen> {
  late RelioDependencies _dependencies;
  Future<int>? _packetCount;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _dependencies = RelioDependencyScope.of(context);
    _refresh();
  }

  void _refresh() {
    setState(() {
      _packetCount = _dependencies.relayRepository.packetCount();
    });
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
}
