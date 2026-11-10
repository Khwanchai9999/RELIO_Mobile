// หน้าสถานะคิว Sync และ private backup แสดงผลตามเจ้าของข้อมูลและสถานะที่ repository ส่งกลับ
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/relio_dependencies.dart';
import '../../core/repositories/local_repositories.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_types.dart';
import '../../shared/widgets/relio_widgets.dart';
import 'sync_status_counts.dart';

// หน้านี้สรุปสถานะ Cloud Sync และงานในคิวที่ยังรอหรือกำลังประมวลผล
// การส่ง Cloud เป็นคนละสถานะกับการส่ง Nearby และไม่ยืนยันการรับถึงอุปกรณ์ปลายทาง
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Sync Screen State)
class _SyncScreenState extends State<SyncScreen> {
  bool _syncingAction = false;
  bool _restoringAction = false;
  String? _cloudCountOwner;
  Future<int?>? _cloudCountFuture;
  SyncEngineState? _lastEngineState;
  CloudState? _lastCloudState;
  AuthState? _lastAuthState;

  bool get _actionInProgress => _syncingAction || _restoringAction;

  Future<void> _runSync() async {
    final dependencies = RelioDependencyScope.of(context);
    if (_actionInProgress ||
        dependencies.syncEngine.snapshot.state == SyncEngineState.running) {
      return;
    }
    setState(() => _syncingAction = true);
    try {
      await dependencies.syncEngine.run();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_resultMessage(dependencies.syncEngine.snapshot)),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncingAction = false);
    }
  }

  void _refreshCloudCount() {
    if (!mounted) return;
    final dependencies = RelioDependencyScope.of(context);
    final ownerId = dependencies.cloudDataSource.currentIdentity?.userId;
    setState(() {
      _cloudCountOwner = ownerId;
      _cloudCountFuture = _fetchConfirmedBackupCount(dependencies, ownerId);
    });
  }

  Future<int?> _fetchConfirmedBackupCount(
    RelioDependencies dependencies,
    String? ownerId,
  ) => fetchConfirmedPrivateBackupCount(dependencies.cloudDataSource, ownerId);

  Future<void> _restorePrivateBackup() async {
    final dependencies = RelioDependencyScope.of(context);
    if (_actionInProgress ||
        dependencies.syncEngine.snapshot.state == SyncEngineState.running) {
      return;
    }
    setState(() => _restoringAction = true);
    try {
      final count = await dependencies.syncEngine.restorePrivateBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('กู้คืนข้อมูลสำรองแล้ว $count รายการ')),
      );
    } on CloudException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('กู้คืนไม่ได้: ${error.message}')));
    } finally {
      if (mounted) setState(() => _restoringAction = false);
    }
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
    if (_actionInProgress) return;
    final dependencies = RelioDependencyScope.of(context);
    setState(() => _syncingAction = true);
    try {
      final ownerId = dependencies.cloudDataSource.currentIdentity?.userId;
      if (ownerId == null) return;
      final failed = await dependencies.repositories.syncQueue.listAll();
      for (final item in failed.where(
        (item) =>
            item.ownerUserId == ownerId &&
            item.status == SyncQueueStatus.failed.value,
      )) {
        await dependencies.syncEngine.retryFailed(item.id);
      }
    } finally {
      if (mounted) setState(() => _syncingAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = RelioDependencyScope.of(context);
    final ownerId = dependencies.cloudDataSource.currentIdentity?.userId;
    if (_cloudCountFuture == null || _cloudCountOwner != ownerId) {
      _cloudCountOwner = ownerId;
      _cloudCountFuture = _fetchConfirmedBackupCount(dependencies, ownerId);
    }
    return Scaffold(
      appBar: RelioAppBar(
        title: 'สถานะการซิงก์',
        onBack: () => context.canPop() ? context.pop() : context.go('/home'),
      ),
      body: StreamBuilder<SyncEngineSnapshot>(
        stream: dependencies.syncEngine.watchState(),
        initialData: dependencies.syncEngine.snapshot,
        builder: (context, engineSnapshot) {
          final engine =
              engineSnapshot.data ?? dependencies.syncEngine.snapshot;
          final syncEnded =
              _lastEngineState == SyncEngineState.running &&
              engine.state != SyncEngineState.running;
          final cloudScopeChanged =
              _lastCloudState != null &&
              (_lastCloudState != engine.cloudState ||
                  _lastAuthState != engine.authState);
          if (syncEnded || cloudScopeChanged) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _refreshCloudCount();
            });
          }
          _lastEngineState = engine.state;
          _lastCloudState = engine.cloudState;
          _lastAuthState = engine.authState;
          return FutureBuilder<List<RelioQueueItem>>(
            future: dependencies.repositories.syncQueue.listAll(),
            builder: (context, queueSnapshot) {
              final items = queueSnapshot.data ?? const <RelioQueueItem>[];
              final ownerId =
                  dependencies.cloudDataSource.currentIdentity?.userId;
              final accountItems = ownerId == null
                  ? const <RelioQueueItem>[]
                  : items
                        .where((item) => item.ownerUserId == ownerId)
                        .toList(growable: false);
              final privateItems = accountItems
                  .where(
                    (item) =>
                        item.operation ==
                        SyncOperation.privateBackupUpsert.value,
                  )
                  .toList(growable: false);
              final isSyncing =
                  _syncingAction || engine.state == SyncEngineState.running;
              final isWorking = isSyncing || _restoringAction;
              return FutureBuilder<int?>(
                future: _cloudCountFuture,
                builder: (context, cloudCountSnapshot) => ListView(
                  padding: const EdgeInsets.fromLTRB(
                    RelioSpacing.lg,
                    16,
                    RelioSpacing.lg,
                    28,
                  ),
                  children: [
                    CloudSyncStatusCard(
                      snapshot: engine,
                      privateItems: privateItems,
                      isRunning: isSyncing,
                      confirmedCount: cloudCountSnapshot.data,
                      countLoading:
                          cloudCountSnapshot.connectionState ==
                          ConnectionState.waiting,
                    ),
                    const SizedBox(height: 14),
                    SyncStatusSummary(
                      snapshot: engine,
                      items: accountItems,
                      ownerUserId: ownerId,
                      confirmedBackupCount: cloudCountSnapshot.data,
                      queueLoaded:
                          queueSnapshot.hasData && !queueSnapshot.hasError,
                    ),
                    const SizedBox(height: 14),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        key: const PageStorageKey<String>('sync-details'),
                        title: const Text('รายละเอียดเพิ่มเติม'),
                        initiallyExpanded: false,
                        expansionAnimationStyle:
                            MediaQuery.maybeOf(context)?.disableAnimations ==
                                true
                            ? const AnimationStyle(
                                duration: Duration.zero,
                                reverseDuration: Duration.zero,
                              )
                            : null,
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          _SharedChatStatusRow(
                            snapshot: engine,
                            items: accountItems,
                          ),
                          const SizedBox(height: 12),
                          _AutomaticBackupControl(
                            key: ValueKey(
                              dependencies.isGuestApplicationMode ||
                                      dependencies.isGuestCloudBackupSession
                                  ? 'guest-private-backup'
                                  : 'member-private-backup',
                            ),
                            guestMode:
                                dependencies.isGuestApplicationMode ||
                                dependencies.isGuestCloudBackupSession,
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: Semantics(
                              liveRegion: true,
                              button: true,
                              enabled: !isWorking,
                              label: isSyncing
                                  ? 'กำลังซิงก์ข้อมูล'
                                  : 'ซิงก์ตอนนี้',
                              child: FilledButton.icon(
                                key: const ValueKey('sync-now-button'),
                                onPressed: isWorking ? null : _runSync,
                                icon: isSyncing
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          semanticsLabel: 'กำลังซิงก์ข้อมูล',
                                        ),
                                      )
                                    : const Icon(Icons.cloud_sync_outlined),
                                label: Text(
                                  isSyncing ? 'กำลังซิงก์...' : 'ซิงก์ตอนนี้',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: RelioColors.primary,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(52),
                                ),
                              ),
                            ),
                          ),
                          if (engine.authState == AuthState.authenticated) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                key: const ValueKey('private-restore-button'),
                                onPressed: isWorking
                                    ? null
                                    : _restorePrivateBackup,
                                icon: _restoringAction
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.restore_rounded),
                                label: Text(
                                  _restoringAction
                                      ? 'กำลังกู้คืน...'
                                      : 'กู้คืนข้อมูลสำรอง',
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          FutureBuilder<int>(
                            future: dependencies.repositories.conversations
                                .countUnowned(),
                            builder: (context, snapshot) {
                              if (engine.authState != AuthState.authenticated ||
                                  (snapshot.data ?? 0) == 0) {
                                return const SizedBox.shrink();
                              }
                              return OutlinedButton.icon(
                                onPressed: isWorking ? null : _adoptGuestData,
                                icon: const Icon(
                                  Icons.person_add_alt_1_outlined,
                                ),
                                label: const Text(
                                  'นำข้อมูลออฟไลน์นี้ไปซิงก์กับบัญชีนี้',
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          _SyncDetails(
                            snapshot: engine,
                            allItems: accountItems,
                            privateItems: privateItems,
                            confirmedBackupCount: cloudCountSnapshot.data,
                            onRetry: _retryFailed,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
      'ตรวจคิวสำรองส่วนตัวแล้ว ข้อมูลที่บัญชีนี้เป็นเจ้าของจะอัปโหลดอัตโนมัติ',
    SyncEngineState.waitingForCloud =>
      'ยังซิงก์ไม่ได้ — ต้องมี Cloud และบัญชีที่เข้าสู่ระบบ',
    SyncEngineState.waitingForBinding =>
      'สำรองข้อมูลส่วนตัวแยกต่างหากแล้ว; แชท Cloud ยังรอการเชื่อมต่อที่ได้รับอนุญาต',
    SyncEngineState.waitingForOwnership =>
      'มีข้อมูลที่ยังยืนยันเจ้าของไม่ได้ จึงคงไว้ในเครื่อง',
    SyncEngineState.error => 'บางรายการซิงก์ไม่สำเร็จ ข้อมูลในเครื่องยังคงอยู่',
    SyncEngineState.running => 'กำลังซิงก์ข้อมูล',
    SyncEngineState.idle => 'ยังไม่ได้เริ่มซิงก์',
  };
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Sync Status Summary
class SyncStatusSummary extends StatelessWidget {
  const SyncStatusSummary({
    super.key,
    required this.snapshot,
    required this.items,
    required this.ownerUserId,
    this.queueLoaded = true,
    this.confirmedBackupCount,
  });

  final SyncEngineSnapshot snapshot;
  final List<RelioQueueItem> items;
  final String? ownerUserId;
  final bool queueLoaded;
  final int? confirmedBackupCount;

  @override
  Widget build(BuildContext context) {
    final queueCounts = SyncQueueCounts.fromItems(
      items,
      ownerUserId: ownerUserId,
    );
    final known = queueLoaded;
    final running = snapshot.state == SyncEngineState.running;
    final titles = ['รอซิงก์', 'ค้างส่ง', 'ซิงก์แล้ว'];
    final subtitles = [
      'ข้อมูลที่รอหรือกำลังส่งขึ้น Cloud',
      'ข้อมูลที่ส่งไม่สำเร็จ รอลองใหม่',
      'ข้อมูลที่ Cloud บันทึกสำเร็จแล้ว',
    ];
    final counts = [
      known ? '${queueCounts.pending}' : '—',
      known ? '${queueCounts.failed}' : '—',
      confirmedBackupCount == null ? '—' : '$confirmedBackupCount',
    ];
    final colors = [
      RelioColors.warning,
      RelioColors.rescue,
      RelioColors.success,
    ];
    final icons = [
      Icons.schedule_rounded,
      Icons.cloud_upload_outlined,
      Icons.check_circle_outline_rounded,
    ];
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleSmall!;
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final countStyle = theme.textTheme.titleMedium!;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    Size measure(String text, TextStyle style, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: width);
      final size = painter.size;
      painter.dispose();
      return size;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('สถานะข้อมูล', style: theme.textTheme.titleMedium),
            ),
            Tooltip(
              message:
                  'ประมวลผลตามสถานะ Cloud และสิทธิ์เดิม ไม่ได้เปิดการสำรองส่วนตัวแทนคุณ',
              child: Text('อัตโนมัติ', style: theme.textTheme.labelSmall),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final countWidth = counts
                  .map(
                    (text) => measure(text, countStyle, double.infinity).width,
                  )
                  .fold<double>(24, math.max);
              final textWidth = math.max(
                1.0,
                constraints.maxWidth - 32 - 22 - 24 - countWidth,
              );
              var contentHeight = 22.0;
              // คำนวณความสูงร่วมตาม TextScaler เพื่อให้แถวเท่ากันโดยไม่ตัดข้อความ accessibility
              for (var i = 0; i < 3; i++) {
                contentHeight = math.max(
                  contentHeight,
                  measure(titles[i], titleStyle, textWidth).height +
                      2 +
                      measure(subtitles[i], subtitleStyle, textWidth).height,
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    SizedBox(
                      key: ValueKey('sync-status-row-$i'),
                      height: contentHeight + 24,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            SizedBox.square(
                              key: ValueKey('sync-status-icon-$i'),
                              dimension: 22,
                              child: i == 0 && running
                                  ? Semantics(
                                      label: 'กำลังซิงก์ข้อมูลกับ Cloud',
                                      child: ExcludeSemantics(
                                        child: CircularProgressIndicator(
                                          key: const ValueKey(
                                            'sync-status-spinner',
                                          ),
                                          strokeWidth: 2,
                                          color: colors[i],
                                          value:
                                              MediaQuery.maybeOf(
                                                    context,
                                                  )?.disableAnimations ==
                                                  true
                                              ? 0.7
                                              : null,
                                        ),
                                      ),
                                    )
                                  : Icon(icons[i], size: 22, color: colors[i]),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(titles[i], style: titleStyle),
                                  const SizedBox(height: 2),
                                  Text(subtitles[i], style: subtitleStyle),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: countWidth,
                              child: Text(
                                counts[i],
                                key: ValueKey('sync-status-count-$i'),
                                textAlign: TextAlign.end,
                                style: countStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Automatic Backup Control)
class _AutomaticBackupControl extends StatefulWidget {
  const _AutomaticBackupControl({super.key, required this.guestMode});

  final bool guestMode;

  @override
  State<_AutomaticBackupControl> createState() =>
      _AutomaticBackupControlState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Automatic Backup Control State)
class _AutomaticBackupControlState extends State<_AutomaticBackupControl> {
  bool? _enabled;
  bool _saving = false;
  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoad) {
      _didLoad = true;
      _load();
    }
  }

  Future<void> _load() async {
    final value = await RelioDependencyScope.of(
      context,
    ).automaticPrivateBackupEnabled(guestMode: widget.guestMode);
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_saving) return;
    final dependencies = RelioDependencyScope.of(context);
    setState(() {
      _saving = true;
      _enabled = enabled;
    });
    try {
      await dependencies.repositories.settings.setBool(
        RelioSettingsRepository.automaticPrivateBackupKey,
        enabled,
      );
      if (!enabled) return;
      if (widget.guestMode) {
        final identity = await dependencies.ensureGuestCloudIdentity();
        if (identity == null) {
          throw const CloudException(
            'บันทึกการตั้งค่าแล้ว แต่ยังเริ่มสำรองไม่ได้ กรุณาตรวจอินเทอร์เน็ตและการตั้งค่า Guest Cloud',
            code: 'guestBackupUnavailable',
          );
        }
      }
      await dependencies.syncEngine.run();
    } on CloudException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปเดตการสำรองข้อมูลไม่สำเร็จ')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Card(
      child: SwitchListTile.adaptive(
        key: const ValueKey('automatic-private-backup-switch'),
        value: enabled ?? false,
        onChanged: _saving || enabled == null ? null : _setEnabled,
        title: const Text('สำรองข้อมูลส่วนตัวอัตโนมัติ'),
        subtitle: Text(
          widget.guestMode
              ? 'Guest เริ่มต้นปิดอยู่ เมื่อเปิดจะสำรองข้อมูลส่วนตัวไปยัง Cloud ของบัญชี Guest นี้ คิวและข้อมูลในเครื่องยังคงอยู่เมื่อปิด'
              : 'สำรองข้อมูลส่วนตัวที่บัญชีนี้เป็นเจ้าของโดยอัตโนมัติ แยกจากการส่งข้อความแชท Cloud',
        ),
        secondary: _saving
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_upload_outlined),
      ),
    );
  }
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Cloud Sync Status Card
class CloudSyncStatusCard extends StatelessWidget {
  const CloudSyncStatusCard({
    super.key,
    required this.snapshot,
    required this.privateItems,
    required this.isRunning,
    this.confirmedCount,
    this.countLoading = false,
  });

  final SyncEngineSnapshot snapshot;
  final List<RelioQueueItem> privateItems;
  final bool isRunning;
  final int? confirmedCount;
  final bool countLoading;

  @override
  Widget build(BuildContext context) {
    final state = _PrivateBackupViewState.from(
      snapshot,
      privateItems,
      confirmedCount: confirmedCount,
      countLoading: countLoading,
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 240);
    final isBusy =
        isRunning &&
        snapshot.cloudState == CloudState.ready &&
        (state.hasPending || state.hasProcessing);
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: state.color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: state.color.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: duration,
              child: SizedBox.square(
                key: ValueKey(isBusy ? 'busy' : state.icon.codePoint),
                dimension: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: state.color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: isBusy
                      ? Padding(
                          padding: const EdgeInsets.all(15),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: state.color,
                            semanticsLabel: 'กำลังซิงก์ข้อมูล',
                          ),
                        )
                      : Icon(state.icon, color: state.color, size: 27),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: AnimatedSwitcher(
                duration: duration,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    ...previousChildren,
                    currentChild ?? const SizedBox.shrink(),
                  ],
                ),
                child: Column(
                  key: ValueKey('${state.title}:${isBusy ? 'busy' : ''}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBusy ? 'กำลังสำรองข้อมูล' : state.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      isBusy
                          ? 'กำลังสำรองข้อมูลของคุณอย่างปลอดภัย'
                          : state.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (state.detail case final detail?) ...[
                      const SizedBox(height: 6),
                      Text(
                        detail,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: state.color),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      confirmedCount == null
                          ? countLoading
                                ? 'กำลังตรวจสอบจำนวนข้อมูลบน Cloud'
                                : 'จำนวนข้อมูลที่ยืนยันบน Cloud: —'
                          : 'จำนวนข้อมูลที่ยืนยันบน Cloud: $confirmedCount รายการ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: confirmedCount == null
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : state.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Private Backup View State)
class _PrivateBackupViewState {
  const _PrivateBackupViewState({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    this.detail,
    this.hasPending = false,
    this.hasProcessing = false,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final String? detail;
  final bool hasPending;
  final bool hasProcessing;

  factory _PrivateBackupViewState.from(
    SyncEngineSnapshot snapshot,
    List<RelioQueueItem> items, {
    required int? confirmedCount,
    required bool countLoading,
  }) {
    final pending = items.where((item) => item.status == 'pending').length;
    final processing = items
        .where((item) => item.status == 'processing')
        .length;
    final completed = confirmedCount ?? 0;
    final failedItems = items.where((item) => item.status == 'failed');
    final failed = failedItems.length;
    final failureCode =
        snapshot.lastError ?? failedItems.firstOrNull?.lastError;
    if (failed > 0) {
      return _PrivateBackupViewState(
        title: 'สำรองข้อมูลไม่สำเร็จ',
        subtitle: 'ข้อมูลเดิมยังอยู่ในเครื่อง ลองใหม่ได้เมื่อพร้อม',
        detail: _friendlySyncError(failureCode),
        color: RelioColors.sos,
        icon: Icons.cloud_off_outlined,
      );
    }
    if (snapshot.cloudState == CloudState.offline &&
        (pending > 0 || completed == 0)) {
      return const _PrivateBackupViewState(
        title: 'รออินเทอร์เน็ต',
        subtitle: 'ข้อมูลยังอยู่ในเครื่องอย่างปลอดภัย',
        color: RelioColors.secondaryText,
        icon: Icons.cloud_queue_outlined,
      );
    }
    if (snapshot.cloudState == CloudState.notConfigured ||
        snapshot.cloudState == CloudState.signedOut ||
        snapshot.authState != AuthState.authenticated) {
      return const _PrivateBackupViewState(
        title: 'ข้อมูลยังอยู่ในเครื่อง',
        subtitle: 'เข้าสู่ระบบและเชื่อมต่อ Cloud เพื่อสำรองข้อมูลส่วนตัว',
        color: RelioColors.secondaryText,
        icon: Icons.cloud_queue_outlined,
      );
    }
    if (confirmedCount == null) {
      return _PrivateBackupViewState(
        title: countLoading ? 'กำลังตรวจสอบ Cloud' : 'ตรวจสอบ Cloud ไม่ได้',
        subtitle: countLoading
            ? 'กำลังอ่านจำนวนข้อมูลสำรองของบัญชีนี้'
            : 'ยังยืนยันจำนวนข้อมูลสำรองจาก Cloud ไม่ได้',
        detail: countLoading ? null : 'จำนวนข้อมูลสำรอง: —',
        color: RelioColors.secondaryText,
        icon: Icons.cloud_queue_outlined,
        hasPending: pending > 0,
        hasProcessing: processing > 0,
      );
    }
    if (processing > 0 ||
        (pending > 0 && snapshot.state == SyncEngineState.running)) {
      return const _PrivateBackupViewState(
        title: 'กำลังสำรองข้อมูล',
        subtitle: 'กำลังสำรองข้อมูลของคุณอย่างปลอดภัย',
        color: RelioColors.primary,
        icon: Icons.sync_rounded,
        hasPending: true,
        hasProcessing: true,
      );
    }
    if (pending > 0) {
      return _PrivateBackupViewState(
        title: 'รอการสำรองข้อมูล',
        subtitle: 'ระบบจะดำเนินการเมื่อ Cloud พร้อม',
        detail: 'รออยู่ $pending รายการ',
        color: RelioColors.warning,
        icon: Icons.schedule_rounded,
        hasPending: true,
      );
    }
    if (completed > 0) {
      return _PrivateBackupViewState(
        title: 'สำรองข้อมูลล่าสุดแล้ว',
        subtitle: 'ข้อมูลส่วนตัวของคุณถูกเก็บบน Cloud แล้ว',
        detail: 'สำรองแล้ว $completed รายการ',
        color: RelioColors.success,
        icon: Icons.cloud_done_outlined,
      );
    }
    if (snapshot.state == SyncEngineState.error ||
        snapshot.cloudState == CloudState.error) {
      return _PrivateBackupViewState(
        title: 'สำรองข้อมูลไม่สำเร็จ',
        subtitle: 'ตรวจสอบการเชื่อมต่อแล้วลองอีกครั้ง',
        detail: _friendlySyncError(snapshot.lastError),
        color: RelioColors.sos,
        icon: Icons.cloud_off_outlined,
      );
    }
    return _PrivateBackupViewState(
      title: 'พร้อมสำรองข้อมูล',
      subtitle: 'ข้อมูลใหม่จะถูกบันทึกในเครื่องก่อนเสมอ',
      detail: 'ยืนยันบน Cloud $completed รายการ',
      color: RelioColors.primary,
      icon: Icons.cloud_queue_outlined,
    );
  }
}

String? _friendlySyncError(String? code) {
  if (code == null || code.isEmpty) return null;
  return switch (code) {
    'offline' ||
    'network' ||
    'pull_failed' => 'Cloud ไม่พร้อมใช้งาน ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง',
    'permissionDenied' || 'owner_mismatch' =>
      'บัญชีนี้ไม่มีสิทธิ์กับบางรายการ ข้อมูลยังอยู่ในเครื่อง',
    'server' => 'Cloud ขัดข้องชั่วคราว ลองใหม่ภายหลัง',
    'storage' ||
    'attachment_metadata_failed' ||
    'attachment_download_metadata_invalid' ||
    'attachment_download_mime_invalid' =>
      'ตรวจสอบไฟล์สำรองไม่ผ่าน ข้อมูลเดิมยังอยู่ในเครื่อง',
    'cloud_download_failed' =>
      'ดาวน์โหลดข้อมูลจาก Cloud ไม่สำเร็จ ลองใหม่ภายหลัง',
    'conflict' => 'มีข้อมูลขัดแย้งกัน โปรดลองซิงก์อีกครั้ง',
    _ => 'ตรวจสอบการเชื่อมต่อและบัญชี แล้วลองอีกครั้ง',
  };
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Shared Chat Status Row)
class _SharedChatStatusRow extends StatelessWidget {
  const _SharedChatStatusRow({required this.snapshot, required this.items});

  final SyncEngineSnapshot snapshot;
  final List<RelioQueueItem> items;

  @override
  Widget build(BuildContext context) {
    final shared = items
        .where((item) {
          final operation = SyncOperation.parse(item.operation);
          return operation == SyncOperation.conversationUpsert ||
              operation == SyncOperation.messageUpsert ||
              operation == SyncOperation.readReceiptUpsert;
        })
        .toList(growable: false);
    final waitingForBinding =
        snapshot.state == SyncEngineState.waitingForBinding;
    final waitingForInternet =
        snapshot.cloudState == CloudState.offline ||
        snapshot.state == SyncEngineState.waitingForCloud;
    final waitingForLogin =
        snapshot.cloudState == CloudState.notConfigured ||
        snapshot.cloudState == CloudState.signedOut ||
        snapshot.authState != AuthState.authenticated;
    final hasFailed = shared.any((item) => item.status == 'failed');
    final pending = shared.where((item) => item.status == 'pending').length;
    final processing = shared
        .where((item) => item.status == 'processing')
        .length;
    final hasSyncedChat = shared.any((item) => item.status == 'completed');
    final isRelevant =
        waitingForBinding ||
        waitingForInternet ||
        hasFailed ||
        pending > 0 ||
        processing > 0 ||
        hasSyncedChat;
    final status = hasFailed
        ? 'ซิงก์บทสนทนาไม่สำเร็จ'
        : waitingForBinding
        ? 'รอเชื่อมโยงบัญชีผู้สนทนา'
        : waitingForInternet
        ? 'รออินเทอร์เน็ต'
        : waitingForLogin && pending + processing > 0
        ? 'รอเข้าสู่ระบบ'
        : processing > 0
        ? 'กำลังซิงก์บทสนทนา'
        : pending > 0
        ? 'รอซิงก์บทสนทนา $pending รายการ'
        : hasSyncedChat
        ? 'ซิงก์บทสนทนาแล้ว'
        : 'ยังไม่มีแชทที่ซิงก์';
    final color = hasFailed
        ? RelioColors.sos
        : waitingForBinding || waitingForInternet || pending + processing > 0
        ? RelioColors.warning
        : hasSyncedChat
        ? RelioColors.success
        : RelioColors.secondaryText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.forum_outlined, size: 21, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'แชทกับบัญชีอื่น',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  isRelevant ? status : '$status · แยกจากข้อมูลสำรองส่วนตัว',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          if (isRelevant)
            Icon(Icons.info_outline_rounded, color: color, size: 19),
        ],
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Sync Details)
class _SyncDetails extends StatelessWidget {
  const _SyncDetails({
    required this.snapshot,
    required this.allItems,
    required this.privateItems,
    required this.confirmedBackupCount,
    required this.onRetry,
  });

  final SyncEngineSnapshot snapshot;
  final List<RelioQueueItem> allItems;
  final List<RelioQueueItem> privateItems;
  final int? confirmedBackupCount;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final pending = privateItems
        .where((item) => item.status == 'pending')
        .length;
    final completed = privateItems
        .where((item) => item.status == 'completed')
        .length;
    final failed = privateItems.where((item) => item.status == 'failed').length;
    final chatItems = allItems
        .where((item) {
          final operation = SyncOperation.parse(item.operation);
          return operation == SyncOperation.conversationUpsert ||
              operation == SyncOperation.messageUpsert ||
              operation == SyncOperation.readReceiptUpsert;
        })
        .toList(growable: false);
    final bindingLabel = snapshot.state == SyncEngineState.waitingForBinding
        ? 'ยังไม่เชื่อมต่อบทสนทนา Cloud'
        : chatItems.any((item) => item.status == 'completed')
        ? 'มีรายการแชทที่ซิงก์แล้ว'
        : 'ยังไม่มีรายการแชทที่ซิงก์';
    final attachmentCount = allItems.where((item) {
      final operation = SyncOperation.parse(item.operation);
      return operation == SyncOperation.attachmentUpload ||
          operation == SyncOperation.attachmentDownload ||
          operation == SyncOperation.attachmentMetadataUpsert;
    }).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailRow(
          label: 'สำรองข้อมูลส่วนตัว',
          value: _backupLabel(completed, pending, failed),
        ),
        _DetailRow(
          label: 'ข้อมูลที่สำรองแล้ว',
          value: confirmedBackupCount == null
              ? 'ตรวจสอบ Cloud ไม่ได้'
              : '$confirmedBackupCount รายการ',
        ),
        _DetailRow(label: 'ข้อมูลรอสำรอง', value: '$pending รายการ'),
        const _DetailRow(
          label: 'การส่ง Nearby / Relay',
          value: 'ตรวจสอบในบทสนทนา • คิว Cloud ไม่ใช่ยอดส่งถึงผู้รับ',
        ),
        _DetailRow(label: 'แชท Cloud', value: bindingLabel),
        _DetailRow(
          label: 'ไฟล์แนบในคิว Cloud',
          value: attachmentCount == 0
              ? 'ไม่มีรายการในคิว'
              : '$attachmentCount รายการ',
        ),
        _DetailRow(
          label: 'สำเร็จล่าสุดในรอบนี้',
          value: snapshot.lastSuccessAt == null
              ? 'ยังไม่มีข้อมูล'
              : _formatLocalTime(snapshot.lastSuccessAt!),
        ),
        if (allItems.isNotEmpty) ...[
          const Divider(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'คิวงานตามประเภท',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 6),
          ..._operationGroups(allItems).map(
            (group) => _DetailRow(label: group.label, value: group.summary),
          ),
        ],
        if (failed > 0 || snapshot.state == SyncEngineState.error) ...[
          const Divider(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _friendlySyncError(snapshot.lastError) ??
                  'บางรายการลองซิงก์ไม่สำเร็จ',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: RelioColors.sos),
            ),
          ),
          if (failed > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('ลองรายการที่ล้มเหลวอีกครั้ง'),
              ),
            ),
        ],
      ],
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Detail Row)
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Operation Group)
class _OperationGroup {
  const _OperationGroup(this.label, this.summary);
  final String label;
  final String summary;
}

List<_OperationGroup> _operationGroups(List<RelioQueueItem> items) {
  final groups = <String, Map<String, int>>{};
  for (final item in items) {
    final label = _operationLabel(item.operation);
    final statuses = groups.putIfAbsent(label, () => <String, int>{});
    statuses[item.status] = (statuses[item.status] ?? 0) + 1;
  }
  final labels = groups.keys.toList()..sort();
  return labels
      .map((label) {
        final statusCounts = groups[label]!;
        final parts = <String>[];
        for (final status in {
          'completed',
          'pending',
          'processing',
          'failed',
          ...statusCounts.keys,
        }) {
          final count = statusCounts[status] ?? 0;
          if (count > 0) {
            parts.add(
              '${_statusLabel(status, isBackup: label == 'สำรองข้อมูลส่วนตัว')} $count',
            );
          }
        }
        return _OperationGroup(label, parts.join(' · '));
      })
      .toList(growable: false);
}

String _backupLabel(int completed, int pending, int failed) {
  if (failed > 0) return 'มีรายการผิดพลาด $failed รายการ';
  if (pending > 0) return 'รอซิงก์ $pending รายการ';
  if (completed > 0) return 'สำรองแล้ว $completed รายการ';
  return 'ยังไม่มีรายการสำรอง';
}

String _formatLocalTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

String _operationLabel(String operation) =>
    switch (SyncOperation.parse(operation)) {
      SyncOperation.profileUpsert => 'โปรไฟล์',
      SyncOperation.conversationUpsert => 'บทสนทนา',
      SyncOperation.messageUpsert => 'ข้อความ',
      SyncOperation.sosUpsert => 'ข้อมูล SOS',
      SyncOperation.attachmentMetadataUpsert => 'ข้อมูลไฟล์แนบ',
      SyncOperation.attachmentUpload => 'ไฟล์แนบ',
      SyncOperation.attachmentDownload => 'ดาวน์โหลดไฟล์แนบ',
      SyncOperation.readReceiptUpsert => 'ใบตอบรับการอ่าน',
      SyncOperation.privateBackupUpsert => 'สำรองข้อมูลส่วนตัว',
      null => 'รายการอื่น',
    };

String _statusLabel(String status, {bool isBackup = false}) => switch (status) {
  'completed' => isBackup ? 'ข้อมูลที่สำรองแล้ว' : 'ซิงก์แล้ว',
  'pending' => isBackup ? 'ข้อมูลรอสำรอง' : 'รอซิงก์',
  'processing' => isBackup ? 'กำลังสำรอง' : 'กำลังซิงก์',
  'failed' => isBackup ? 'สำรองไม่สำเร็จ' : 'ซิงก์ไม่สำเร็จ',
  _ => 'ไม่ทราบสถานะ',
};
