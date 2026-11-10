// พื้นผิวแผนที่ Nearby สำหรับวาด peer และตำแหน่งที่ได้รับ พร้อมดูแล lifecycle ของแผนที่อย่างแยกส่วน
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/theme/relio_colors.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../core/location/nearby_location_quality.dart';
import '../../core/location/packaged_map_service.dart';
import '../../core/domain/relio_entities.dart';
import '../../data/models/prototype_models.dart';
import 'nearby_offline_map.dart';
import 'nearby_marker_hit_test.dart';
import 'nearby_marker_reconciliation.dart';

String nearbyTargetLocationLabel({
  required bool shared,
  required bool historical,
}) => shared
    ? 'ตำแหน่งที่แชร์'
    : historical
    ? 'SOS • ตำแหน่งที่บันทึกไว้'
    : 'SOS • ตำแหน่งจากคำขอ';

Color nearbyTargetLocationColor({required bool shared}) =>
    shared ? RelioColors.primary : RelioColors.sos;

const nearbyMapTileMaxZoom = 15;
const nearbyMapCameraMaxZoom = 18.0;
const nearbyMapAttributionPosition = AttributionButtonPosition.bottomLeft;
const nearbyMapAttributionMargins = Point(10, 28);
const nearbySelfMarkerDiameter = 36.0;
const _nearbySelfMarkerRadius = 15.0;
const _nearbySelfMarkerStroke = 3.0;

Color nearbyMapStatusColor(DeviceStatus status) => switch (status) {
  DeviceStatus.sos => RelioColors.mapSos,
  DeviceStatus.rescue => RelioColors.mapRescue,
  DeviceStatus.normal => RelioColors.mapNormal,
  DeviceStatus.offline => RelioColors.muted,
};

Color nearbyPeerMarkerStrokeColor({
  required bool selected,
  required bool fresh,
}) => selected
    ? RelioColors.primaryDark
    : fresh
    ? Colors.white
    : RelioColors.warning;

CameraPosition nearbyInitialCameraPosition({
  CameraPosition? savedViewport,
  LocationData? selfLocation,
  DateTime? now,
}) {
  final saved = savedViewport;
  if (saved != null &&
      saved.zoom.isFinite &&
      saved.zoom >= 0 &&
      NearbyMapCalculations.isValidPoint(
        saved.target.latitude,
        saved.target.longitude,
      )) {
    return CameraPosition(
      target: saved.target,
      zoom: saved.zoom.clamp(0, nearbyMapCameraMaxZoom).toDouble(),
    );
  }
  if (selfLocation != null &&
      NearbyMapCalculations.isValidPoint(
        selfLocation.latitude,
        selfLocation.longitude,
      )) {
    final age = (now ?? DateTime.now()).difference(selfLocation.capturedAt);
    if (!age.isNegative && age <= NearbyMapCalculations.freshFor) {
      return CameraPosition(
        target: LatLng(selfLocation.latitude, selfLocation.longitude),
        zoom: 12,
      );
    }
  }
  return const CameraPosition(target: LatLng(15, 101), zoom: 5);
}

// วาด peer และเหตุการณ์บนแผนที่จาก state ที่แอปเตรียมไว้ให้
// Widget นี้เป็นชั้นนำเสนอ ไม่เป็นเจ้าของการค้นหา Nearby หรือการขอ GPS
class NearbyMapCanvas extends StatefulWidget {
  const NearbyMapCanvas({
    required this.peers,
    required this.myLocation,
    required this.navigationTargetId,
    required this.onPeerSelected,
    this.targetLocationOverride,
    this.targetLocationHistorical = false,
    this.targetLocationShared = false,
    this.showBattery = true,
    this.locationFocusRequest = 0,
    this.mapVisible = true,
    this.offlineMapStore = const MapLibreNearbyOfflineMapStore(),
    super.key,
  });

  final List<RelioDevice> peers;
  final LocationData? myLocation;
  final String? navigationTargetId;
  final ValueChanged<String> onPeerSelected;
  final LocationData? targetLocationOverride;
  final bool targetLocationHistorical;
  final bool targetLocationShared;
  final bool showBattery;
  final int locationFocusRequest;
  final bool mapVisible;
  final NearbyOfflineMapStore offlineMapStore;

  @override
  State<NearbyMapCanvas> createState() => _NearbyMapCanvasState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Nearby Map Canvas State)
