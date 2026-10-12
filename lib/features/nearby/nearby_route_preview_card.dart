import 'package:flutter/material.dart';

import '../../core/domain/relio_entities.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../data/models/prototype_models.dart';

class NearbyRoutePreviewCard extends StatelessWidget {
  const NearbyRoutePreviewCard({
    required this.peer,
    required this.myLocation,
    required this.onClose,
    super.key,
  });

  final RelioDevice peer;
  final LocationData? myLocation;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final distance = NearbyMapCalculations.distanceMeters(
      fromLatitude: myLocation?.latitude,
      fromLongitude: myLocation?.longitude,
      toLatitude: peer.locationLatitude,
      toLongitude: peer.locationLongitude,
    );
    final bearing = NearbyMapCalculations.bearingDegrees(
      fromLatitude: myLocation?.latitude,
      fromLongitude: myLocation?.longitude,
      toLatitude: peer.locationLatitude,
      toLongitude: peer.locationLongitude,
    );
    final now = DateTime.now();
    return Positioned(
      left: 12,
      right: 12,
      bottom: 104,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.route_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ดูเส้นทาง • ${peer.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      myLocation == null
                          ? 'ตำแหน่งเครื่องนี้ยังไม่พร้อม • ${NearbyMapCalculations.freshnessLabel(peer.locationCapturedAt, now)}'
                          : '${NearbyMapCalculations.distanceLabel(distance)} • ${NearbyMapCalculations.bearingLabel(bearing)} • ${NearbyMapCalculations.freshnessLabel(peer.locationCapturedAt, now)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (myLocation != null)
                      Text(
                        'เส้นตรงโดยประมาณ ไม่ใช่เส้นทางถนน',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'ปิดดูเส้นทาง',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
