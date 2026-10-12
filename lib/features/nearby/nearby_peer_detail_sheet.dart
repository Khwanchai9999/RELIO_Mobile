import 'package:flutter/material.dart';

import '../../core/domain/relio_entities.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../data/models/prototype_models.dart';

Future<void> showNearbyPeerDetailSheet({
  required BuildContext context,
  required RelioDevice device,
  required LocationData? myLocation,
  required VoidCallback onChat,
  required VoidCallback onNavigate,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => SafeArea(
    top: false,
    bottom: true,
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.66,
      minChildSize: 0.42,
      maxChildSize: 0.96,
      snap: true,
      snapSizes: const [0.66, 0.96],
      builder: (context, scrollController) => _PeerDetailSheet(
        device: device,
        myLocation: myLocation,
        scrollController: scrollController,
        onChat: () {
          Navigator.of(sheetContext).pop();
          onChat();
        },
        onNavigate: () {
          Navigator.of(sheetContext).pop();
          onNavigate();
        },
      ),
    ),
  ),
);

class _PeerDetailSheet extends StatelessWidget {
  const _PeerDetailSheet({
    required this.device,
    required this.myLocation,
    required this.scrollController,
    required this.onChat,
    required this.onNavigate,
  });

  final RelioDevice device;
  final LocationData? myLocation;
  final ScrollController scrollController;
  final VoidCallback onChat;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final distance = NearbyMapCalculations.distanceMeters(
      fromLatitude: myLocation?.latitude,
      fromLongitude: myLocation?.longitude,
      toLatitude: device.locationLatitude,
      toLongitude: device.locationLongitude,
    );
    final bearing = NearbyMapCalculations.bearingDegrees(
      fromLatitude: myLocation?.latitude,
      fromLongitude: myLocation?.longitude,
      toLatitude: device.locationLatitude,
      toLongitude: device.locationLongitude,
    );
    final hasLocation = NearbyMapCalculations.isValidPoint(
      device.locationLatitude,
      device.locationLongitude,
    );
    final staleLocation =
        hasLocation &&
        NearbyMapCalculations.freshness(
              device.locationCapturedAt ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              now,
            ) !=
            LocationFreshness.fresh;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            device.name,
            style: Theme.of(context).textTheme.titleLarge,
            softWrap: true,
          ),
          if (device.peerDeviceModel?.isNotEmpty == true)
            Text(
              device.peerDeviceModel!,
              style: Theme.of(context).textTheme.bodyMedium,
              softWrap: true,
            ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.circle, color: device.status.color),
            title: Text('สถานะ ${device.status.label}'),
            subtitle: Text(
              device.isConnected
                  ? 'เชื่อมต่อ Nearby'
                  : 'ไม่ได้เชื่อมต่อ Nearby',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.battery_std_rounded),
            title: Text(
              device.batteryLevel == null
                  ? 'แบตเตอรี่ไม่ทราบ'
                  : 'แบตเตอรี่ ${device.batteryLevel}%${device.isCharging == true ? ' • กำลังชาร์จ' : ''}',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on_outlined),
            title: Text(hasLocation ? 'ตำแหน่ง peer' : 'ยังไม่มีตำแหน่ง peer'),
            subtitle: Text(
              hasLocation
                  ? '${NearbyMapCalculations.freshnessLabel(device.locationCapturedAt, now)} • ${NearbyMapCalculations.distanceLabel(distance)} • ${NearbyMapCalculations.bearingLabel(bearing)}'
                  : 'peer ต้องแชร์ตำแหน่งด้วยตนเองก่อน',
            ),
          ),
          if (staleLocation)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('ตำแหน่งเก่าอาจไม่ตรงกับตำแหน่งปัจจุบัน'),
            ),
          _PeerDetailActions(
            device: device,
            hasLocation: hasLocation,
            onChat: onChat,
            onNavigate: onNavigate,
          ),
        ],
      ),
    );
  }
}

class _PeerDetailActions extends StatelessWidget {
  const _PeerDetailActions({
    required this.device,
    required this.hasLocation,
    required this.onChat,
    required this.onNavigate,
  });

  final RelioDevice device;
  final bool hasLocation;
  final VoidCallback onChat;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actions = [
        OutlinedButton.icon(
          onPressed: device.isConnected ? onChat : null,
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('แชท'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
        FilledButton.icon(
          onPressed: onNavigate,
          icon: const Icon(Icons.navigation_rounded),
          label: const Text('ดูเส้นทาง'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
      ];

      if (constraints.maxWidth < 440 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.15) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [actions[0], const SizedBox(height: 10), actions[1]],
        );
      }
      return Row(
        children: [
          Expanded(child: actions[0]),
          const SizedBox(width: 10),
          Expanded(child: actions[1]),
        ],
      );
    },
  );
}