class _NearbyMapCanvasState extends State<NearbyMapCanvas>
    with WidgetsBindingObserver {
  static const _styleUrl = String.fromEnvironment(
    'RELIO_MAP_STYLE_URL',
    defaultValue: 'assets/maps/style.json',
  );

  static CameraPosition? _savedUserViewport;

  final Map<String, Circle> _circles = {};
  final Map<String, Symbol> _symbols = {};
  final Map<String, Line> _lines = {};
  final _reconciliation = NearbyMarkerReconciliation();
  final _headingFilter = NearbyHeadingFilter();

  Future<void> _circle(
    String id,
    CircleOptions options, [
    Map<String, dynamic>? data,
  ]) async {
    final encoded = jsonEncode(options.toJson());
    if (!_reconciliation.needsUpdate(id, encoded)) return;
    final current = _circles[id];
    if (current == null) {
      _circles[id] = await _controller!.addCircle(options, data);
    } else {
      await _controller!.updateCircle(current, options);
    }
    _reconciliation.applied(id, encoded);
  }

  Future<void> _symbol(
    String id,
    SymbolOptions options, [
    Map<String, dynamic>? data,
  ]) async {
    final encoded = jsonEncode(options.toJson());
    if (!_reconciliation.needsUpdate(id, encoded)) return;
    final current = _symbols[id];
    if (current == null) {
      _symbols[id] = await _controller!.addSymbol(options, data);
    } else {
      await _controller!.updateSymbol(current, options);
    }
    _reconciliation.applied(id, encoded);
  }

  Future<void> _line(String id, LineOptions options) async {
    final encoded = jsonEncode(options.toJson());
    if (!_reconciliation.needsUpdate(id, encoded)) return;
    final current = _lines[id];
    if (current == null) {
      _lines[id] = await _controller!.addLine(options);
    } else {
      await _controller!.updateLine(current, options);
    }
    _reconciliation.applied(id, encoded);
  }

  Future<void> _removeMissing() async {
    for (final id in _reconciliation.missingIds) {
      final circle = _circles.remove(id);
      final symbol = _symbols.remove(id);
      final line = _lines.remove(id);
      if (circle != null) await _controller!.removeCircle(circle);
      if (symbol != null) await _controller!.removeSymbol(symbol);
      if (line != null) await _controller!.removeLine(line);
      _reconciliation.forget(id);
    }
  }

  String? _preparedStyle;
  bool _preparing = false;
  MapLibreMapController? _controller;
  Timer? _loadWatchdog;
  Timer? _headingExpiryTimer;
  Future<void>? _headingCancellation;
  bool _headingCancelWatcherScheduled = false;
  bool _headingRestartAfterCancel = false;
  bool _styleLoaded = false;
  bool _unavailable = false;
  bool _markersBusy = false;
  bool _refreshPending = false;
  bool _cameraManuallyMoved = false;
  bool _initialCameraFocused = false;
  final Map<int, Offset> _pointerOrigins = {};
  double? _headingDegrees;
  NearbyHeadingConfidence _headingConfidence =
      NearbyHeadingConfidence.provisional;
  StreamSubscription<CompassEvent>? _headingSubscription;
  String? _cameraTargetId;
  int _mapAttempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialCameraFocused = _savedUserViewport != null;
    if (widget.mapVisible) unawaited(_prepareStyle());
    _syncHeadingSubscription();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHeadingSubscription();
    });
  }

  @override
  void didUpdateWidget(covariant NearbyMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_styleLoaded &&
        (!_samePeers(oldWidget.peers, widget.peers) ||
            oldWidget.myLocation != widget.myLocation ||
            oldWidget.targetLocationOverride != widget.targetLocationOverride ||
            oldWidget.targetLocationHistorical !=
                widget.targetLocationHistorical ||
            oldWidget.targetLocationShared != widget.targetLocationShared ||
            oldWidget.showBattery != widget.showBattery ||
            oldWidget.navigationTargetId != widget.navigationTargetId)) {
      unawaited(_refreshMarkers());
    }
    if (oldWidget.locationFocusRequest != widget.locationFocusRequest) {
      unawaited(_focusMyLocation());
    }
    if (oldWidget.navigationTargetId != widget.navigationTargetId ||
        oldWidget.targetLocationOverride != widget.targetLocationOverride ||
        oldWidget.targetLocationShared != widget.targetLocationShared) {
      _cameraTargetId = null;
    }
    if (widget.mapVisible && _preparedStyle == null) unawaited(_prepareStyle());
    if (oldWidget.mapVisible != widget.mapVisible) {
      _syncHeadingSubscription();
    }
  }

  Future<void> _prepareStyle() async {
    if (_preparing || !(Platform.isAndroid || Platform.isIOS)) return;
    _preparing = true;
    try {
      final style = _styleUrl == 'assets/maps/style.json'
          ? await PackagedMapService.prepare()
          : _styleUrl;
      if (mounted) setState(() => _preparedStyle = style);
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    } finally {
      _preparing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncHeadingSubscription();
  }

  void _syncHeadingSubscription() {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    // Flutter can briefly report null before delivering its first resumed event.
    final shouldListen =
        widget.mapVisible &&
        (lifecycleState == null || lifecycleState == AppLifecycleState.resumed);
    if (!shouldListen) {
      final active = _headingSubscription;
      if (active != null) {
        _headingSubscription = null;
        _headingCancellation = active.cancel();
      }
      _headingRestartAfterCancel = false;
      _headingExpiryTimer?.cancel();
      _headingExpiryTimer = null;
      _headingFilter.clear();
      if (_headingDegrees != null ||
          _headingConfidence != NearbyHeadingConfidence.provisional) {
        _headingDegrees = null;
        _headingConfidence = NearbyHeadingConfidence.provisional;
        unawaited(_refreshMarkers());
      }
      return;
    }
    if (_headingSubscription != null) return;
    final cancelling = _headingCancellation;
    if (cancelling != null) {
      _headingRestartAfterCancel = true;
      if (!_headingCancelWatcherScheduled) {
        _headingCancelWatcherScheduled = true;
        unawaited(
          cancelling.whenComplete(() {
            _headingCancellation = null;
            _headingCancelWatcherScheduled = false;
            if (!mounted) return;
            if (_headingRestartAfterCancel) {
              _headingRestartAfterCancel = false;
              _syncHeadingSubscription();
            }
          }),
        );
      }
      return;
    }
    final events = FlutterCompass.events;
    if (events == null) return;
    _headingSubscription = events.listen(
      (event) {
        final now = DateTime.now();
        final heading = _headingFilter.update(
          event.heading,
          accuracyDegrees: event.accuracy,
          now: now,
        );
        if (heading != null) {
          _scheduleHeadingExpiry();
        }
        _setHeading(heading);
      },
      onError: (Object _) {
        _setHeading(_headingFilter.expire(DateTime.now()));
      },
    );
  }

  void _scheduleHeadingExpiry() {
    _headingExpiryTimer?.cancel();
    _headingExpiryTimer = Timer(NearbyHeadingFilter.staleAfter, () {
      _setHeading(_headingFilter.expire(DateTime.now()));
    });
  }

  void _setHeading(double? heading) {
    if (!mounted) return;
    final previous = _headingDegrees;
    final confidence = _headingFilter.confidence;
    if ((previous == heading && _headingConfidence == confidence) ||
        (previous != null &&
            heading != null &&
            (previous - heading).abs() < 0.5 &&
            _headingConfidence == confidence)) {
      return;
    }
    // อัปเดตเฉพาะ symbol บน MapLibre ไม่ rebuild แผนที่ทั้งชั้นตาม sensor
    _headingDegrees = heading;
    _headingConfidence = confidence;
    unawaited(_refreshMarkers());
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
    _circles.clear();
    _symbols.clear();
    _lines.clear();
    _reconciliation.reset();
    setState(() {
      _styleLoaded = true;
      _unavailable = false;
    });
    unawaited(_configureAnnotationFont());
  }

  Future<void> _configureAnnotationFont() async {
    final controller = _controller;
    final manager = controller?.symbolManager;
    if (controller == null || manager == null) return;
    try {
      // SymbolManager ใช้ font คงที่ จึงต้องเปลี่ยน layer ให้ตรงกับ glyph ที่แพ็กไว้
      for (var i = 0; i < manager.layerIds.length; i++) {
        final properties =
            manager.allLayerProperties[i] as SymbolLayerProperties;
        await controller.setLayerProperties(
          manager.layerIds[i],
          properties.copyWith(const SymbolLayerProperties(textFont: ['noto'])),
        );
      }
      await _refreshMarkers();
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerOrigins[event.pointer] = event.position;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final origin = _pointerOrigins[event.pointer];
    if (_controller != null &&
        origin != null &&
        (event.position - origin).distance > 10) {
      _cameraManuallyMoved = true;
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _pointerOrigins.remove(event.pointer);
  }

  Future<void> _animateTo(LatLng target, {double zoom = 12}) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    } on Object {
      // Camera animation can be interrupted when the map route is removed.
    }
  }

  Future<void> _focusMyLocation() async {
    final location = widget.myLocation;
    if (location == null ||
        !NearbyMapCalculations.isValidPoint(
          location.latitude,
          location.longitude,
        )) {
      return;
    }
    if (_controller == null || !_styleLoaded) return;
    final camera = CameraPosition(
      target: LatLng(location.latitude, location.longitude),
      zoom: 12,
    );
    await _animateTo(camera.target, zoom: camera.zoom);
    _savedUserViewport = camera;
    _initialCameraFocused = true;
  }

  void _onCircleTapped(Circle circle) {
    final markerId = circle.data?['markerId'];
    final deviceId = circle.data?['deviceId'];
    final id = markerId is String
        ? markerId
        : deviceId is String
        ? deviceId
        : null;
    if (id != null) unawaited(_handleMarkerTap(id));
  }

  void _onSymbolTapped(Symbol symbol) {
    final deviceId = symbol.data?['deviceId'];
    if (deviceId is String) unawaited(_handleMarkerTap(deviceId));
  }

  Future<void> _handleMarkerTap(String tappedMarkerId) async {
    final controller = _controller;
    if (controller == null) return;

    final ids = <String>[];
    final points = <LatLng>[];
    final self = widget.myLocation;
    if (self != null &&
        NearbyMapCalculations.isValidPoint(self.latitude, self.longitude)) {
      ids.add('self');
      points.add(LatLng(self.latitude, self.longitude));
    }
    final peers = <String, RelioDevice>{};
    for (final peer in widget.peers) {
      if (!NearbyMapCalculations.isValidPoint(
        peer.locationLatitude,
        peer.locationLongitude,
      )) {
        continue;
      }
      ids.add(peer.id);
      points.add(LatLng(peer.locationLatitude!, peer.locationLongitude!));
      peers[peer.id] = peer;
    }
    if (!ids.contains(tappedMarkerId)) return;

    try {
      final projected = await controller.toScreenLocationBatch(points);
      if (!mounted || projected.length != ids.length) return;
      final nearbyIds = nearbyMapMarkerIdsAtPoint([
        for (var index = 0; index < ids.length; index++)
          NearbyMapMarkerHit(
            id: ids[index],
            screenPoint: Offset(
              projected[index].x.toDouble(),
              projected[index].y.toDouble(),
            ),
          ),
      ], tappedMarkerId);
      if (nearbyIds.length < 2) {
        if (tappedMarkerId != 'self') widget.onPeerSelected(tappedMarkerId);
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'เลือกอุปกรณ์ที่อยู่ใกล้กัน',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final id in nearbyIds)
                        ListTile(
                          leading: Icon(
                            id == 'self' ? Icons.my_location : Icons.person,
                            color: id == 'self'
                                ? RelioColors.mapSelf
                                : nearbyMapStatusColor(peers[id]!.status),
                          ),
                          title: Text(
                            id == 'self' ? 'ตำแหน่งของฉัน' : peers[id]!.name,
                          ),
                          subtitle: id == 'self'
                              ? null
                              : Text('ตำแหน่งล่าสุดของอุปกรณ์'),
                          onTap: () {
                            Navigator.of(context).pop();
                            if (id != 'self') widget.onPeerSelected(id);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } on Object {
      if (mounted && tappedMarkerId != 'self') {
        widget.onPeerSelected(tappedMarkerId);
      }
    }
  }

  Future<void> _refreshMarkers() async {
    final controller = _controller;
    if (controller == null || !_styleLoaded) return;
    if (_markersBusy) {
      _refreshPending = true;
      return;
    }
    _markersBusy = true;
    try {
      // คง annotation เดิมไว้และแก้เฉพาะข้อมูลที่เปลี่ยน เพื่อไม่ให้เข็มทิศทำ peer กระพริบ
      _reconciliation.begin();

      final myLocation = widget.myLocation;
      if (myLocation != null &&
          NearbyMapCalculations.isValidPoint(
            myLocation.latitude,
            myLocation.longitude,
          )) {
        final selfAccuracyIsLow =
            NearbyLocationQuality.confidence(myLocation.accuracyMeters) ==
            LocationConfidence.low;
        await _circle(
          'self-circle',
          CircleOptions(
            geometry: LatLng(myLocation.latitude, myLocation.longitude),
            circleRadius: _nearbySelfMarkerRadius,
            circleColor: _hex(RelioColors.mapSelf),
            circleOpacity: 0.72,
            circleStrokeWidth: _nearbySelfMarkerStroke,
            circleStrokeColor: selfAccuracyIsLow
                ? _hex(RelioColors.warning)
                : '#FFFFFF',
          ),
          const {'markerId': 'self'},
        );
        final heading = _headingDegrees;
        if (heading != null) {
          await _symbol(
            'self-heading',
            SymbolOptions(
              fontNames: const ['noto'],
              geometry: LatLng(myLocation.latitude, myLocation.longitude),
              textField: '▲',
              textSize: 18,
              textRotate: heading,
              zIndex: 100,
              textColor: _hex(
                _headingConfidence == NearbyHeadingConfidence.reliable
                    ? RelioColors.mapSelfHeading
                    : RelioColors.warning,
              ),
              textHaloColor: '#FFFFFF',
              textHaloWidth: 2.5,
            ),
          );
        }
        await _symbol(
          'self-label',
          SymbolOptions(
            fontNames: const ['noto'],
            geometry: LatLng(myLocation.latitude, myLocation.longitude),
            textField: selfAccuracyIsLow
                ? 'ตำแหน่งเรา • ±${myLocation.accuracyMeters!.round()} ม.'
                : 'ตำแหน่งเรา',
            textSize: 12,
            textColor: _hex(RelioColors.mapSelf),
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2,
            textOffset: const Offset(0, 1.5),
          ),
        );
      }

      RelioDevice? navigationTarget;
      for (final peer in widget.peers) {
        if (widget.targetLocationOverride != null &&
            peer.id == widget.navigationTargetId) {
          continue;
        }
        if (!NearbyMapCalculations.isValidPoint(
          peer.locationLatitude,
          peer.locationLongitude,
        )) {
          continue;
        }
        final color = _hex(nearbyMapStatusColor(peer.status));
        final locationIsFresh =
            NearbyMapCalculations.isFreshLocation(
              peer.locationCapturedAt,
              DateTime.now(),
            ) &&
            NearbyLocationQuality.confidence(peer.locationAccuracyMeters) !=
                LocationConfidence.low;
        final point = LatLng(peer.locationLatitude!, peer.locationLongitude!);
        final selected = peer.id == widget.navigationTargetId;
        await _circle(
          'peer-circle:${peer.id}',
          CircleOptions(
            geometry: point,
            circleRadius: selected
                ? 12
                : peer.status == DeviceStatus.sos
                ? 10
                : 8,
            circleColor: color,
            circleStrokeWidth: selected ? 5 : 3,
            circleStrokeColor: _hex(
              nearbyPeerMarkerStrokeColor(
                selected: selected,
                fresh: locationIsFresh,
              ),
            ),
          ),
          {'deviceId': peer.id},
        );
        final battery =
            !selected || !widget.showBattery || peer.batteryLevel == null
            ? ''
            : ' · ${peer.isCharging == true ? '⚡' : '🔋'} ${peer.batteryLevel}%';
        await _symbol(
          'peer-label:${peer.id}',
          SymbolOptions(
            fontNames: const ['noto'],
            geometry: point,
            textField: '${_compactName(peer.name)}$battery',
            textSize: selected ? 12 : 10,
            textColor: color,
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2,
            textOffset: const Offset(0, 1.7),
          ),
          {'deviceId': peer.id},
        );
        if (peer.id == widget.navigationTargetId) navigationTarget = peer;
      }

      final savedTarget = widget.targetLocationOverride;
      if (savedTarget != null &&
          NearbyMapCalculations.isValidPoint(
            savedTarget.latitude,
            savedTarget.longitude,
          )) {
        final point = LatLng(savedTarget.latitude, savedTarget.longitude);
        await _circle(
          'selected-location-circle',
          CircleOptions(
            geometry: point,
            circleRadius: 14,
            circleColor: _hex(
              nearbyTargetLocationColor(shared: widget.targetLocationShared),
            ),
            circleStrokeWidth: 4,
            circleStrokeColor: '#FFFFFF',
          ),
        );
        await _symbol(
          'selected-location-label',
          SymbolOptions(
            fontNames: const ['noto'],
            geometry: point,
            textField: nearbyTargetLocationLabel(
              shared: widget.targetLocationShared,
              historical: widget.targetLocationHistorical,
            ),
            textSize: 12,
            textColor: _hex(
              widget.targetLocationShared
                  ? RelioColors.primaryDark
                  : RelioColors.sosStrong,
            ),
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2.5,
            textOffset: const Offset(0, 1.7),
            zIndex: 120,
          ),
        );
      }

      final routeTarget = savedTarget != null
          ? LatLng(savedTarget.latitude, savedTarget.longitude)
          : navigationTarget == null
          ? null
          : LatLng(
              navigationTarget.locationLatitude!,
              navigationTarget.locationLongitude!,
            );
      if (myLocation != null && routeTarget != null) {
        await _line(
          'route',
          LineOptions(
            geometry: [
              LatLng(myLocation.latitude, myLocation.longitude),
              routeTarget,
            ],
            lineColor: _hex(RelioColors.primaryDark),
            lineWidth: 3,
            lineOpacity: 0.85,
          ),
        );
      }
      await _removeMissing();
      if (savedTarget != null &&
          NearbyMapCalculations.isValidPoint(
            savedTarget.latitude,
            savedTarget.longitude,
          ) &&
          _cameraTargetId != 'selected-location') {
        final point = LatLng(savedTarget.latitude, savedTarget.longitude);
        await _animateTo(point, zoom: 14);
        _savedUserViewport = CameraPosition(target: point, zoom: 14);
        _cameraTargetId = 'selected-location';
        _initialCameraFocused = true;
      } else if (navigationTarget != null &&
          _cameraTargetId != navigationTarget.id) {
        await _animateTo(
          LatLng(
            navigationTarget.locationLatitude!,
            navigationTarget.locationLongitude!,
          ),
          zoom: 12,
        );
        _savedUserViewport = CameraPosition(
          target: LatLng(
            navigationTarget.locationLatitude!,
            navigationTarget.locationLongitude!,
          ),
          zoom: 12,
        );
        _cameraTargetId = navigationTarget.id;
        _initialCameraFocused = true;
      } else if (!_initialCameraFocused && !_cameraManuallyMoved) {
        final local = widget.myLocation;
        if (local != null &&
            NearbyMapCalculations.isValidPoint(
              local.latitude,
              local.longitude,
            ) &&
            NearbyMapCalculations.isFreshLocation(
              local.capturedAt,
              DateTime.now(),
            )) {
          await _animateTo(LatLng(local.latitude, local.longitude));
          if (widget.locationFocusRequest > 0) {
            _savedUserViewport = CameraPosition(
              target: LatLng(local.latitude, local.longitude),
              zoom: 12,
            );
          }
          _initialCameraFocused = true;
        }
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

  String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  String _compactName(String name) {
    final compact = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 24 ? compact : '${compact.substring(0, 23)}…';
  }

  void _retry() {
    _loadWatchdog?.cancel();
    _headingExpiryTimer?.cancel();
    unawaited(_prepareStyle());
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
    _headingExpiryTimer?.cancel();
    final controller = _controller;
    if (controller != null) {
      controller.onCircleTapped.remove(_onCircleTapped);
      controller.onSymbolTapped.remove(_onSymbolTapped);
    }
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_headingSubscription?.cancel());
    _headingSubscription = null;
    _pointerOrigins.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if ((Platform.isAndroid || Platform.isIOS) && _preparedStyle != null)
          Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerEnd,
            onPointerCancel: _onPointerEnd,
            child: MapLibreMap(
              key: ValueKey(_mapAttempt),
              styleString: _preparedStyle!,
              minMaxZoomPreference: const MinMaxZoomPreference(
                null,
                nearbyMapCameraMaxZoom,
              ),
              annotationOrder: const [
                AnnotationType.line,
                AnnotationType.circle,
                AnnotationType.symbol,
              ],
              initialCameraPosition: nearbyInitialCameraPosition(
                savedViewport: widget.targetLocationOverride == null
                    ? _savedUserViewport
                    : CameraPosition(
                        target: LatLng(
                          widget.targetLocationOverride!.latitude,
                          widget.targetLocationOverride!.longitude,
                        ),
                        zoom: 14,
                      ),
                selfLocation: widget.targetLocationOverride == null
                    ? widget.myLocation
                    : null,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded,
              trackCameraPosition: true,
              onCameraIdle: () {
                if (_cameraManuallyMoved) {
                  _savedUserViewport = _controller?.cameraPosition;
                }
              },
              compassEnabled: false,
              logoEnabled: false,
              attributionButtonPosition: nearbyMapAttributionPosition,
              attributionButtonMargins: nearbyMapAttributionMargins,
              attributionButtonColor: colors.onSurface,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
            ),
          )
        else
          ColoredBox(color: colors.surfaceContainerLow),
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
