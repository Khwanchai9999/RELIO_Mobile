import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/cloud/cloud_models.dart';
import '../core/relio_dependencies.dart';
import 'environment.dart';
import 'router.dart';
import 'theme/relio_theme.dart';

abstract interface class RelioThemePreferenceStore {
  Future<String?> read();

  Future<void> write(String value);
}

class SharedPreferencesThemePreferenceStore
    implements RelioThemePreferenceStore {
  static const key = 'relio_theme_mode';

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _instance async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String?> read() async => (await _instance).getString(key);

  @override
  Future<void> write(String value) async {
    await (await _instance).setString(key, value);
  }
}

class RelioThemeController extends ChangeNotifier {
  RelioThemeController({RelioThemePreferenceStore? store})
    : _store = store ?? SharedPreferencesThemePreferenceStore();

  static const defaultMode = ThemeMode.system;

  final RelioThemePreferenceStore _store;
  ThemeMode _mode = defaultMode;
  Future<void>? _loadOperation;
  bool _loaded = false;

  ThemeMode get mode => _mode;

  bool get isLoaded => _loaded;

  Future<void> load() {
    return _loadOperation ??= _load();
  }

  Future<void> _load() async {
    // เก็บค่าเป็น light/dark/system เพื่อไม่ผูก persistence กับข้อความบน UI
    String? saved;
    try {
      saved = await _store.read();
    } on Object {
      // โหลดแอปต่อด้วย ThemeMode.system ได้ แม้ preference store ใช้งานไม่ได้
      saved = null;
    }
    final nextMode = switch (saved) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => defaultMode,
    };
    _loaded = true;
    if (_mode == nextMode) return;
    _mode = nextMode;
    notifyListeners();
  }

  // แจ้ง UI ให้เปลี่ยน ThemeMode ทันที แล้วบันทึกค่าไว้สำหรับการเปิดแอปครั้งถัดไป
  Future<void> setMode(ThemeMode mode) async {
    if (!_loaded) await load();
    if (_mode == mode) return;

    _mode = mode;
    notifyListeners();
    await _store.write(switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
    });
  }
}

class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class RelioThemeScope extends InheritedNotifier<RelioThemeController> {
  const RelioThemeScope({
    required super.notifier,
    required super.child,
    super.key,
  });

  static RelioThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RelioThemeScope>();
    assert(scope != null, 'RelioThemeScope is missing above this context.');
    return scope!.notifier!;
  }
}

class RelioApp extends StatefulWidget {
  const RelioApp({this.dependencies, this.themeController, super.key});

  final RelioDependencies? dependencies;
  final RelioThemeController? themeController;

  @override
  State<RelioApp> createState() => _RelioAppState();
}

