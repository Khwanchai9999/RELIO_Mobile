import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final saved = await _store.read();
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
  late final GoRouter _router = createRelioRouter();
  late final RelioDependencies _dependencies;
  late final bool _ownsDependencies;
  late final bool _ownsThemeController;

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
    unawaited(_themeController.load());
    unawaited(_dependencies.initialize());
  }

  void _handleThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _themeController.removeListener(_handleThemeChanged);
    if (_ownsThemeController) _themeController.dispose();
    if (_ownsDependencies) unawaited(_dependencies.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarColor: Theme.of(
                  context,
                ).scaffoldBackgroundColor,
                systemNavigationBarIconBrightness: brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
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
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
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
