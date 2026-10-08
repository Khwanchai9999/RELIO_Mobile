import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/relio_dependencies.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_types.dart';
import '../../shared/widgets/relio_widgets.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  Future<void> _runSync() async {
    final dependencies = RelioDependencyScope.of(context);
    await dependencies.syncEngine.run();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_resultMessage(dependencies.syncEngine.snapshot))),
    );
  }

  Future<void> _adoptGuestData() async {
    final dependencies = RelioDependencyScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('นำข้อมูลออฟไลน์ไปซิงก์หรือไม่'),
        content: const Text(
          'บทสนทนาและคิวข้อมูลที่สร้างใน Guest Mode จะยังอยู่ในเครื่องและไม่ถูกผูกกับบัญชีโดยอัตโนมัติ\n\n'
          'ยืนยันเพื่อย้ายข้อมูล Guest ที่ยังไม่มีเจ้าของไปยังบัญชีที่เข้าสู่ระบบอยู่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ย้ายและซิงก์'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await dependencies.syncEngine.adoptGuestItemsAndRun();
  }

  Future<void> _retryFailed() async {
    final dependencies = RelioDependencyScope.of(context);
    final failed = await dependencies.repositories.syncQueue.listAll();
    for (final item in failed.where(
      (item) => item.status == SyncQueueStatus.failed.value,
    )) {
      await dependencies.syncEngine.retryFailed(item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = RelioDependencyScope.of(context);
    return Scaffold(
      appBar: RelioAppBar(title: 'สถานะการซิงก์', onBack: () => context.pop()),
      body: StreamBuilder<SyncEngineSnapshot>(
        stream: dependencies.syncEngine.watchState(),
        initialData: dependencies.syncEngine.snapshot,
        builder: (context, engineSnapshot) {
          final engine =
              engineSnapshot.data ?? dependencies.syncEngine.snapshot;
          return StreamBuilder<SyncQueueSummary>(
            stream: dependencies.repositories.syncQueue.watchSummary(),
            initialData: engine.queueSummary,
            builder: (context, queueSnapshot) {
              final summary = queueSnapshot.data ?? engine.queueSummary;
              final isRunning = engine.state == SyncEngineState.running;
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  RelioSpacing.lg,
                  16,
                  RelioSpacing.lg,
                  24,
                ),
                children: [
                  _StatusCard(snapshot: engine, summary: summary),
                  const SizedBox(height: 18),
                  _QueueSummaryCard(summary: summary),
                  const SizedBox(height: 18),
                  Text(
                    'รายการในคิวออฟไลน์',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<RelioQueueItem>>(
                    future: dependencies.repositories.syncQueue.listAll(),
                    builder: (context, itemsSnapshot) {
                      final items =
                          itemsSnapshot.data ?? const <RelioQueueItem>[];
                      if (items.isEmpty) {
                        return const Card(
                          child: ListTile(
                            leading: Icon(Icons.check_circle_outline),
                            title: Text('ยังไม่มีรายการในคิว'),
                            subtitle: Text(
                              'ข้อมูลใหม่จะถูกบันทึกในเครื่องก่อนเสมอ',
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final item in items.take(20)) ...[
                            _QueueItemTile(item: item),
                            const SizedBox(height: 8),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  if (engine.authState == AuthState.authenticated)
                    FutureBuilder<int>(
                      future: dependencies.repositories.conversations
                          .countUnowned(),
                      builder: (context, snapshot) {
                        if (summary.pending == 0 && (snapshot.data ?? 0) == 0) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          children: [
                            OutlinedButton.icon(
                              onPressed: isRunning ? null : _adoptGuestData,
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              label: const Text(
                                'นำข้อมูลออฟไลน์นี้ไปซิงก์กับบัญชีนี้',
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
                  if (summary.failed > 0) ...[
                    OutlinedButton.icon(
                      onPressed: isRunning ? null : _retryFailed,
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('ลองรายการที่ล้มเหลวอีกครั้ง'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isRunning ? null : _runSync,
                      icon: Icon(
                        isRunning
                            ? Icons.sync_rounded
                            : Icons.cloud_sync_outlined,
                      ),
                      label: Text(isRunning ? 'กำลังซิงก์...' : 'ซิงก์ตอนนี้'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const RelioLocationCard(title: 'พื้นที่จัดเก็บ'),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _resultMessage(
    SyncEngineSnapshot snapshot,
  ) => switch (snapshot.state) {
    SyncEngineState.completed =>
      'ตรวจสอบคิวแล้ว ข้อมูลที่เป็นของบัญชีปัจจุบันจะถูกซิงก์เมื่อ Cloud พร้อม',
    SyncEngineState.waitingForCloud =>
      'ยังซิงก์ไม่ได้ — ต้องมี Cloud และบัญชีที่เข้าสู่ระบบ',
    SyncEngineState.waitingForOwnership =>
      'มีข้อมูลที่ยังยืนยันเจ้าของไม่ได้ จึงคงไว้ในเครื่อง',
    SyncEngineState.error => 'บางรายการซิงก์ไม่สำเร็จ ข้อมูลในเครื่องยังคงอยู่',
    SyncEngineState.running => 'กำลังซิงก์ข้อมูล',
    SyncEngineState.idle => 'ยังไม่ได้เริ่มซิงก์',
  };
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.snapshot, required this.summary});

  final SyncEngineSnapshot snapshot;
  final SyncQueueSummary summary;

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(snapshot.state);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(_stateIcon(snapshot.state), color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stateLabel(snapshot.state),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cloud: ${_cloudLabel(snapshot.cloudState)} • บัญชี: ${_authLabel(snapshot.authState)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (summary.pending > 0)
                    Text(
                      'ข้อมูลรอซิงก์ ${summary.pending} รายการ',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueSummaryCard extends StatelessWidget {
  const _QueueSummaryCard({required this.summary});

  final SyncQueueSummary summary;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Count(
            label: 'รอซิงก์',
            value: summary.pending,
            color: RelioColors.warning,
          ),
          _Count(
            label: 'กำลังทำ',
            value: summary.processing,
            color: RelioColors.primary,
          ),
          _Count(
            label: 'สำเร็จ',
            value: summary.completed,
            color: RelioColors.success,
          ),
          _Count(
            label: 'ผิดพลาด',
            value: summary.failed,
            color: RelioColors.sos,
          ),
        ],
      ),
    ),
  );
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
      ),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _QueueItemTile extends StatelessWidget {
  const _QueueItemTile({required this.item});

  final RelioQueueItem item;

  @override
  Widget build(BuildContext context) {
    final status = SyncQueueStatus.parse(item.status);
    final color = switch (status) {
      SyncQueueStatus.completed => RelioColors.success,
      SyncQueueStatus.failed => RelioColors.sos,
      SyncQueueStatus.processing => RelioColors.primary,
      SyncQueueStatus.pending || null => RelioColors.warning,
    };
    return Card(
      child: ListTile(
        leading: Icon(_entityIcon(item.entityType), color: color),
        title: Text(_operationLabel(item.operation)),
        subtitle: Text(
          '${_statusLabel(status)} • ${item.ownerUserId == null ? 'ยังไม่ระบุเจ้าของ' : 'ผูกกับบัญชีแล้ว'}',
        ),
        trailing: Icon(_statusIcon(status), color: color),
      ),
    );
  }
}

IconData _entityIcon(String type) => switch (SyncEntityType.parse(type)) {
  SyncEntityType.message => Icons.chat_bubble_outline,
  SyncEntityType.conversation => Icons.forum_outlined,
  SyncEntityType.sosEvent => Icons.sos_outlined,
  SyncEntityType.attachment => Icons.attach_file,
  SyncEntityType.profile => Icons.person_outline,
  null => Icons.cloud_queue_outlined,
};

String _operationLabel(String operation) =>
    switch (SyncOperation.parse(operation)) {
      SyncOperation.profileUpsert => 'โปรไฟล์',
      SyncOperation.conversationUpsert => 'บทสนทนา',
      SyncOperation.messageUpsert => 'ข้อความ',
      SyncOperation.sosUpsert => 'ข้อมูล SOS',
      SyncOperation.attachmentMetadataUpsert => 'ข้อมูลไฟล์แนบ',
      SyncOperation.attachmentUpload => 'ไฟล์แนบ',
      SyncOperation.readReceiptUpsert => 'ใบตอบรับการอ่าน',
      null => 'รายการที่ไม่รู้จัก',
    };

String _statusLabel(SyncQueueStatus? status) => switch (status) {
  SyncQueueStatus.pending => 'รอซิงก์',
  SyncQueueStatus.processing => 'กำลังซิงก์',
  SyncQueueStatus.completed => 'ซิงก์แล้ว',
  SyncQueueStatus.failed => 'ซิงก์ไม่สำเร็จ',
  null => 'รอตรวจสอบ',
};

IconData _statusIcon(SyncQueueStatus? status) => switch (status) {
  SyncQueueStatus.completed => Icons.check_circle_outline,
  SyncQueueStatus.failed => Icons.error_outline,
  SyncQueueStatus.processing => Icons.sync,
  SyncQueueStatus.pending || null => Icons.schedule_rounded,
};

Color _stateColor(SyncEngineState state) => switch (state) {
  SyncEngineState.completed => RelioColors.success,
  SyncEngineState.error => RelioColors.sos,
  SyncEngineState.running => RelioColors.primary,
  SyncEngineState.waitingForOwnership => RelioColors.warning,
  SyncEngineState.waitingForCloud ||
  SyncEngineState.idle => RelioColors.secondaryText,
};

IconData _stateIcon(SyncEngineState state) => switch (state) {
  SyncEngineState.completed => Icons.cloud_done_outlined,
  SyncEngineState.error => Icons.cloud_off_outlined,
  SyncEngineState.running => Icons.sync_rounded,
  SyncEngineState.waitingForOwnership => Icons.lock_outline,
  SyncEngineState.waitingForCloud ||
  SyncEngineState.idle => Icons.cloud_queue_outlined,
};

String _stateLabel(SyncEngineState state) => switch (state) {
  SyncEngineState.completed => 'ตรวจสอบคิวแล้ว',
  SyncEngineState.error => 'มีรายการซิงก์ไม่สำเร็จ',
  SyncEngineState.running => 'กำลังซิงก์ข้อมูล',
  SyncEngineState.waitingForOwnership => 'รอยืนยันเจ้าของข้อมูล',
  SyncEngineState.waitingForCloud => 'รอ Cloud หรือการเข้าสู่ระบบ',
  SyncEngineState.idle => 'ยังไม่ได้เริ่มซิงก์',
};

String _cloudLabel(CloudState state) => switch (state) {
  CloudState.ready => 'พร้อม',
  CloudState.offline => 'ออฟไลน์',
  CloudState.signedOut => 'ไม่ได้เข้าสู่ระบบ',
  CloudState.notConfigured => 'ยังไม่ตั้งค่า',
  CloudState.error => 'ผิดพลาด',
};

String _authLabel(AuthState state) => switch (state) {
  AuthState.authenticated => 'เข้าสู่ระบบแล้ว',
  AuthState.guest => 'Guest / ในเครื่องเท่านั้น',
  AuthState.expired => 'เซสชันหมดอายุ',
  AuthState.loading => 'กำลังตรวจสอบ',
  AuthState.error => 'ตรวจสอบไม่สำเร็จ',
};
