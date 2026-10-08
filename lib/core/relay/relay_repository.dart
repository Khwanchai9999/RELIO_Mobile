import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'relay_models.dart';

abstract interface class RelayRepository {
  Future<RelayPacketRecord?> getPacket(String packetId);
  Future<bool> storePacket(RelayEnvelope envelope);
  Future<List<RelayPacketRecord>> listForwardable(DateTime now);
  Future<void> updatePacketState(String packetId, RelayPacketState state);
  Future<RelayForwardRecord?> getForwardRecord(
    String packetId,
    String targetDeviceId,
  );
  Future<void> recordForwardAttempt({
    required String packetId,
    required String targetDeviceId,
    required String targetEndpointId,
  });
  Future<void> recordForwardResult({
    required String packetId,
    required String targetDeviceId,
    required String status,
  });
  Future<void> expirePackets(DateTime now);
  Future<int> packetCount();
}

class DriftRelayRepository implements RelayRepository {
  DriftRelayRepository(this.db);

  final AppDatabase db;

  @override
  Future<RelayPacketRecord?> getPacket(String packetId) async {
    final row = await db
        .customSelect(
          'SELECT * FROM relay_packets WHERE packet_id = ?',
          variables: [Variable<String>(packetId)],
        )
        .getSingleOrNull();
    return row == null ? null : _packet(row.data);
  }

  @override
  Future<bool> storePacket(RelayEnvelope envelope) async {
    // ใช้ packetId กันการบันทึกซ้ำ เพื่อให้รับซ้ำแล้วไม่ relay ซ้ำ
    final existing = await getPacket(envelope.packetId);
    if (existing != null) return false;
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO relay_packets
        (packet_id, origin_device_id, destination_device_id, payload_type,
         payload_id, created_at, expires_at, hop_count, max_hops, priority,
         previous_hop_device_id, protocol, payload_json, state, stored_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        envelope.packetId,
        envelope.originDeviceId,
        envelope.destinationDeviceId,
        envelope.payloadType,
        envelope.payloadId,
        envelope.createdAt.toUtc().millisecondsSinceEpoch,
        envelope.expiresAt.toUtc().millisecondsSinceEpoch,
        envelope.hopCount,
        envelope.maxHops,
        envelope.priority,
        envelope.previousHopDeviceId,
        envelope.protocol,
        jsonEncode(envelope.toJson()),
        RelayPacketState.stored.name,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
    return (await getPacket(envelope.packetId)) != null;
  }

  @override
  Future<List<RelayPacketRecord>> listForwardable(DateTime now) async {
    final rows = await db
        .customSelect(
          '''
          SELECT * FROM relay_packets
          WHERE state IN (?, ?) AND expires_at > ?
          ORDER BY priority DESC, created_at ASC
          ''',
          variables: [
            Variable<String>(RelayPacketState.stored.name),
            Variable<String>(RelayPacketState.forwarded.name),
            Variable<int>(now.toUtc().millisecondsSinceEpoch),
          ],
        )
        .get();
    return rows.map((row) => _packet(row.data)).toList(growable: false);
  }

  @override
  Future<void> updatePacketState(String packetId, RelayPacketState state) =>
      db.customStatement(
        'UPDATE relay_packets SET state = ? WHERE packet_id = ?',
        [state.name, packetId],
      );

  @override
  Future<RelayForwardRecord?> getForwardRecord(
    String packetId,
    String targetDeviceId,
  ) async {
    final row = await db
        .customSelect(
          '''
          SELECT * FROM relay_forward_history
          WHERE packet_id = ? AND target_device_id = ?
          ''',
          variables: [
            Variable<String>(packetId),
            Variable<String>(targetDeviceId),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _forward(row.data);
  }

  @override
  Future<void> recordForwardAttempt({
    required String packetId,
    required String targetDeviceId,
    required String targetEndpointId,
  }) async {
    await db.customStatement(
      '''
      INSERT INTO relay_forward_history
        (packet_id, target_device_id, target_endpoint_id, status,
         attempt_count, updated_at)
      VALUES (?, ?, ?, ?, 1, ?)
      ON CONFLICT(packet_id, target_device_id) DO UPDATE SET
        target_endpoint_id = excluded.target_endpoint_id,
        status = excluded.status,
        attempt_count = relay_forward_history.attempt_count + 1,
        updated_at = excluded.updated_at
      ''',
      [
        packetId,
        targetDeviceId,
        targetEndpointId,
        'attempting',
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> recordForwardResult({
    required String packetId,
    required String targetDeviceId,
    required String status,
  }) => db.customStatement(
    '''
    UPDATE relay_forward_history
    SET status = ?, updated_at = ?
    WHERE packet_id = ? AND target_device_id = ?
    ''',
    [
      status,
      DateTime.now().toUtc().millisecondsSinceEpoch,
      packetId,
      targetDeviceId,
    ],
  );

  @override
  Future<void> expirePackets(DateTime now) => db.customStatement(
    '''
    UPDATE relay_packets SET state = ?
    WHERE expires_at <= ? AND state IN (?, ?)
    ''',
    [
      RelayPacketState.expired.name,
      now.toUtc().millisecondsSinceEpoch,
      RelayPacketState.stored.name,
      RelayPacketState.forwarded.name,
    ],
  );

  @override
  Future<int> packetCount() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS count FROM relay_packets')
        .getSingle();
    return row.read<int>('count');
  }

  RelayPacketRecord _packet(Map<String, Object?> data) => RelayPacketRecord(
    envelope: RelayEnvelope.fromJson(
      (jsonDecode(data['payload_json']! as String) as Map)
          .cast<String, dynamic>(),
    ),
    state: RelayPacketState.values.firstWhere(
      (item) => item.name == data['state'],
      orElse: () => RelayPacketState.blocked,
    ),
    storedAt: _date(data['stored_at']),
  );

  RelayForwardRecord _forward(Map<String, Object?> data) => RelayForwardRecord(
    packetId: data['packet_id']! as String,
    targetDeviceId: data['target_device_id']! as String,
    targetEndpointId: data['target_endpoint_id']! as String,
    status: data['status']! as String,
    attemptCount: data['attempt_count']! as int,
    updatedAt: _date(data['updated_at']),
  );

  DateTime _date(Object? value) => DateTime.fromMillisecondsSinceEpoch(
    value is int ? value : int.parse(value.toString()),
    isUtc: true,
  );
}
