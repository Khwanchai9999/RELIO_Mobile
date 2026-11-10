// หน้าจอไฟฉายจากแสงหน้าจอ มีโหมดแสงและปุ่มควบคุมที่ผู้ใช้สั่งเอง
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

// ชนิดตัวเลือกที่ระบุสถานะหรือโหมดซึ่งส่วนอื่นของโมดูลนำไปใช้: Screen Light Mode
enum ScreenLightMode { white, redBlue }

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Screen Flashlight Screen
class ScreenFlashlightScreen extends StatefulWidget {
  const ScreenFlashlightScreen({super.key});

  @override
  State<ScreenFlashlightScreen> createState() => _ScreenFlashlightScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Screen Flashlight Screen State)
class _ScreenFlashlightScreenState extends State<ScreenFlashlightScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('relio/screen_flashlight');

  ScreenLightMode _mode = ScreenLightMode.white;
  bool _red = true;
  Timer? _signalTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enterFullscreen());
    unawaited(_setKeepAwake(true));
  }

  Future<void> _enterFullscreen() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } on Object {
      // แสงหน้าจอยังใช้งานได้หากระบบไม่อนุญาต immersive mode
    }
  }

  Future<void> _restoreSystemUi() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } on Object {
      // ไม่แตะค่าความสว่างหรือการตั้งค่าหน้าจอของผู้ใช้
    }
  }

  Future<void> _setKeepAwake(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('keepAwake', enabled);
    } on MissingPluginException {
      // Platform อื่นไม่มี native Android window flag นี้
    } on PlatformException {
      // ไฟฉายยังทำงานได้โดยไม่ค้างหน้าจอ
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_setKeepAwake(true));
      if (_mode == ScreenLightMode.redBlue) _setWhite();
    } else {
      _stopSignal();
      unawaited(_setKeepAwake(false));
      if (_mode == ScreenLightMode.redBlue && mounted) _setWhite();
    }
  }

  void _toggleMode() {
    if (_disposed) return;
    if (_mode == ScreenLightMode.redBlue) {
      _setWhite();
      return;
    }
    _startSignal();
  }

  // ยกเลิก Timer เดิมก่อนเริ่มสลับสี เพื่อไม่ให้การแตะซ้ำสร้างจังหวะกะพริบซ้อนกัน
  void _startSignal() {
    _signalTimer?.cancel();
    setState(() {
      _mode = ScreenLightMode.redBlue;
      _red = true;
    });
    _signalTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _disposed) return;
      setState(() => _red = !_red);
    });
  }

  void _stopSignal() {
    _signalTimer?.cancel();
    _signalTimer = null;
  }

  void _setWhite() {
    _stopSignal();
    if (!mounted) return;
    setState(() {
      _mode = ScreenLightMode.white;
      _red = true;
    });
  }

  void _exit() {
    _stopSignal();
    unawaited(_setKeepAwake(false));
    unawaited(_restoreSystemUi());
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopSignal();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_setKeepAwake(false));
    unawaited(_restoreSystemUi());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _mode == ScreenLightMode.white
        ? Colors.white
        : _red
        ? const Color(0xFFFF0000)
        : const Color(0xFF0000FF);
    return Scaffold(
      backgroundColor: color,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final bar = _ControlBar(
            vertical: orientation == Orientation.landscape,
            mode: _mode,
            onToggle: _toggleMode,
            onExit: _exit,
          );
          if (orientation == Orientation.landscape) {
            return Row(
              children: [
                Expanded(child: _LightingSurface(onTap: _toggleMode)),
                SafeArea(child: bar),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: _LightingSurface(onTap: _toggleMode)),
              SafeArea(top: false, child: bar),
            ],
          );
        },
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Lighting Surface)
class _LightingSurface extends StatelessWidget {
  const _LightingSurface({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'ไฟฉายหน้าจอ',
    hint: 'แตะหน้าจอเพื่อสลับโหมด',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox.expand(),
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Control Bar)
class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.vertical,
    required this.mode,
    required this.onToggle,
    required this.onExit,
  });

  final bool vertical;
  final ScreenLightMode mode;
  final VoidCallback onToggle;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final modeLabel = Text(
      mode == ScreenLightMode.white ? 'แสงสีขาว' : 'ไฟสัญญาณ',
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    );
    final switchButton = OutlinedButton(
      onPressed: onToggle,
      child: const Text('สลับ'),
    );
    final exitButton = FilledButton(
      onPressed: onExit,
      child: const Text('ออก'),
    );
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE6222222),
        borderRadius: BorderRadius.circular(18),
      ),
      child: vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                modeLabel,
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'คำเตือน: แสงกะพริบอาจไม่เหมาะกับผู้ไวต่อแสง',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
                switchButton,
                exitButton,
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: modeLabel),
                    const Flexible(
                      child: Text(
                        'คำเตือน: แสงกะพริบอาจไม่เหมาะกับผู้ไวต่อแสง',
                        textAlign: TextAlign.end,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    switchButton,
                    const SizedBox(width: 6),
                    exitButton,
                  ],
                ),
              ],
            ),
    );
  }
}
