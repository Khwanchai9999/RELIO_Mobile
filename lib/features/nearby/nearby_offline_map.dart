// โมเดลและหน้าจัดการแผนที่ออฟไลน์ Nearby ตามขีดจำกัดจำนวน tile และขนาดที่แอปกำหนด
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

const nearbyOfflineMapDiameterMeters = 5000.0;
const nearbyOfflineMapMaxTiles = 3000;
const nearbyOfflineMapMaxBytes = 50 * 1024 * 1024;
const nearbyOfflineMapMinZoom = 10.0;
const nearbyOfflineMapMaxZoom = 15.0;

// โมเดลแผนและความคืบหน้าของ offline map; ไม่ได้เป็นตัวเริ่มดาวน์โหลดโดยอัตโนมัติ
// การบันทึกพื้นที่ต้องผ่านการยืนยันและข้อจำกัด provider ที่แอปกำหนด
class NearbyOfflineMapPlan {
  const NearbyOfflineMapPlan({required this.bounds});

  final ml.LatLngBounds bounds;

  static NearbyOfflineMapPlan? around(ml.LatLng center) {
    if (!center.latitude.isFinite ||
        !center.longitude.isFinite ||
        center.latitude.abs() > 85 ||
        center.longitude < -180 ||
        center.longitude > 180) {
      return null;
    }
    const halfSideMeters = nearbyOfflineMapDiameterMeters / 2;
    const metersPerLatitudeDegree = 111320.0;
    final latitudeDelta = halfSideMeters / metersPerLatitudeDegree;
    final longitudeScale = math.cos(center.latitude * math.pi / 180);
    if (longitudeScale.abs() < 0.01) return null;
    final longitudeDelta =
        halfSideMeters / (metersPerLatitudeDegree * longitudeScale.abs());
    final south = (center.latitude - latitudeDelta).clamp(-85.0, 85.0);
    final north = (center.latitude + latitudeDelta).clamp(-85.0, 85.0);
    final west = (center.longitude - longitudeDelta).clamp(-180.0, 180.0);
    final east = (center.longitude + longitudeDelta).clamp(-180.0, 180.0);
    return NearbyOfflineMapPlan(
      bounds: ml.LatLngBounds(
        southwest: ml.LatLng(south, west),
        northeast: ml.LatLng(north, east),
      ),
    );
  }
}

