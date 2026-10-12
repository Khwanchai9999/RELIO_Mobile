import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/theme/relio_colors.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../core/domain/relio_entities.dart';
import '../../data/models/prototype_models.dart';

class NearbyMapCanvas extends StatefulWidget {
  const NearbyMapCanvas({
    required this.peers,
    required this.myLocation,
    required this.navigationTargetId,
    required this.onPeerSelected,
    super.key,
  });

  final List<RelioDevice> peers;
  final LocationData? myLocation;
  final String? navigationTargetId;
  final ValueChanged<String> onPeerSelected;

  @override
  State<NearbyMapCanvas> createState() => _NearbyMapCanvasState();
}

class _NearbyMapCanvasState extends State<NearbyMapCanvas> {
  static const _styleUrl = String.fromEnvironment(
    'RELIO_MAP_STYLE_URL',
    defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
  );

  MapLibreMapController? _controller;
  Timer? _loadWatchdog;
  bool _styleLoaded = false;
  bool _unavailable = false;
  bool _markersBusy = false;
  bool _refreshPending = false;
  bool _locationCameraFocused = false;
  String? _cameraTargetId;
  int _mapAttempt = 0;

  @override
  void didUpdateWidget(covariant NearbyMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_styleLoaded &&
        (!_samePeers(oldWidget.peers, widget.peers) ||
            oldWidget.myLocation != widget.myLocation ||
            oldWidget.navigationTargetId != widget.navigationTargetId)) {
      unawaited(_refreshMarkers());
    }
  }

  bool _samePeers(List<RelioDevice> a, List<RelioDevice> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      final left = a[index];
      final right = b[index];
      if (left.id != right.id ||
          left.name != right.name ||
          left.status != right.status ||
          left.batteryLevel != right.batteryLevel ||
          left.isCharging != right.isCharging ||
          left.locationLatitude != right.locationLatitude ||
          left.locationLongitude != right.locationLongitude ||
          left.locationCapturedAt != right.locationCapturedAt) {
        return false;
      }
    }
    return true;
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.onCircleTapped.add(_onCircleTapped);
    controller.onSymbolTapped.add(_onSymbolTapped);
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || _styleLoaded) return;
      setState(() => _unavailable = true);
    });
  }

  void _onStyleLoaded() {
    _loadWatchdog?.cancel();
    if (!mounted) return;
    setState(() {
      _styleLoaded = true;
      _unavailable = false;
    });
    unawaited(_refreshMarkers());
  }

  void _onCircleTapped(Circle circle) {
    final deviceId = circle.data?['deviceId'];
    if (deviceId is String) widget.onPeerSelected(deviceId);
  }

  void _onSymbolTapped(Symbol symbol) {
    final deviceId = symbol.data?['deviceId'];
    if (deviceId is String) widget.onPeerSelected(deviceId);
  }

  Future<void> _refreshMarkers() async {
    final controller = _controller;
    if (controller == null || !_styleLoaded) return;
    if (_markersBusy) {
      _refreshPending = true;
      return;
    }
    final labelColor = _hex(Theme.of(context).colorScheme.onSurface);
    _markersBusy = true;
    try {
      await controller.clearCircles();
      await controller.clearSymbols();
      await controller.clearLines();

      final myLocation = widget.myLocation;
      if (myLocation != null &&
          NearbyMapCalculations.isValidPoint(
            myLocation.latitude,
            myLocation.longitude,
          )) {
        await controller.addCircle(
          CircleOptions(
            geometry: LatLng(myLocation.latitude, myLocation.longitude),
            circleRadius: 8,
            circleColor: _hex(RelioColors.info),
            circleStrokeWidth: 3,
            circleStrokeColor: '#FFFFFF',
          ),
        );
        await controller.addSymbol(
          SymbolOptions(
            geometry: LatLng(myLocation.latitude, myLocation.longitude),
            textField: '📍 คุณ',
            textSize: 12,
            textColor: labelColor,
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2,
            textOffset: const Offset(0, 1.5),
          ),
        );
        if (widget.navigationTargetId == null && !_locationCameraFocused) {
          await controller.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(myLocation.latitude, myLocation.longitude),
              14,
            ),
          );
          _locationCameraFocused = true;
        }
      }

      RelioDevice? navigationTarget;
      for (final peer in widget.peers) {
        if (!NearbyMapCalculations.isValidPoint(
          peer.locationLatitude,
          peer.locationLongitude,
        )) {
          continue;
        }
        final color = _statusColor(peer.status);
        final point = LatLng(peer.locationLatitude!, peer.locationLongitude!);
        final selected = peer.id == widget.navigationTargetId;
        await controller.addCircle(
          CircleOptions(
            geometry: point,
            circleRadius: selected
                ? 12
                : peer.status == DeviceStatus.sos
                ? 10
                : 8,
            circleColor: color,
            circleStrokeWidth: selected ? 5 : 3,
            circleStrokeColor: selected
                ? _hex(RelioColors.primaryDark)
                : '#FFFFFF',
          ),
          {'deviceId': peer.id},
        );
        final battery = peer.batteryLevel == null
            ? ''
            : '\n${peer.isCharging == true ? '⚡' : '🔋'} ${peer.batteryLevel}%';
        await controller.addSymbol(
          SymbolOptions(
            geometry: point,
            textField:
                '${selected ? '📍 ' : ''}${_compactName(peer.name)}$battery',
            textSize: 11,
            textColor: color,
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2,
            textOffset: const Offset(0, 1.7),
          ),
          {'deviceId': peer.id},
        );
        if (peer.id == widget.navigationTargetId) navigationTarget = peer;
      }

      if (myLocation != null && navigationTarget != null) {
        await controller.addLine(
          LineOptions(
            geometry: [
              LatLng(myLocation.latitude, myLocation.longitude),
              LatLng(
                navigationTarget.locationLatitude!,
                navigationTarget.locationLongitude!,
              ),
            ],
            lineColor: _hex(RelioColors.primaryDark),
            lineWidth: 3,
            lineOpacity: 0.85,
          ),
        );
      }
      if (navigationTarget != null && _cameraTargetId != navigationTarget.id) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(
              navigationTarget.locationLatitude!,
              navigationTarget.locationLongitude!,
            ),
            14,
          ),
        );
        _cameraTargetId = navigationTarget.id;
      }
    } on Object {
      if (mounted) setState(() => _unavailable = true);
    } finally {
      _markersBusy = false;
      if (_refreshPending && mounted) {
        _refreshPending = false;
        unawaited(_refreshMarkers());
      }
    }
  }

  String _statusColor(DeviceStatus status) => switch (status) {
    DeviceStatus.sos => _hex(RelioColors.sos),
    DeviceStatus.rescue => _hex(RelioColors.rescue),
    DeviceStatus.normal => _hex(RelioColors.success),
    DeviceStatus.offline => _hex(RelioColors.muted),
  };

  String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  String _compactName(String name) {
    final compact = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 24 ? compact : '${compact.substring(0, 23)}…';
  }

  void _retry() {
    _loadWatchdog?.cancel();
    setState(() {
      _controller = null;
      _styleLoaded = false;
      _unavailable = false;
      _mapAttempt++;
    });
  }

  @override
  void dispose() {
    _loadWatchdog?.cancel();
    final controller = _controller;
    if (controller != null) {
      controller.onCircleTapped.remove(_onCircleTapped);
      controller.onSymbolTapped.remove(_onSymbolTapped);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (Platform.isAndroid || Platform.isIOS)
          MapLibreMap(
            key: ValueKey(_mapAttempt),
            styleString: _styleUrl,
            initialCameraPosition: const CameraPosition(
              target: LatLng(15, 105),
              zoom: 2.5,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            compassEnabled: false,
            logoEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            attributionButtonMargins: const Point(10, 28),
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
          )
        else
          ColoredBox(color: colors.surfaceContainerLow),
        Positioned(
          left: 12,
          bottom: 38,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '© OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        if (_unavailable)
          Positioned.fill(
            child: ColoredBox(
              color: colors.surface.withValues(alpha: 0.88),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map_outlined, size: 42),
                      const SizedBox(height: 8),
                      const Text('แผนที่ยังใช้งานไม่ได้'),
                      const SizedBox(height: 4),
                      const Text('Nearby และรายการอุปกรณ์ยังใช้ต่อได้'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('ลองแผนที่อีกครั้ง'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
