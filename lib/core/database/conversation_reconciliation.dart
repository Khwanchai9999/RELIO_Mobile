part of 'app_database.dart';

extension ConversationReconciliation on AppDatabase {
  Future<void> _createConversationAliases() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS conversation_aliases (
        conversation_id TEXT PRIMARY KEY NOT NULL REFERENCES conversations(id),
        canonical_id TEXT NOT NULL REFERENCES conversations(id),
        CHECK (conversation_id <> canonical_id)
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS conversation_aliases_canonical_idx
      ON conversation_aliases(canonical_id)
    ''');
  }

  // เก็บรหัสเดิมเพื่อให้ Cloud, คิวส่ง และใบตอบรับอ้างอิงประวัติเดิมได้
  Future<String> logicalConversationId(String id) async {
    final alias = await customSelect(
      'SELECT canonical_id FROM conversation_aliases WHERE conversation_id=?',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();
    return alias?.read<String>('canonical_id') ?? id;
  }

  Future<bool> sameLogicalConversation(String first, String second) async =>
      first == second ||
      await logicalConversationId(first) == await logicalConversationId(second);

  // ทั้งสองฝั่งใช้รหัสหลักเดียวกัน โดยไม่เปลี่ยน conversation_id ของข้อความ
  String logicalIdExpression(String column) =>
      'COALESCE((SELECT canonical_id FROM conversation_aliases '
      'WHERE conversation_id=$column), $column)';

  Future<List<QueryRow>> conversationCandidates(String local, String remote) =>
      customSelect(
        '''
        SELECT cp.conversation_id, cp.remote_device_id,
          c.participant_id, cs.owner_user_id AS scope_owner,
          EXISTS(SELECT 1 FROM cloud_conversation_links l
            WHERE l.local_conversation_id=c.id) AS cloud_bound
        FROM conversation_principals cp
        JOIN conversations c ON c.id=cp.conversation_id
        LEFT JOIN conversation_scopes cs ON cs.conversation_id=c.id
        WHERE cp.local_principal=? AND cp.remote_principal=? AND cp.state='active'
          AND NOT EXISTS (SELECT 1 FROM conversation_aliases a
            WHERE a.conversation_id=cp.conversation_id)
        ORDER BY cloud_bound DESC, c.created_at, c.id
      ''',
        variables: [Variable.withString(local), Variable.withString(remote)],
      ).get();

  bool hasVerifiedRemoteDevice(String remote, QueryRow row) {
    final device = row.readNullable<String>('remote_device_id');
    return remote.length <= 160 &&
        RegExp(r'^(account|guest):[a-zA-Z0-9_-]+$').hasMatch(remote) &&
        device != null &&
        device.isNotEmpty &&
        device == row.read<String>('participant_id');
  }

  // scope ที่หายไปต้องมี Cloud binding ซึ่งระบุทั้งเจ้าของและคู่สนทนาตรงกัน
  // ประวัติที่มีเจ้าของหรือ Cloud peer ขัดกันยังคงแยกไว้
  Future<bool> hasConversationScopeEvidence(
    QueryRow candidate,
    String local,
    String remote,
  ) async {
    final id = candidate.read<String>('conversation_id');
    final scope = candidate.readNullable<String>('scope_owner');
    final account = local.startsWith('account:') ? local.substring(8) : null;
    if (account == null && (!local.startsWith('guest:') || scope != null)) {
      return false;
    }
    if (account != null &&
        (account.isEmpty || (scope != null && scope != account))) {
      return false;
    }
    final links = await (select(
      cloudConversationLinks,
    )..where((row) => row.localConversationId.equals(id))).get();
    if (links.any(
      (link) =>
          link.ownerUserId != account || 'account:${link.peerUserId}' != remote,
    )) {
      return false;
    }
    if (account != null && scope == null && links.isEmpty) return false;
    final conflicts = await customSelect(
      '''
      SELECT 1 FROM sync_queue q
      LEFT JOIN queue_principals qp ON qp.queue_id=q.id
      WHERE (${queueConversationExpression('q')})=?
        AND ((q.owner_user_id IS NOT NULL AND q.owner_user_id IS NOT ?)
          OR (qp.local_principal LIKE 'account:%' AND qp.local_principal<>?)
          OR (? AND qp.local_principal IS NOT NULL AND qp.local_principal<>?))
      LIMIT 1
    ''',
      variables: [
        Variable.withString(id),
        Variable<String>(account),
        Variable.withString(local),
        Variable.withBool(account != null && scope == null),
        Variable.withString(local),
      ],
    ).getSingleOrNull();
    return conflicts == null;
  }

  String queueConversationExpression(String queue) =>
      '''
    CASE $queue.entity_type
      WHEN 'conversation' THEN $queue.entity_id
      WHEN 'private_backup_conversation' THEN $queue.entity_id
      WHEN 'message' THEN (SELECT m.conversation_id FROM messages m
        WHERE m.id=$queue.entity_id)
      WHEN 'private_backup_message' THEN (SELECT m.conversation_id FROM messages m
        WHERE m.id=$queue.entity_id)
      WHEN 'attachment' THEN (SELECT m.conversation_id FROM attachments a
        JOIN messages m ON m.id=a.message_id WHERE a.id=$queue.entity_id)
    END
  ''';

  Future<void> reconcileConversationDuplicates({
    String? local,
    String? remote,
  }) async {
    if (local != null && remote != null) {
      await _reconcileConversationPair(local, remote);
      return;
    }
    final pairs = await customSelect('''
      SELECT local_principal, remote_principal FROM conversation_principals
      WHERE state='active'
      GROUP BY local_principal, remote_principal HAVING COUNT(*)>1
    ''').get();
    for (final pair in pairs) {
      await _reconcileConversationPair(
        pair.read<String>('local_principal'),
        pair.read<String>('remote_principal'),
      );
    }
  }

  Future<void> _reconcileConversationPair(String local, String remote) async {
    final candidates = await conversationCandidates(local, remote);
    if (candidates.length < 2) return;
    final byDevice = <String, List<QueryRow>>{};
    for (final row in candidates) {
      if (hasVerifiedRemoteDevice(remote, row) &&
          await hasConversationScopeEvidence(row, local, remote)) {
        final device = row.read<String>('remote_device_id');
        (byDevice[device] ??= []).add(row);
      }
    }
    for (final group in byDevice.values.where((rows) => rows.length > 1)) {
      final canonical = group.first.read<String>('conversation_id');
      for (final row in group.skip(1)) {
        final alias = row.read<String>('conversation_id');
        await customUpdate(
          'UPDATE conversation_aliases SET canonical_id=? WHERE canonical_id=?',
          variables: [
            Variable.withString(canonical),
            Variable.withString(alias),
          ],
          updates: {conversations, messages},
        );
        await customUpdate(
          'INSERT INTO conversation_aliases(conversation_id,canonical_id) VALUES (?,?)',
          variables: [
            Variable.withString(alias),
            Variable.withString(canonical),
          ],
          updates: {conversations, messages},
        );
      }
    }
  }

  Future<void> _auditConversationUpgrade(String phase, int schema) async {
    final candidates = await customSelect('''
      SELECT cp.conversation_id, cs.owner_user_id IS NOT NULL AS scoped
      FROM conversation_principals cp
      LEFT JOIN conversation_scopes cs ON cs.conversation_id=cp.conversation_id
      WHERE cp.state='active' AND EXISTS (
        SELECT 1 FROM conversation_principals other
        WHERE other.state='active'
          AND other.local_principal=cp.local_principal
          AND other.remote_principal=cp.remote_principal
          AND other.remote_device_id=cp.remote_device_id
          AND other.conversation_id<>cp.conversation_id
      )
      ORDER BY cp.conversation_id
    ''').get();
    String fingerprint(String value) =>
        sha256.convert(utf8.encode(value)).toString();
    final counts = <String, int>{};
    for (final table in [
      'messages',
      'attachments',
      'sync_queue',
      'queue_principals',
      'cloud_conversation_links',
      'relay_packets',
      'relay_forward_history',
      if (schema >= 14) 'conversation_aliases',
    ]) {
      counts[table] = (await customSelect(
        'SELECT COUNT(*) AS total FROM $table',
      ).getSingle()).read<int>('total');
    }
    debugPrint(
      'RELIO_QA_CONVERSATION_UPGRADE phase=$phase schema=$schema counts=$counts',
    );
    for (final candidate in candidates) {
      final id = candidate.read<String>('conversation_id');
      final messages = await customSelect(
        'SELECT id FROM messages WHERE conversation_id=? ORDER BY id',
        variables: [Variable.withString(id)],
      ).get();
      final ids = messages.map((row) => row.read<String>('id')).toList();
      final logicalId = schema >= 14 ? await logicalConversationId(id) : id;
      debugPrint(
        'RELIO_QA_CONVERSATION_UPGRADE phase=$phase '
        'row=${fingerprint(id).substring(0, 12)} '
        'logical=${fingerprint(logicalId).substring(0, 12)} '
        'scoped=${candidate.read<int>('scoped')} '
        'distinct=${ids.toSet().length} idsHash=${fingerprint(jsonEncode(ids))}',
      );
    }
  }
}