bool supportsNearbyOfflineStyle(String styleUrl) {
  final uri = Uri.tryParse(styleUrl);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'tiles.openfreemap.org' &&
      (uri.port == 443 || uri.hasPort == false) &&
      uri.userInfo.isEmpty &&
      uri.path.startsWith('/styles/');
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Nearby Offline Map Progress
class NearbyOfflineMapProgress {
  const NearbyOfflineMapProgress({
    this.fraction,
    this.completedResources = 0,
    this.requiredResources = 0,
    this.completedBytes = 0,
    this.complete = false,
    this.failed = false,
  });

  final double? fraction;
  final int completedResources;
  final int requiredResources;
  final int completedBytes;
  final bool complete;
  final bool failed;
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Nearby Offline Map Region
class NearbyOfflineMapRegion {
  const NearbyOfflineMapRegion({
    required this.id,
    required this.name,
    required this.complete,
    required this.progress,
    required this.sizeBytes,
  });

  final int id;
  final String name;
  final bool complete;
  final double progress;
  final int sizeBytes;
}

abstract interface class NearbyOfflineMapStore {
  Future<List<NearbyOfflineMapRegion>> listRegions();

  Future<NearbyOfflineMapRegion> download({
    required String styleUrl,
    required NearbyOfflineMapPlan plan,
    required ValueChanged<NearbyOfflineMapProgress> onProgress,
  });

  Future<void> deleteRegion(int id);
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Map Libre Nearby Offline Map Store
class MapLibreNearbyOfflineMapStore implements NearbyOfflineMapStore {
  const MapLibreNearbyOfflineMapStore();

  static const _userAgent = 'RELIO-Mobile/0.9.0 (Android; Nearby offline map)';

  @override
  Future<List<NearbyOfflineMapRegion>> listRegions() async {
    final regions = await ml.getListOfRegions();
    final saved = <NearbyOfflineMapRegion>[];
    for (final region in regions.where(
      (region) => region.metadata['relioOfflineMap'] == true,
    )) {
      final rawName = region.metadata['name'];
      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName
          : 'แผนที่ Nearby';
      try {
        final status = await ml.getOfflineRegionStatus(region.id);
        saved.add(
          NearbyOfflineMapRegion(
            id: region.id,
            name: name,
            complete: status.isComplete,
            progress: status.downloadProgress,
            sizeBytes: status.completedResourceSize,
          ),
        );
      } on Object {
        saved.add(
          NearbyOfflineMapRegion(
            id: region.id,
            name: name,
            complete: false,
            progress: 0,
            sizeBytes: 0,
          ),
        );
      }
    }
    return saved;
  }

  @override
  Future<NearbyOfflineMapRegion> download({
    required String styleUrl,
    required NearbyOfflineMapPlan plan,
    required ValueChanged<NearbyOfflineMapProgress> onProgress,
  }) async {
    if (!supportsNearbyOfflineStyle(styleUrl)) {
      throw const NearbyOfflineMapException();
    }

    await ml.setHttpHeaders({'User-Agent': _userAgent});
    await ml.setOfflineTileCountLimit(nearbyOfflineMapMaxTiles);
    await ml.setOfflineMaxConcurrentRequests(
      maxRequests: 4,
      maxRequestsPerHost: 4,
    );

    final terminal = Completer<NearbyOfflineMapProgress>();
    var exceededLimit = false;
    final region = await ml.downloadOfflineRegion(
      ml.OfflineRegionDefinition(
        bounds: plan.bounds,
        mapStyleUrl: styleUrl,
        minZoom: nearbyOfflineMapMinZoom,
        maxZoom: nearbyOfflineMapMaxZoom,
      ),
      metadata: {
        'relioOfflineMap': true,
        'name': 'แผนที่ Nearby รอบนี้',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
      onEvent: (event) {
        if (event is ml.InProgress) {
          final overLimit =
              event.completedResourceCount > nearbyOfflineMapMaxTiles ||
              event.requiredResourceCount > nearbyOfflineMapMaxTiles ||
              event.completedResourceSize > nearbyOfflineMapMaxBytes;
          if (overLimit) {
            exceededLimit = true;
            final progress = const NearbyOfflineMapProgress(failed: true);
            onProgress(progress);
            if (!terminal.isCompleted) terminal.complete(progress);
            return;
          }
          final progress = NearbyOfflineMapProgress(
            fraction: event.progress,
            completedResources: event.completedResourceCount,
            requiredResources: event.requiredResourceCount,
            completedBytes: event.completedResourceSize,
          );
          onProgress(progress);
        } else if (event is ml.Success) {
          final progress = const NearbyOfflineMapProgress(
            fraction: 1,
            complete: true,
          );
          onProgress(progress);
          if (!terminal.isCompleted) terminal.complete(progress);
        } else if (event is ml.Error) {
          const progress = NearbyOfflineMapProgress(failed: true);
          onProgress(progress);
          if (!terminal.isCompleted) terminal.complete(progress);
        }
      },
    );

    try {
      final result = await terminal.future.timeout(const Duration(minutes: 20));
      if (result.failed || exceededLimit) {
        await ml.pauseOfflineRegionDownload(region.id);
        await ml.deleteOfflineRegion(region.id);
        throw const NearbyOfflineMapException();
      }
      final status = await ml.getOfflineRegionStatus(region.id);
      if (status.completedResourceCount > nearbyOfflineMapMaxTiles ||
          status.completedResourceSize > nearbyOfflineMapMaxBytes) {
        await ml.deleteOfflineRegion(region.id);
        throw const NearbyOfflineMapException();
      }
      return NearbyOfflineMapRegion(
        id: region.id,
        name: 'แผนที่ Nearby รอบนี้',
        complete: status.isComplete,
        progress: status.downloadProgress,
        sizeBytes: status.completedResourceSize,
      );
    } on TimeoutException {
      await ml.pauseOfflineRegionDownload(region.id);
      await ml.deleteOfflineRegion(region.id);
      throw const NearbyOfflineMapException();
    }
  }

  @override
  Future<void> deleteRegion(int id) async {
    final regions = await ml.getListOfRegions();
    final selected = regions.where((region) => region.id == id).firstOrNull;
    if (selected?.metadata['relioOfflineMap'] != true) return;
    await ml.deleteOfflineRegion(id);
  }
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Nearby Offline Map Exception
class NearbyOfflineMapException implements Exception {
  const NearbyOfflineMapException();
}

Future<void> showNearbyOfflineMapManager({
  required BuildContext context,
  required ml.LatLng? center,
  required String styleUrl,
  NearbyOfflineMapStore store = const MapLibreNearbyOfflineMapStore(),
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) =>
      NearbyOfflineMapManager(center: center, styleUrl: styleUrl, store: store),
);

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Nearby Offline Map Manager
class NearbyOfflineMapManager extends StatefulWidget {
  const NearbyOfflineMapManager({
    required this.center,
    required this.styleUrl,
    required this.store,
    super.key,
  });

  final ml.LatLng? center;
  final String styleUrl;
  final NearbyOfflineMapStore store;

  @override
  State<NearbyOfflineMapManager> createState() =>
      _NearbyOfflineMapManagerState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Nearby Offline Map Manager State)
class _NearbyOfflineMapManagerState extends State<NearbyOfflineMapManager> {
  List<NearbyOfflineMapRegion> _regions = const [];
  NearbyOfflineMapProgress? _progress;
  bool _loading = true;
  bool _downloading = false;
  String? _message;

  bool get _providerAllowed => supportsNearbyOfflineStyle(widget.styleUrl);
  NearbyOfflineMapPlan? get _plan => widget.center == null
      ? null
      : NearbyOfflineMapPlan.around(widget.center!);

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final regions = await widget.store.listRegions();
      if (mounted) setState(() => _regions = regions);
    } on Object {
      if (mounted) setState(() => _message = 'อ่านรายการแผนที่ที่บันทึกไม่ได้');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final plan = _plan;
    if (plan == null || !_providerAllowed || _downloading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ดาวน์โหลดแผนที่ออฟไลน์?'),
        content: const Text(
          'บันทึกพื้นที่ประมาณ 5 กม. รอบจุดกึ่งกลางแผนที่ '
          'ใช้ข้อมูลเครือข่ายและพื้นที่จัดเก็บ โดยจำกัดไม่เกิน 3,000 tiles หรือ 50 MB',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ดาวน์โหลด'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _downloading = true;
      _progress = const NearbyOfflineMapProgress();
      _message = null;
    });
    try {
      await widget.store.download(
        styleUrl: widget.styleUrl,
        plan: plan,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) {
        setState(() => _message = 'ดาวน์โหลดแผนที่ออฟไลน์แล้ว');
      }
      await _reload();
    } on Object {
      if (mounted) {
        setState(() => _message = 'ดาวน์โหลดไม่สำเร็จ หรือเกินขีดจำกัด');
      }
      await _reload();
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _delete(NearbyOfflineMapRegion region) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบแผนที่ออฟไลน์นี้?'),
        content: Text('ลบ “${region.name}” ที่บันทึกไว้ในเครื่องนี้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบแผนที่'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.deleteRegion(region.id);
      if (mounted) setState(() => _message = 'ลบแผนที่ที่เลือกแล้ว');
      await _reload();
    } on Object {
      if (mounted) setState(() => _message = 'ลบแผนที่ไม่สำเร็จ');
    }
  }

  String _sizeLabel(int bytes) =>
      bytes <= 0 ? '' : ' • ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'แผนที่ออฟไลน์',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'บันทึกบริเวณรอบจุดกึ่งกลางแผนที่ไว้ดู Nearby โดยไม่ใช้อินเทอร์เน็ต',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (!_providerAllowed)
                Text(
                  'แหล่งแผนที่นี้ยังไม่รองรับการดาวน์โหลดออฟไลน์ตามนโยบายที่ตรวจสอบไว้',
                  style: TextStyle(color: colors.error),
                )
              else if (_plan == null)
                Text(
                  'ยังใช้จุดกึ่งกลางแผนที่ไม่ได้ เลื่อนแผนที่ไปยังบริเวณที่ต้องการก่อน',
                  style: TextStyle(color: colors.error),
                ),
              FilledButton.icon(
                onPressed: !_providerAllowed || _plan == null || _downloading
                    ? null
                    : _download,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('ดาวน์โหลดบริเวณนี้ · 5 กม.'),
              ),
              if (_downloading && _progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress!.fraction),
                const SizedBox(height: 6),
                Text(
                  _progress!.failed
                      ? 'เกินขีดจำกัดที่อนุญาต กำลังยกเลิกพื้นที่นี้'
                      : _progress!.complete
                      ? 'บันทึกแผนที่แล้ว'
                      : 'กำลังดาวน์โหลด ${(_progress!.fraction ?? 0) * 100 ~/ 1}%'
                            '${_progress!.requiredResources > 0 ? ' · ${_progress!.completedResources}/${_progress!.requiredResources} รายการ' : ''}',
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!),
              ],
              const Divider(height: 24),
              Text(
                'พื้นที่ที่บันทึกไว้',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_regions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('ยังไม่มีแผนที่ออฟไลน์'),
                )
              else
                ..._regions.map(
                  (region) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      region.complete ? Icons.offline_pin : Icons.downloading,
                      color: region.complete ? colors.primary : colors.tertiary,
                    ),
                    title: Text(region.name),
                    subtitle: Text(
                      '${region.complete ? 'พร้อมใช้งานออฟไลน์' : '${(region.progress * 100).round()}%'}'
                      '${_sizeLabel(region.sizeBytes)}',
                    ),
                    trailing: IconButton(
                      tooltip: 'ลบ ${region.name}',
                      onPressed: _downloading ? null : () => _delete(region),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
