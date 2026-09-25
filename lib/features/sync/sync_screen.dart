import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

enum SyncState { offline, syncing, synced, failed }

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncState state = SyncState.offline;

  Future<void> _sync() async {
    final cloudState = RelioDependencyScope.of(
      context,
    ).cloudDataSource.cloudState;
    final message = switch (cloudState) {
      CloudState.notConfigured =>
        'ยังไม่ได้ตั้งค่า Cloud — คิวจะคงอยู่ในเครื่อง',
      CloudState.signedOut => 'กรุณาเข้าสู่ระบบก่อนเตรียมซิงก์ข้อมูล',
      CloudState.ready =>
        'Cloud พร้อมใช้งาน แต่ v0.5 ยังไม่มีตัวประมวลผลคิวอัตโนมัติ',
      CloudState.offline => 'ออฟไลน์ — ข้อมูลยังคงอยู่ในคิวภายในเครื่อง',
      CloudState.error =>
        'Cloud มีข้อผิดพลาด — ข้อมูลยังคงอยู่ในคิวภายในเครื่อง',
    };
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSyncing = state == SyncState.syncing;
    return Scaffold(
      appBar: RelioAppBar(title: 'สถานะการซิงก์', onBack: () => context.pop()),
      body: StreamBuilder<int>(
        stream: RelioDependencyScope.of(
          context,
        ).repositories.syncQueue.watchPendingCount(),
        builder: (context, queueSnapshot) {
          final pendingCount = queueSnapshot.data ?? 0;
          final statusText = switch (state) {
            SyncState.offline => 'ข้อมูลรอซิงก์ $pendingCount รายการ',
            SyncState.syncing => 'กำลังซิงก์ข้อมูล...',
            SyncState.synced => 'ซิงก์ข้อมูลแล้ว',
            SyncState.failed => 'ซิงก์ไม่สำเร็จ',
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              RelioSpacing.lg,
              16,
              RelioSpacing.lg,
              24,
            ),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color:
                              (state == SyncState.synced
                                      ? RelioColors.success
                                      : RelioColors.warning)
                                  .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          isSyncing
                              ? Icons.sync_rounded
                              : state == SyncState.synced
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                          color: state == SyncState.synced
                              ? RelioColors.success
                              : RelioColors.warning,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statusText,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              state == SyncState.synced
                                  ? 'อัปเดตล่าสุด 10:24'
                                  : 'จะซิงก์เมื่อมีอินเทอร์เน็ต',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'คิวออฟไลน์',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const RelioSettingTile(
                icon: Icons.chat_bubble_outline,
                title: 'ข้อความ: สมชาย ใจดี',
                subtitle: 'รอซิงก์ • 10:22',
                trailing: Icon(
                  Icons.schedule_rounded,
                  color: RelioColors.warning,
                ),
              ),
              const SizedBox(height: 8),
              const RelioSettingTile(
                icon: Icons.image_outlined,
                title: 'รูปภาพ: 20240924_102318.jpg',
                subtitle: 'รอซิงก์ • 10:23',
                trailing: Icon(
                  Icons.schedule_rounded,
                  color: RelioColors.warning,
                ),
              ),
              const SizedBox(height: 8),
              const RelioSettingTile(
                icon: Icons.chat_bubble_outline,
                title: 'ข้อความ: มิ้นท์',
                subtitle: 'ซิงก์แล้ว • 10:18',
                trailing: Icon(
                  Icons.check_circle_outline,
                  color: RelioColors.success,
                ),
              ),
              const SizedBox(height: 18),
              const RelioLocationCard(title: 'พื้นที่จัดเก็บ'),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isSyncing ? null : _sync,
                  icon: Icon(
                    isSyncing ? Icons.sync_rounded : Icons.refresh_rounded,
                  ),
                  label: Text(
                    isSyncing ? 'กำลังตรวจสอบ...' : 'ตรวจสอบสถานะ Cloud',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