class _RelioAppState extends State<RelioApp> with WidgetsBindingObserver {
  late final RelioThemeController _themeController;
  late final GoRouter _router;
  late final _RouterRefresh _routerRefresh;
  late final VoidCallback _developerModeListener;
  late final RelioDependencies _dependencies;
  late final bool _ownsDependencies;
  late final bool _ownsThemeController;
  StreamSubscription<AuthState>? _authStateSubscription;
  StreamSubscription<void>? _localAuthSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeController = widget.themeController ?? RelioThemeController();
    _ownsThemeController = widget.themeController == null;
    // ThemeController ตัวนี้ใช้ร่วมกันทั้งแอป เพื่อให้ MaterialApp rebuild ตาม Settings
    _themeController.addListener(_handleThemeChanged);
    _dependencies = widget.dependencies ?? RelioDependencies();
    _ownsDependencies = widget.dependencies == null;
    _routerRefresh = _RouterRefresh();
    _router = createRelioRouter(
      authReady: () => _dependencies.authInitialized,
      hasSession: () => _dependencies.hasSelectedUserSession,
      passwordRecovery: () =>
          _dependencies.authService.state == AuthState.passwordRecovery,
      developerModeEnabled: () =>
          _dependencies.internalExperience.developerModeEnabled,
      refreshListenable: _routerRefresh,
    );
    _developerModeListener = _routerRefresh.refresh;
    _dependencies.internalExperience.addListener(_developerModeListener);
    _authStateSubscription = _dependencies.authService.watchState().listen((_) {
      _routerRefresh.refresh();
    });
    _localAuthSubscription = _dependencies.localAuthChanges.listen((_) {
      _routerRefresh.refresh();
    });
    _router.routerDelegate.addListener(_updateNearbyLifecycleContext);
    _updateNearbyLifecycleContext();
    unawaited(_themeController.load());
    unawaited(
      _dependencies.initializeAuth().whenComplete(_routerRefresh.refresh),
    );
    unawaited(_dependencies.initialize());
  }

  void _handleThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.routerDelegate.removeListener(_updateNearbyLifecycleContext);
    _router.dispose();
    _dependencies.internalExperience.removeListener(_developerModeListener);
    unawaited(_authStateSubscription?.cancel());
    unawaited(_localAuthSubscription?.cancel());
    _routerRefresh.dispose();
    _themeController.removeListener(_handleThemeChanged);
    if (_ownsThemeController) _themeController.dispose();
    if (_ownsDependencies) unawaited(_dependencies.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateNearbyLifecycleContext(lifecycleState: state.name);
    if (state == AppLifecycleState.resumed) {
      // เมื่อกลับมา foreground ให้ลองซิงก์คิวที่เป็นของบัญชีปัจจุบันอีกครั้ง
      unawaited(_dependencies.syncEngine.run());
      unawaited(_dependencies.appUpdateService.checkForUpdate());
      unawaited(_dependencies.connectivityStatus.refresh());
      unawaited(_dependencies.setNearbyForeground(true));
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // รวม start/stop ในคิวเดียว ป้องกัน resume ชนกับการหยุด session
      unawaited(_dependencies.setNearbyForeground(false));
    }
  }

  void _updateNearbyLifecycleContext({String? lifecycleState}) {
    _dependencies.nearbyService.updateLifecycleContext(
      lifecycleState:
          lifecycleState ??
          WidgetsBinding.instance.lifecycleState?.name ??
          'unknown',
      route: _router.routerDelegate.currentConfiguration.uri.path,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RelioThemeScope(
      notifier: _themeController,
      child: RelioDependencyScope(
        dependencies: _dependencies,
        child: MaterialApp.router(
          title: RelioBuildInfo.appName,
          debugShowCheckedModeBanner: false,
          theme: RelioTheme.light(),
          darkTheme: RelioTheme.dark(),
          themeMode: _themeController.mode,
          routerConfig: _router,
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            return IncomingConnectionPromptHost(
              dependencies: _dependencies,
              router: _router,
              navigatorKey: _router.routerDelegate.navigatorKey,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
                  systemNavigationBarColor: Theme.of(
                    context,
                  ).scaffoldBackgroundColor,
                  systemNavigationBarIconBrightness:
                      brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
  }
}

class IncomingConnectionPromptHost extends StatefulWidget {
  const IncomingConnectionPromptHost({
    required this.dependencies,
    required this.child,
    this.router,
    this.navigatorKey,
    super.key,
  });

  final RelioDependencies dependencies;
  final Widget child;
  final GoRouter? router;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<IncomingConnectionPromptHost> createState() =>
      _IncomingConnectionPromptHostState();
}

class _IncomingConnectionPromptHostState
    extends State<IncomingConnectionPromptHost> {
  bool _dialogOpen = false;
  StreamSubscription<String>? _notificationRouteSubscription;

  @override
  void initState() {
    super.initState();
    widget.dependencies.nearbyService.addListener(_showNextRequest);
    _notificationRouteSubscription = widget
        .dependencies
        .localNotificationService
        .tappedRoutes
        .listen(_openNotificationRoute);
    unawaited(
      widget.dependencies.localNotificationService.consumeInitialRoute().then((
        route,
      ) {
        if (route != null) _openNotificationRoute(route);
      }),
    );
  }

  @override
  void didUpdateWidget(IncomingConnectionPromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dependencies != widget.dependencies) {
      oldWidget.dependencies.nearbyService.removeListener(_showNextRequest);
      widget.dependencies.nearbyService.addListener(_showNextRequest);
      unawaited(_notificationRouteSubscription?.cancel());
      _notificationRouteSubscription = widget
          .dependencies
          .localNotificationService
          .tappedRoutes
          .listen(_openNotificationRoute);
    }
  }

  @override
  void dispose() {
    widget.dependencies.nearbyService.removeListener(_showNextRequest);
    unawaited(_notificationRouteSubscription?.cancel());
    super.dispose();
  }

  void _openNotificationRoute(String route) {
    final uri = Uri.tryParse(route);
    final isEmergency =
        route == '/sos' || route == '/sos/active' || route == '/rescue';
    final isChat = RegExp(r'^/chat/[A-Za-z0-9._:-]{1,128}$').hasMatch(route);
    final isExactSos =
        uri != null &&
        RegExp(
          r'^/rescue/request/[A-Za-z0-9._:-]{1,128}$',
        ).hasMatch(uri.path) &&
        uri.queryParameters.length == 1 &&
        RegExp(
          r'^[0-9a-fA-F-]{36}$',
        ).hasMatch(uri.queryParameters['eventId'] ?? '');
    if (!mounted || (!isEmergency && !isChat && !isExactSos)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final router = widget.router;
      if (mounted && router != null) {
        if (isExactSos) {
          router.go(route);
        } else {
          unawaited(router.push(route));
        }
      }
    });
    // Warm notification อาจเข้าหลัง frame ปัจจุบัน จึงขอ frame ให้ callback ทำงาน
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _showNextRequest() {
    if (!mounted || _dialogOpen) return;
    final service = widget.dependencies.nearbyService;
    if (service.pendingConnectionRequests.isEmpty) return;
    final entry = service.pendingConnectionRequests.entries.first;
    final request = entry.value;
    _dialogOpen = true;
    widget.dependencies.diagnostics.record(
      'connection',
      'incoming_request_ui_observed',
      connectionTraceId: service.connectionTraceForEndpoint(entry.key),
      operation: 'IncomingConnectionPromptHost',
      peerIdentifier: entry.key,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final navigator = widget.navigatorKey?.currentState;
      if (navigator == null) {
        widget.dependencies.diagnostics.record(
          'connection',
          'incoming_request_ui_unavailable',
          connectionTraceId: service.connectionTraceForEndpoint(entry.key),
          operation: 'showDialog',
          peerIdentifier: entry.key,
          reason: 'root_navigator_not_ready',
        );
        _dialogOpen = false;
        return;
      }
      widget.dependencies.diagnostics.record(
        'connection',
        'accept_reject_dialog_displayed',
        connectionTraceId: service.connectionTraceForEndpoint(entry.key),
        operation: 'showDialog',
        peerIdentifier: entry.key,
      );
      final accepted = await navigator.push<bool>(
        DialogRoute<bool>(
          context: navigator.context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              request.isIncomingRequest
                  ? 'คำขอเชื่อมต่อ'
                  : 'ยืนยันการเชื่อมต่อ',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.isIncomingRequest
                      ? '${request.peer.name} ต้องการเชื่อมต่อกับคุณ'
                      : 'กำลังเชื่อมต่อกับ ${request.peer.name}',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(request.isIncomingRequest ? 'ปฏิเสธ' : 'ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(request.isIncomingRequest ? 'ยอมรับ' : 'เชื่อมต่อ'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (accepted == true) {
        await service.acceptConnectionRequest(entry.key);
      } else {
        await service.rejectConnectionRequest(entry.key);
      }
      _dialogOpen = false;
      _showNextRequest();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class RelioShell extends StatelessWidget {
  const RelioShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  int get selectedIndex {
    if (location.startsWith('/nearby')) return 1;
    if (location.startsWith('/chats') || location.startsWith('/chat/')) {
      return 2;
    }
    if (location.startsWith('/sos')) return 3;
    if (location.startsWith('/profile') || location.startsWith('/settings')) {
      return 4;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    const routes = ['/home', '/nearby', '/chats', '/sos', '/profile'];
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => context.go(routes[index]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'หน้าหลัก',
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: 'ใกล้เคียง',
          ),
          NavigationDestination(
            icon: _UnreadChatBadge(selected: false),
            selectedIcon: _UnreadChatBadge(selected: true),
            label: 'แชท',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning_amber),
            label: 'SOS',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'โปรไฟล์',
          ),
        ],
      ),
    );
  }
}

class _UnreadChatBadge extends StatelessWidget {
  const _UnreadChatBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final stream = RelioDependencyScope.of(
      context,
    ).repositories.conversations.watchConversations();
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        final unread = (snapshot.data ?? const []).fold<int>(
          0,
          (total, conversation) => total + conversation.unreadCount,
        );
        return Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: Icon(selected ? Icons.chat_bubble : Icons.chat_bubble_outline),
        );
      },
    );
  }
}
