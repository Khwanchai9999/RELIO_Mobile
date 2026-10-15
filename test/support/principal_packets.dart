import 'dart:typed_data';

import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';

/// Fixtures explicitly model an upgraded remote Guest and this local principal.
Future<Uint8List> applicationBytes(
  RelioPacket packet,
  RelioRepositories repos,
) async => packet
    .withPrincipals(
      'guest:${packet.senderDeviceId}',
      (await repos.profiles.current()).principalId,
    )
    .toBytes();
