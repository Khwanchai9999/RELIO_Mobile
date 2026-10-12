// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _participantIdMeta = const VerificationMeta(
    'participantId',
  );
  @override
  late final GeneratedColumn<String> participantId = GeneratedColumn<String>(
    'participant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _participantStatusMeta = const VerificationMeta(
    'participantStatus',
  );
  @override
  late final GeneratedColumn<String> participantStatus =
      GeneratedColumn<String>(
        'participant_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastMessageAtMeta = const VerificationMeta(
    'lastMessageAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastMessageAt =
      GeneratedColumn<DateTime>(
        'last_message_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    participantId,
    displayName,
    participantStatus,
    unreadCount,
    lastMessageAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('participant_id')) {
      context.handle(
        _participantIdMeta,
        participantId.isAcceptableOrUnknown(
          data['participant_id']!,
          _participantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_participantIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('participant_status')) {
      context.handle(
        _participantStatusMeta,
        participantStatus.isAcceptableOrUnknown(
          data['participant_status']!,
          _participantStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_participantStatusMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('last_message_at')) {
      context.handle(
        _lastMessageAtMeta,
        lastMessageAt.isAcceptableOrUnknown(
          data['last_message_at']!,
          _lastMessageAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      participantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participant_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      participantStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participant_status'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      lastMessageAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_message_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String id;
  final String participantId;
  final String displayName;
  final String participantStatus;
  final int unreadCount;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Conversation({
    required this.id,
    required this.participantId,
    required this.displayName,
    required this.participantStatus,
    required this.unreadCount,
    this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['participant_id'] = Variable<String>(participantId);
    map['display_name'] = Variable<String>(displayName);
    map['participant_status'] = Variable<String>(participantStatus);
    map['unread_count'] = Variable<int>(unreadCount);
    if (!nullToAbsent || lastMessageAt != null) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      participantId: Value(participantId),
      displayName: Value(displayName),
      participantStatus: Value(participantStatus),
      unreadCount: Value(unreadCount),
      lastMessageAt: lastMessageAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<String>(json['id']),
      participantId: serializer.fromJson<String>(json['participantId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      participantStatus: serializer.fromJson<String>(json['participantStatus']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      lastMessageAt: serializer.fromJson<DateTime?>(json['lastMessageAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'participantId': serializer.toJson<String>(participantId),
      'displayName': serializer.toJson<String>(displayName),
      'participantStatus': serializer.toJson<String>(participantStatus),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'lastMessageAt': serializer.toJson<DateTime?>(lastMessageAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Conversation copyWith({
    String? id,
    String? participantId,
    String? displayName,
    String? participantStatus,
    int? unreadCount,
    Value<DateTime?> lastMessageAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Conversation(
    id: id ?? this.id,
    participantId: participantId ?? this.participantId,
    displayName: displayName ?? this.displayName,
    participantStatus: participantStatus ?? this.participantStatus,
    unreadCount: unreadCount ?? this.unreadCount,
    lastMessageAt: lastMessageAt.present
        ? lastMessageAt.value
        : this.lastMessageAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      participantId: data.participantId.present
          ? data.participantId.value
          : this.participantId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      participantStatus: data.participantStatus.present
          ? data.participantStatus.value
          : this.participantStatus,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('participantId: $participantId, ')
          ..write('displayName: $displayName, ')
          ..write('participantStatus: $participantStatus, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    participantId,
    displayName,
    participantStatus,
    unreadCount,
    lastMessageAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.participantId == this.participantId &&
          other.displayName == this.displayName &&
          other.participantStatus == this.participantStatus &&
          other.unreadCount == this.unreadCount &&
          other.lastMessageAt == this.lastMessageAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> id;
  final Value<String> participantId;
  final Value<String> displayName;
  final Value<String> participantStatus;
  final Value<int> unreadCount;
  final Value<DateTime?> lastMessageAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.participantId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.participantStatus = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    required String participantId,
    required String displayName,
    required String participantStatus,
    this.unreadCount = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       participantId = Value(participantId),
       displayName = Value(displayName),
       participantStatus = Value(participantStatus),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Conversation> custom({
    Expression<String>? id,
    Expression<String>? participantId,
    Expression<String>? displayName,
    Expression<String>? participantStatus,
    Expression<int>? unreadCount,
    Expression<DateTime>? lastMessageAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (participantId != null) 'participant_id': participantId,
      if (displayName != null) 'display_name': displayName,
      if (participantStatus != null) 'participant_status': participantStatus,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? id,
    Value<String>? participantId,
    Value<String>? displayName,
    Value<String>? participantStatus,
    Value<int>? unreadCount,
    Value<DateTime?>? lastMessageAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      participantId: participantId ?? this.participantId,
      displayName: displayName ?? this.displayName,
      participantStatus: participantStatus ?? this.participantStatus,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (participantId.present) {
      map['participant_id'] = Variable<String>(participantId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (participantStatus.present) {
      map['participant_status'] = Variable<String>(participantStatus.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('participantId: $participantId, ')
          ..write('displayName: $displayName, ')
          ..write('participantStatus: $participantStatus, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CloudConversationLinksTable extends CloudConversationLinks
    with TableInfo<$CloudConversationLinksTable, CloudConversationLink> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CloudConversationLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localConversationIdMeta =
      const VerificationMeta('localConversationId');
  @override
  late final GeneratedColumn<String> localConversationId =
      GeneratedColumn<String>(
        'local_conversation_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _cloudConversationIdMeta =
      const VerificationMeta('cloudConversationId');
  @override
  late final GeneratedColumn<String> cloudConversationId =
      GeneratedColumn<String>(
        'cloud_conversation_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerUserIdMeta = const VerificationMeta(
    'peerUserId',
  );
  @override
  late final GeneratedColumn<String> peerUserId = GeneratedColumn<String>(
    'peer_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageCursorAtMeta = const VerificationMeta(
    'messageCursorAt',
  );
  @override
  late final GeneratedColumn<DateTime> messageCursorAt =
      GeneratedColumn<DateTime>(
        'message_cursor_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _messageCursorIdMeta = const VerificationMeta(
    'messageCursorId',
  );
  @override
  late final GeneratedColumn<String> messageCursorId = GeneratedColumn<String>(
    'message_cursor_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptCursorAtMeta = const VerificationMeta(
    'receiptCursorAt',
  );
  @override
  late final GeneratedColumn<DateTime> receiptCursorAt =
      GeneratedColumn<DateTime>(
        'receipt_cursor_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _receiptCursorMessageIdMeta =
      const VerificationMeta('receiptCursorMessageId');
  @override
  late final GeneratedColumn<String> receiptCursorMessageId =
      GeneratedColumn<String>(
        'receipt_cursor_message_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _receiptCursorReaderIdMeta =
      const VerificationMeta('receiptCursorReaderId');
  @override
  late final GeneratedColumn<String> receiptCursorReaderId =
      GeneratedColumn<String>(
        'receipt_cursor_reader_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localConversationId,
    cloudConversationId,
    ownerUserId,
    peerUserId,
    messageCursorAt,
    messageCursorId,
    receiptCursorAt,
    receiptCursorMessageId,
    receiptCursorReaderId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cloud_conversation_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<CloudConversationLink> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_conversation_id')) {
      context.handle(
        _localConversationIdMeta,
        localConversationId.isAcceptableOrUnknown(
          data['local_conversation_id']!,
          _localConversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localConversationIdMeta);
    }
    if (data.containsKey('cloud_conversation_id')) {
      context.handle(
        _cloudConversationIdMeta,
        cloudConversationId.isAcceptableOrUnknown(
          data['cloud_conversation_id']!,
          _cloudConversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cloudConversationIdMeta);
    }
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('peer_user_id')) {
      context.handle(
        _peerUserIdMeta,
        peerUserId.isAcceptableOrUnknown(
          data['peer_user_id']!,
          _peerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerUserIdMeta);
    }
    if (data.containsKey('message_cursor_at')) {
      context.handle(
        _messageCursorAtMeta,
        messageCursorAt.isAcceptableOrUnknown(
          data['message_cursor_at']!,
          _messageCursorAtMeta,
        ),
      );
    }
    if (data.containsKey('message_cursor_id')) {
      context.handle(
        _messageCursorIdMeta,
        messageCursorId.isAcceptableOrUnknown(
          data['message_cursor_id']!,
          _messageCursorIdMeta,
        ),
      );
    }
    if (data.containsKey('receipt_cursor_at')) {
      context.handle(
        _receiptCursorAtMeta,
        receiptCursorAt.isAcceptableOrUnknown(
          data['receipt_cursor_at']!,
          _receiptCursorAtMeta,
        ),
      );
    }
    if (data.containsKey('receipt_cursor_message_id')) {
      context.handle(
        _receiptCursorMessageIdMeta,
        receiptCursorMessageId.isAcceptableOrUnknown(
          data['receipt_cursor_message_id']!,
          _receiptCursorMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('receipt_cursor_reader_id')) {
      context.handle(
        _receiptCursorReaderIdMeta,
        receiptCursorReaderId.isAcceptableOrUnknown(
          data['receipt_cursor_reader_id']!,
          _receiptCursorReaderIdMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localConversationId, ownerUserId};
  @override
  CloudConversationLink map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CloudConversationLink(
      localConversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_conversation_id'],
      )!,
      cloudConversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_conversation_id'],
      )!,
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      peerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_user_id'],
      )!,
      messageCursorAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}message_cursor_at'],
      ),
      messageCursorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_cursor_id'],
      ),
      receiptCursorAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}receipt_cursor_at'],
      ),
      receiptCursorMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_cursor_message_id'],
      ),
      receiptCursorReaderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_cursor_reader_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CloudConversationLinksTable createAlias(String alias) {
    return $CloudConversationLinksTable(attachedDatabase, alias);
  }
}

class CloudConversationLink extends DataClass
    implements Insertable<CloudConversationLink> {
  final String localConversationId;
  final String cloudConversationId;
  final String ownerUserId;
  final String peerUserId;
  final DateTime? messageCursorAt;
  final String? messageCursorId;
  final DateTime? receiptCursorAt;
  final String? receiptCursorMessageId;
  final String? receiptCursorReaderId;
  final DateTime updatedAt;
  const CloudConversationLink({
    required this.localConversationId,
    required this.cloudConversationId,
    required this.ownerUserId,
    required this.peerUserId,
    this.messageCursorAt,
    this.messageCursorId,
    this.receiptCursorAt,
    this.receiptCursorMessageId,
    this.receiptCursorReaderId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_conversation_id'] = Variable<String>(localConversationId);
    map['cloud_conversation_id'] = Variable<String>(cloudConversationId);
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['peer_user_id'] = Variable<String>(peerUserId);
    if (!nullToAbsent || messageCursorAt != null) {
      map['message_cursor_at'] = Variable<DateTime>(messageCursorAt);
    }
    if (!nullToAbsent || messageCursorId != null) {
      map['message_cursor_id'] = Variable<String>(messageCursorId);
    }
    if (!nullToAbsent || receiptCursorAt != null) {
      map['receipt_cursor_at'] = Variable<DateTime>(receiptCursorAt);
    }
    if (!nullToAbsent || receiptCursorMessageId != null) {
      map['receipt_cursor_message_id'] = Variable<String>(
        receiptCursorMessageId,
      );
    }
    if (!nullToAbsent || receiptCursorReaderId != null) {
      map['receipt_cursor_reader_id'] = Variable<String>(receiptCursorReaderId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CloudConversationLinksCompanion toCompanion(bool nullToAbsent) {
    return CloudConversationLinksCompanion(
      localConversationId: Value(localConversationId),
      cloudConversationId: Value(cloudConversationId),
      ownerUserId: Value(ownerUserId),
      peerUserId: Value(peerUserId),
      messageCursorAt: messageCursorAt == null && nullToAbsent
          ? const Value.absent()
          : Value(messageCursorAt),
      messageCursorId: messageCursorId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageCursorId),
      receiptCursorAt: receiptCursorAt == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptCursorAt),
      receiptCursorMessageId: receiptCursorMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptCursorMessageId),
      receiptCursorReaderId: receiptCursorReaderId == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptCursorReaderId),
      updatedAt: Value(updatedAt),
    );
  }

  factory CloudConversationLink.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CloudConversationLink(
      localConversationId: serializer.fromJson<String>(
        json['localConversationId'],
      ),
      cloudConversationId: serializer.fromJson<String>(
        json['cloudConversationId'],
      ),
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      peerUserId: serializer.fromJson<String>(json['peerUserId']),
      messageCursorAt: serializer.fromJson<DateTime?>(json['messageCursorAt']),
      messageCursorId: serializer.fromJson<String?>(json['messageCursorId']),
      receiptCursorAt: serializer.fromJson<DateTime?>(json['receiptCursorAt']),
      receiptCursorMessageId: serializer.fromJson<String?>(
        json['receiptCursorMessageId'],
      ),
      receiptCursorReaderId: serializer.fromJson<String?>(
        json['receiptCursorReaderId'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localConversationId': serializer.toJson<String>(localConversationId),
      'cloudConversationId': serializer.toJson<String>(cloudConversationId),
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'peerUserId': serializer.toJson<String>(peerUserId),
      'messageCursorAt': serializer.toJson<DateTime?>(messageCursorAt),
      'messageCursorId': serializer.toJson<String?>(messageCursorId),
      'receiptCursorAt': serializer.toJson<DateTime?>(receiptCursorAt),
      'receiptCursorMessageId': serializer.toJson<String?>(
        receiptCursorMessageId,
      ),
      'receiptCursorReaderId': serializer.toJson<String?>(
        receiptCursorReaderId,
      ),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CloudConversationLink copyWith({
    String? localConversationId,
    String? cloudConversationId,
    String? ownerUserId,
    String? peerUserId,
    Value<DateTime?> messageCursorAt = const Value.absent(),
    Value<String?> messageCursorId = const Value.absent(),
    Value<DateTime?> receiptCursorAt = const Value.absent(),
    Value<String?> receiptCursorMessageId = const Value.absent(),
    Value<String?> receiptCursorReaderId = const Value.absent(),
    DateTime? updatedAt,
  }) => CloudConversationLink(
    localConversationId: localConversationId ?? this.localConversationId,
    cloudConversationId: cloudConversationId ?? this.cloudConversationId,
    ownerUserId: ownerUserId ?? this.ownerUserId,
    peerUserId: peerUserId ?? this.peerUserId,
    messageCursorAt: messageCursorAt.present
        ? messageCursorAt.value
        : this.messageCursorAt,
    messageCursorId: messageCursorId.present
        ? messageCursorId.value
        : this.messageCursorId,
    receiptCursorAt: receiptCursorAt.present
        ? receiptCursorAt.value
        : this.receiptCursorAt,
    receiptCursorMessageId: receiptCursorMessageId.present
        ? receiptCursorMessageId.value
        : this.receiptCursorMessageId,
    receiptCursorReaderId: receiptCursorReaderId.present
        ? receiptCursorReaderId.value
        : this.receiptCursorReaderId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CloudConversationLink copyWithCompanion(
    CloudConversationLinksCompanion data,
  ) {
    return CloudConversationLink(
      localConversationId: data.localConversationId.present
          ? data.localConversationId.value
          : this.localConversationId,
      cloudConversationId: data.cloudConversationId.present
          ? data.cloudConversationId.value
          : this.cloudConversationId,
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      peerUserId: data.peerUserId.present
          ? data.peerUserId.value
          : this.peerUserId,
      messageCursorAt: data.messageCursorAt.present
          ? data.messageCursorAt.value
          : this.messageCursorAt,
      messageCursorId: data.messageCursorId.present
          ? data.messageCursorId.value
          : this.messageCursorId,
      receiptCursorAt: data.receiptCursorAt.present
          ? data.receiptCursorAt.value
          : this.receiptCursorAt,
      receiptCursorMessageId: data.receiptCursorMessageId.present
          ? data.receiptCursorMessageId.value
          : this.receiptCursorMessageId,
      receiptCursorReaderId: data.receiptCursorReaderId.present
          ? data.receiptCursorReaderId.value
          : this.receiptCursorReaderId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CloudConversationLink(')
          ..write('localConversationId: $localConversationId, ')
          ..write('cloudConversationId: $cloudConversationId, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('peerUserId: $peerUserId, ')
          ..write('messageCursorAt: $messageCursorAt, ')
          ..write('messageCursorId: $messageCursorId, ')
          ..write('receiptCursorAt: $receiptCursorAt, ')
          ..write('receiptCursorMessageId: $receiptCursorMessageId, ')
          ..write('receiptCursorReaderId: $receiptCursorReaderId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localConversationId,
    cloudConversationId,
    ownerUserId,
    peerUserId,
    messageCursorAt,
    messageCursorId,
    receiptCursorAt,
    receiptCursorMessageId,
    receiptCursorReaderId,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CloudConversationLink &&
          other.localConversationId == this.localConversationId &&
          other.cloudConversationId == this.cloudConversationId &&
          other.ownerUserId == this.ownerUserId &&
          other.peerUserId == this.peerUserId &&
          other.messageCursorAt == this.messageCursorAt &&
          other.messageCursorId == this.messageCursorId &&
          other.receiptCursorAt == this.receiptCursorAt &&
          other.receiptCursorMessageId == this.receiptCursorMessageId &&
          other.receiptCursorReaderId == this.receiptCursorReaderId &&
          other.updatedAt == this.updatedAt);
}

class CloudConversationLinksCompanion
    extends UpdateCompanion<CloudConversationLink> {
  final Value<String> localConversationId;
  final Value<String> cloudConversationId;
  final Value<String> ownerUserId;
  final Value<String> peerUserId;
  final Value<DateTime?> messageCursorAt;
  final Value<String?> messageCursorId;
  final Value<DateTime?> receiptCursorAt;
  final Value<String?> receiptCursorMessageId;
  final Value<String?> receiptCursorReaderId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CloudConversationLinksCompanion({
    this.localConversationId = const Value.absent(),
    this.cloudConversationId = const Value.absent(),
    this.ownerUserId = const Value.absent(),
    this.peerUserId = const Value.absent(),
    this.messageCursorAt = const Value.absent(),
    this.messageCursorId = const Value.absent(),
    this.receiptCursorAt = const Value.absent(),
    this.receiptCursorMessageId = const Value.absent(),
    this.receiptCursorReaderId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CloudConversationLinksCompanion.insert({
    required String localConversationId,
    required String cloudConversationId,
    required String ownerUserId,
    required String peerUserId,
    this.messageCursorAt = const Value.absent(),
    this.messageCursorId = const Value.absent(),
    this.receiptCursorAt = const Value.absent(),
    this.receiptCursorMessageId = const Value.absent(),
    this.receiptCursorReaderId = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : localConversationId = Value(localConversationId),
       cloudConversationId = Value(cloudConversationId),
       ownerUserId = Value(ownerUserId),
       peerUserId = Value(peerUserId),
       updatedAt = Value(updatedAt);
  static Insertable<CloudConversationLink> custom({
    Expression<String>? localConversationId,
    Expression<String>? cloudConversationId,
    Expression<String>? ownerUserId,
    Expression<String>? peerUserId,
    Expression<DateTime>? messageCursorAt,
    Expression<String>? messageCursorId,
    Expression<DateTime>? receiptCursorAt,
    Expression<String>? receiptCursorMessageId,
    Expression<String>? receiptCursorReaderId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localConversationId != null)
        'local_conversation_id': localConversationId,
      if (cloudConversationId != null)
        'cloud_conversation_id': cloudConversationId,
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (peerUserId != null) 'peer_user_id': peerUserId,
      if (messageCursorAt != null) 'message_cursor_at': messageCursorAt,
      if (messageCursorId != null) 'message_cursor_id': messageCursorId,
      if (receiptCursorAt != null) 'receipt_cursor_at': receiptCursorAt,
      if (receiptCursorMessageId != null)
        'receipt_cursor_message_id': receiptCursorMessageId,
      if (receiptCursorReaderId != null)
        'receipt_cursor_reader_id': receiptCursorReaderId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CloudConversationLinksCompanion copyWith({
    Value<String>? localConversationId,
    Value<String>? cloudConversationId,
    Value<String>? ownerUserId,
    Value<String>? peerUserId,
    Value<DateTime?>? messageCursorAt,
    Value<String?>? messageCursorId,
    Value<DateTime?>? receiptCursorAt,
    Value<String?>? receiptCursorMessageId,
    Value<String?>? receiptCursorReaderId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CloudConversationLinksCompanion(
      localConversationId: localConversationId ?? this.localConversationId,
      cloudConversationId: cloudConversationId ?? this.cloudConversationId,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      peerUserId: peerUserId ?? this.peerUserId,
      messageCursorAt: messageCursorAt ?? this.messageCursorAt,
      messageCursorId: messageCursorId ?? this.messageCursorId,
      receiptCursorAt: receiptCursorAt ?? this.receiptCursorAt,
      receiptCursorMessageId:
          receiptCursorMessageId ?? this.receiptCursorMessageId,
      receiptCursorReaderId:
          receiptCursorReaderId ?? this.receiptCursorReaderId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localConversationId.present) {
      map['local_conversation_id'] = Variable<String>(
        localConversationId.value,
      );
    }
    if (cloudConversationId.present) {
      map['cloud_conversation_id'] = Variable<String>(
        cloudConversationId.value,
      );
    }
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (peerUserId.present) {
      map['peer_user_id'] = Variable<String>(peerUserId.value);
    }
    if (messageCursorAt.present) {
      map['message_cursor_at'] = Variable<DateTime>(messageCursorAt.value);
    }
    if (messageCursorId.present) {
      map['message_cursor_id'] = Variable<String>(messageCursorId.value);
    }
    if (receiptCursorAt.present) {
      map['receipt_cursor_at'] = Variable<DateTime>(receiptCursorAt.value);
    }
    if (receiptCursorMessageId.present) {
      map['receipt_cursor_message_id'] = Variable<String>(
        receiptCursorMessageId.value,
      );
    }
    if (receiptCursorReaderId.present) {
      map['receipt_cursor_reader_id'] = Variable<String>(
        receiptCursorReaderId.value,
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CloudConversationLinksCompanion(')
          ..write('localConversationId: $localConversationId, ')
          ..write('cloudConversationId: $cloudConversationId, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('peerUserId: $peerUserId, ')
          ..write('messageCursorAt: $messageCursorAt, ')
          ..write('messageCursorId: $messageCursorId, ')
          ..write('receiptCursorAt: $receiptCursorAt, ')
          ..write('receiptCursorMessageId: $receiptCursorMessageId, ')
          ..write('receiptCursorReaderId: $receiptCursorReaderId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderDeviceIdMeta = const VerificationMeta(
    'senderDeviceId',
  );
  @override
  late final GeneratedColumn<String> senderDeviceId = GeneratedColumn<String>(
    'sender_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _messageTypeMeta = const VerificationMeta(
    'messageType',
  );
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
    'message_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveryStatusMeta = const VerificationMeta(
    'deliveryStatus',
  );
  @override
  late final GeneratedColumn<String> deliveryStatus = GeneratedColumn<String>(
    'delivery_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cloudSyncStatusMeta = const VerificationMeta(
    'cloudSyncStatus',
  );
  @override
  late final GeneratedColumn<String> cloudSyncStatus = GeneratedColumn<String>(
    'cloud_sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('notQueued'),
  );
  static const VerificationMeta _isOutgoingMeta = const VerificationMeta(
    'isOutgoing',
  );
  @override
  late final GeneratedColumn<bool> isOutgoing = GeneratedColumn<bool>(
    'is_outgoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_outgoing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationAccuracyMeta = const VerificationMeta(
    'locationAccuracy',
  );
  @override
  late final GeneratedColumn<double> locationAccuracy = GeneratedColumn<double>(
    'location_accuracy',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationCapturedAtMeta =
      const VerificationMeta('locationCapturedAt');
  @override
  late final GeneratedColumn<DateTime> locationCapturedAt =
      GeneratedColumn<DateTime>(
        'location_captured_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _nearbyMessageIdMeta = const VerificationMeta(
    'nearbyMessageId',
  );
  @override
  late final GeneratedColumn<String> nearbyMessageId = GeneratedColumn<String>(
    'nearby_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    senderId,
    senderDeviceId,
    messageType,
    content,
    createdAt,
    updatedAt,
    deliveryStatus,
    cloudSyncStatus,
    isOutgoing,
    localFilePath,
    latitude,
    longitude,
    locationAccuracy,
    locationCapturedAt,
    nearbyMessageId,
    readAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('sender_device_id')) {
      context.handle(
        _senderDeviceIdMeta,
        senderDeviceId.isAcceptableOrUnknown(
          data['sender_device_id']!,
          _senderDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('message_type')) {
      context.handle(
        _messageTypeMeta,
        messageType.isAcceptableOrUnknown(
          data['message_type']!,
          _messageTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageTypeMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('delivery_status')) {
      context.handle(
        _deliveryStatusMeta,
        deliveryStatus.isAcceptableOrUnknown(
          data['delivery_status']!,
          _deliveryStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deliveryStatusMeta);
    }
    if (data.containsKey('cloud_sync_status')) {
      context.handle(
        _cloudSyncStatusMeta,
        cloudSyncStatus.isAcceptableOrUnknown(
          data['cloud_sync_status']!,
          _cloudSyncStatusMeta,
        ),
      );
    }
    if (data.containsKey('is_outgoing')) {
      context.handle(
        _isOutgoingMeta,
        isOutgoing.isAcceptableOrUnknown(data['is_outgoing']!, _isOutgoingMeta),
      );
    } else if (isInserting) {
      context.missing(_isOutgoingMeta);
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('location_accuracy')) {
      context.handle(
        _locationAccuracyMeta,
        locationAccuracy.isAcceptableOrUnknown(
          data['location_accuracy']!,
          _locationAccuracyMeta,
        ),
      );
    }
    if (data.containsKey('location_captured_at')) {
      context.handle(
        _locationCapturedAtMeta,
        locationCapturedAt.isAcceptableOrUnknown(
          data['location_captured_at']!,
          _locationCapturedAtMeta,
        ),
      );
    }
    if (data.containsKey('nearby_message_id')) {
      context.handle(
        _nearbyMessageIdMeta,
        nearbyMessageId.isAcceptableOrUnknown(
          data['nearby_message_id']!,
          _nearbyMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      senderDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_device_id'],
      ),
      messageType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_type'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deliveryStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_status'],
      )!,
      cloudSyncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_sync_status'],
      )!,
      isOutgoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_outgoing'],
      )!,
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      locationAccuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}location_accuracy'],
      ),
      locationCapturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}location_captured_at'],
      ),
      nearbyMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nearby_message_id'],
      ),
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}read_at'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String conversationId;
  final String senderId;
  final String? senderDeviceId;
  final String messageType;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deliveryStatus;
  final String cloudSyncStatus;
  final bool isOutgoing;
  final String? localFilePath;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracy;
  final DateTime? locationCapturedAt;
  final String? nearbyMessageId;
  final DateTime? readAt;
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.senderDeviceId,
    required this.messageType,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.deliveryStatus,
    required this.cloudSyncStatus,
    required this.isOutgoing,
    this.localFilePath,
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    this.locationCapturedAt,
    this.nearbyMessageId,
    this.readAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['sender_id'] = Variable<String>(senderId);
    if (!nullToAbsent || senderDeviceId != null) {
      map['sender_device_id'] = Variable<String>(senderDeviceId);
    }
    map['message_type'] = Variable<String>(messageType);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['delivery_status'] = Variable<String>(deliveryStatus);
    map['cloud_sync_status'] = Variable<String>(cloudSyncStatus);
    map['is_outgoing'] = Variable<bool>(isOutgoing);
    if (!nullToAbsent || localFilePath != null) {
      map['local_file_path'] = Variable<String>(localFilePath);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || locationAccuracy != null) {
      map['location_accuracy'] = Variable<double>(locationAccuracy);
    }
    if (!nullToAbsent || locationCapturedAt != null) {
      map['location_captured_at'] = Variable<DateTime>(locationCapturedAt);
    }
    if (!nullToAbsent || nearbyMessageId != null) {
      map['nearby_message_id'] = Variable<String>(nearbyMessageId);
    }
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      senderId: Value(senderId),
      senderDeviceId: senderDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(senderDeviceId),
      messageType: Value(messageType),
      content: Value(content),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deliveryStatus: Value(deliveryStatus),
      cloudSyncStatus: Value(cloudSyncStatus),
      isOutgoing: Value(isOutgoing),
      localFilePath: localFilePath == null && nullToAbsent
          ? const Value.absent()
          : Value(localFilePath),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      locationAccuracy: locationAccuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(locationAccuracy),
      locationCapturedAt: locationCapturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(locationCapturedAt),
      nearbyMessageId: nearbyMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(nearbyMessageId),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      senderDeviceId: serializer.fromJson<String?>(json['senderDeviceId']),
      messageType: serializer.fromJson<String>(json['messageType']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deliveryStatus: serializer.fromJson<String>(json['deliveryStatus']),
      cloudSyncStatus: serializer.fromJson<String>(json['cloudSyncStatus']),
      isOutgoing: serializer.fromJson<bool>(json['isOutgoing']),
      localFilePath: serializer.fromJson<String?>(json['localFilePath']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      locationAccuracy: serializer.fromJson<double?>(json['locationAccuracy']),
      locationCapturedAt: serializer.fromJson<DateTime?>(
        json['locationCapturedAt'],
      ),
      nearbyMessageId: serializer.fromJson<String?>(json['nearbyMessageId']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'senderId': serializer.toJson<String>(senderId),
      'senderDeviceId': serializer.toJson<String?>(senderDeviceId),
      'messageType': serializer.toJson<String>(messageType),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deliveryStatus': serializer.toJson<String>(deliveryStatus),
      'cloudSyncStatus': serializer.toJson<String>(cloudSyncStatus),
      'isOutgoing': serializer.toJson<bool>(isOutgoing),
      'localFilePath': serializer.toJson<String?>(localFilePath),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'locationAccuracy': serializer.toJson<double?>(locationAccuracy),
      'locationCapturedAt': serializer.toJson<DateTime?>(locationCapturedAt),
      'nearbyMessageId': serializer.toJson<String?>(nearbyMessageId),
      'readAt': serializer.toJson<DateTime?>(readAt),
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    Value<String?> senderDeviceId = const Value.absent(),
    String? messageType,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? deliveryStatus,
    String? cloudSyncStatus,
    bool? isOutgoing,
    Value<String?> localFilePath = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> locationAccuracy = const Value.absent(),
    Value<DateTime?> locationCapturedAt = const Value.absent(),
    Value<String?> nearbyMessageId = const Value.absent(),
    Value<DateTime?> readAt = const Value.absent(),
  }) => Message(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    senderId: senderId ?? this.senderId,
    senderDeviceId: senderDeviceId.present
        ? senderDeviceId.value
        : this.senderDeviceId,
    messageType: messageType ?? this.messageType,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    cloudSyncStatus: cloudSyncStatus ?? this.cloudSyncStatus,
    isOutgoing: isOutgoing ?? this.isOutgoing,
    localFilePath: localFilePath.present
        ? localFilePath.value
        : this.localFilePath,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    locationAccuracy: locationAccuracy.present
        ? locationAccuracy.value
        : this.locationAccuracy,
    locationCapturedAt: locationCapturedAt.present
        ? locationCapturedAt.value
        : this.locationCapturedAt,
    nearbyMessageId: nearbyMessageId.present
        ? nearbyMessageId.value
        : this.nearbyMessageId,
    readAt: readAt.present ? readAt.value : this.readAt,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      senderDeviceId: data.senderDeviceId.present
          ? data.senderDeviceId.value
          : this.senderDeviceId,
      messageType: data.messageType.present
          ? data.messageType.value
          : this.messageType,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deliveryStatus: data.deliveryStatus.present
          ? data.deliveryStatus.value
          : this.deliveryStatus,
      cloudSyncStatus: data.cloudSyncStatus.present
          ? data.cloudSyncStatus.value
          : this.cloudSyncStatus,
      isOutgoing: data.isOutgoing.present
          ? data.isOutgoing.value
          : this.isOutgoing,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      locationAccuracy: data.locationAccuracy.present
          ? data.locationAccuracy.value
          : this.locationAccuracy,
      locationCapturedAt: data.locationCapturedAt.present
          ? data.locationCapturedAt.value
          : this.locationCapturedAt,
      nearbyMessageId: data.nearbyMessageId.present
          ? data.nearbyMessageId.value
          : this.nearbyMessageId,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('senderDeviceId: $senderDeviceId, ')
          ..write('messageType: $messageType, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deliveryStatus: $deliveryStatus, ')
          ..write('cloudSyncStatus: $cloudSyncStatus, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracy: $locationAccuracy, ')
          ..write('locationCapturedAt: $locationCapturedAt, ')
          ..write('nearbyMessageId: $nearbyMessageId, ')
          ..write('readAt: $readAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    senderId,
    senderDeviceId,
    messageType,
    content,
    createdAt,
    updatedAt,
    deliveryStatus,
    cloudSyncStatus,
    isOutgoing,
    localFilePath,
    latitude,
    longitude,
    locationAccuracy,
    locationCapturedAt,
    nearbyMessageId,
    readAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.senderId == this.senderId &&
          other.senderDeviceId == this.senderDeviceId &&
          other.messageType == this.messageType &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deliveryStatus == this.deliveryStatus &&
          other.cloudSyncStatus == this.cloudSyncStatus &&
          other.isOutgoing == this.isOutgoing &&
          other.localFilePath == this.localFilePath &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.locationAccuracy == this.locationAccuracy &&
          other.locationCapturedAt == this.locationCapturedAt &&
          other.nearbyMessageId == this.nearbyMessageId &&
          other.readAt == this.readAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> senderId;
  final Value<String?> senderDeviceId;
  final Value<String> messageType;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> deliveryStatus;
  final Value<String> cloudSyncStatus;
  final Value<bool> isOutgoing;
  final Value<String?> localFilePath;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> locationAccuracy;
  final Value<DateTime?> locationCapturedAt;
  final Value<String?> nearbyMessageId;
  final Value<DateTime?> readAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.senderDeviceId = const Value.absent(),
    this.messageType = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deliveryStatus = const Value.absent(),
    this.cloudSyncStatus = const Value.absent(),
    this.isOutgoing = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracy = const Value.absent(),
    this.locationCapturedAt = const Value.absent(),
    this.nearbyMessageId = const Value.absent(),
    this.readAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String senderId,
    this.senderDeviceId = const Value.absent(),
    required String messageType,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String deliveryStatus,
    this.cloudSyncStatus = const Value.absent(),
    required bool isOutgoing,
    this.localFilePath = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracy = const Value.absent(),
    this.locationCapturedAt = const Value.absent(),
    this.nearbyMessageId = const Value.absent(),
    this.readAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       senderId = Value(senderId),
       messageType = Value(messageType),
       content = Value(content),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       deliveryStatus = Value(deliveryStatus),
       isOutgoing = Value(isOutgoing);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? senderId,
    Expression<String>? senderDeviceId,
    Expression<String>? messageType,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? deliveryStatus,
    Expression<String>? cloudSyncStatus,
    Expression<bool>? isOutgoing,
    Expression<String>? localFilePath,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? locationAccuracy,
    Expression<DateTime>? locationCapturedAt,
    Expression<String>? nearbyMessageId,
    Expression<DateTime>? readAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderId != null) 'sender_id': senderId,
      if (senderDeviceId != null) 'sender_device_id': senderDeviceId,
      if (messageType != null) 'message_type': messageType,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deliveryStatus != null) 'delivery_status': deliveryStatus,
      if (cloudSyncStatus != null) 'cloud_sync_status': cloudSyncStatus,
      if (isOutgoing != null) 'is_outgoing': isOutgoing,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracy != null) 'location_accuracy': locationAccuracy,
      if (locationCapturedAt != null)
        'location_captured_at': locationCapturedAt,
      if (nearbyMessageId != null) 'nearby_message_id': nearbyMessageId,
      if (readAt != null) 'read_at': readAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? senderId,
    Value<String?>? senderDeviceId,
    Value<String>? messageType,
    Value<String>? content,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? deliveryStatus,
    Value<String>? cloudSyncStatus,
    Value<bool>? isOutgoing,
    Value<String?>? localFilePath,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? locationAccuracy,
    Value<DateTime?>? locationCapturedAt,
    Value<String?>? nearbyMessageId,
    Value<DateTime?>? readAt,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      cloudSyncStatus: cloudSyncStatus ?? this.cloudSyncStatus,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      localFilePath: localFilePath ?? this.localFilePath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracy: locationAccuracy ?? this.locationAccuracy,
      locationCapturedAt: locationCapturedAt ?? this.locationCapturedAt,
      nearbyMessageId: nearbyMessageId ?? this.nearbyMessageId,
      readAt: readAt ?? this.readAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (senderDeviceId.present) {
      map['sender_device_id'] = Variable<String>(senderDeviceId.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deliveryStatus.present) {
      map['delivery_status'] = Variable<String>(deliveryStatus.value);
    }
    if (cloudSyncStatus.present) {
      map['cloud_sync_status'] = Variable<String>(cloudSyncStatus.value);
    }
    if (isOutgoing.present) {
      map['is_outgoing'] = Variable<bool>(isOutgoing.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (locationAccuracy.present) {
      map['location_accuracy'] = Variable<double>(locationAccuracy.value);
    }
    if (locationCapturedAt.present) {
      map['location_captured_at'] = Variable<DateTime>(
        locationCapturedAt.value,
      );
    }
    if (nearbyMessageId.present) {
      map['nearby_message_id'] = Variable<String>(nearbyMessageId.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('senderDeviceId: $senderDeviceId, ')
          ..write('messageType: $messageType, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deliveryStatus: $deliveryStatus, ')
          ..write('cloudSyncStatus: $cloudSyncStatus, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracy: $locationAccuracy, ')
          ..write('locationCapturedAt: $locationCapturedAt, ')
          ..write('nearbyMessageId: $nearbyMessageId, ')
          ..write('readAt: $readAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NearbyDevicesTable extends NearbyDevices
    with TableInfo<$NearbyDevicesTable, NearbyDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NearbyDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signalQualityMeta = const VerificationMeta(
    'signalQuality',
  );
  @override
  late final GeneratedColumn<int> signalQuality = GeneratedColumn<int>(
    'signal_quality',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _approxDistanceMeta = const VerificationMeta(
    'approxDistance',
  );
  @override
  late final GeneratedColumn<int> approxDistance = GeneratedColumn<int>(
    'approx_distance',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isTrustedMeta = const VerificationMeta(
    'isTrusted',
  );
  @override
  late final GeneratedColumn<bool> isTrusted = GeneratedColumn<bool>(
    'is_trusted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_trusted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isBlockedMeta = const VerificationMeta(
    'isBlocked',
  );
  @override
  late final GeneratedColumn<bool> isBlocked = GeneratedColumn<bool>(
    'is_blocked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_blocked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _autoReconnectEnabledMeta =
      const VerificationMeta('autoReconnectEnabled');
  @override
  late final GeneratedColumn<bool> autoReconnectEnabled = GeneratedColumn<bool>(
    'auto_reconnect_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_reconnect_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _publicIdentityKeyMeta = const VerificationMeta(
    'publicIdentityKey',
  );
  @override
  late final GeneratedColumn<String> publicIdentityKey =
      GeneratedColumn<String>(
        'public_identity_key',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _publicIdentityFingerprintMeta =
      const VerificationMeta('publicIdentityFingerprint');
  @override
  late final GeneratedColumn<String> publicIdentityFingerprint =
      GeneratedColumn<String>(
        'public_identity_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _batteryLevelMeta = const VerificationMeta(
    'batteryLevel',
  );
  @override
  late final GeneratedColumn<int> batteryLevel = GeneratedColumn<int>(
    'battery_level',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isChargingMeta = const VerificationMeta(
    'isCharging',
  );
  @override
  late final GeneratedColumn<bool> isCharging = GeneratedColumn<bool>(
    'is_charging',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_charging" IN (0, 1))',
    ),
  );
  static const VerificationMeta _batteryUpdatedAtMeta = const VerificationMeta(
    'batteryUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> batteryUpdatedAt =
      GeneratedColumn<DateTime>(
        'battery_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _peerLatitudeMeta = const VerificationMeta(
    'peerLatitude',
  );
  @override
  late final GeneratedColumn<double> peerLatitude = GeneratedColumn<double>(
    'peer_latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _peerLongitudeMeta = const VerificationMeta(
    'peerLongitude',
  );
  @override
  late final GeneratedColumn<double> peerLongitude = GeneratedColumn<double>(
    'peer_longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _peerLocationAccuracyMeta =
      const VerificationMeta('peerLocationAccuracy');
  @override
  late final GeneratedColumn<double> peerLocationAccuracy =
      GeneratedColumn<double>(
        'peer_location_accuracy',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _peerLocationCapturedAtMeta =
      const VerificationMeta('peerLocationCapturedAt');
  @override
  late final GeneratedColumn<DateTime> peerLocationCapturedAt =
      GeneratedColumn<DateTime>(
        'peer_location_captured_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _peerDeviceModelMeta = const VerificationMeta(
    'peerDeviceModel',
  );
  @override
  late final GeneratedColumn<String> peerDeviceModel = GeneratedColumn<String>(
    'peer_device_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    displayName,
    status,
    lastSeenAt,
    signalQuality,
    approxDistance,
    isTrusted,
    isBlocked,
    autoReconnectEnabled,
    publicIdentityKey,
    publicIdentityFingerprint,
    batteryLevel,
    isCharging,
    batteryUpdatedAt,
    peerLatitude,
    peerLongitude,
    peerLocationAccuracy,
    peerLocationCapturedAt,
    peerDeviceModel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nearby_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<NearbyDevice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSeenAtMeta);
    }
    if (data.containsKey('signal_quality')) {
      context.handle(
        _signalQualityMeta,
        signalQuality.isAcceptableOrUnknown(
          data['signal_quality']!,
          _signalQualityMeta,
        ),
      );
    }
    if (data.containsKey('approx_distance')) {
      context.handle(
        _approxDistanceMeta,
        approxDistance.isAcceptableOrUnknown(
          data['approx_distance']!,
          _approxDistanceMeta,
        ),
      );
    }
    if (data.containsKey('is_trusted')) {
      context.handle(
        _isTrustedMeta,
        isTrusted.isAcceptableOrUnknown(data['is_trusted']!, _isTrustedMeta),
      );
    }
    if (data.containsKey('is_blocked')) {
      context.handle(
        _isBlockedMeta,
        isBlocked.isAcceptableOrUnknown(data['is_blocked']!, _isBlockedMeta),
      );
    }
    if (data.containsKey('auto_reconnect_enabled')) {
      context.handle(
        _autoReconnectEnabledMeta,
        autoReconnectEnabled.isAcceptableOrUnknown(
          data['auto_reconnect_enabled']!,
          _autoReconnectEnabledMeta,
        ),
      );
    }
    if (data.containsKey('public_identity_key')) {
      context.handle(
        _publicIdentityKeyMeta,
        publicIdentityKey.isAcceptableOrUnknown(
          data['public_identity_key']!,
          _publicIdentityKeyMeta,
        ),
      );
    }
    if (data.containsKey('public_identity_fingerprint')) {
      context.handle(
        _publicIdentityFingerprintMeta,
        publicIdentityFingerprint.isAcceptableOrUnknown(
          data['public_identity_fingerprint']!,
          _publicIdentityFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('battery_level')) {
      context.handle(
        _batteryLevelMeta,
        batteryLevel.isAcceptableOrUnknown(
          data['battery_level']!,
          _batteryLevelMeta,
        ),
      );
    }
    if (data.containsKey('is_charging')) {
      context.handle(
        _isChargingMeta,
        isCharging.isAcceptableOrUnknown(data['is_charging']!, _isChargingMeta),
      );
    }
    if (data.containsKey('battery_updated_at')) {
      context.handle(
        _batteryUpdatedAtMeta,
        batteryUpdatedAt.isAcceptableOrUnknown(
          data['battery_updated_at']!,
          _batteryUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('peer_latitude')) {
      context.handle(
        _peerLatitudeMeta,
        peerLatitude.isAcceptableOrUnknown(
          data['peer_latitude']!,
          _peerLatitudeMeta,
        ),
      );
    }
    if (data.containsKey('peer_longitude')) {
      context.handle(
        _peerLongitudeMeta,
        peerLongitude.isAcceptableOrUnknown(
          data['peer_longitude']!,
          _peerLongitudeMeta,
        ),
      );
    }
    if (data.containsKey('peer_location_accuracy')) {
      context.handle(
        _peerLocationAccuracyMeta,
        peerLocationAccuracy.isAcceptableOrUnknown(
          data['peer_location_accuracy']!,
          _peerLocationAccuracyMeta,
        ),
      );
    }
    if (data.containsKey('peer_location_captured_at')) {
      context.handle(
        _peerLocationCapturedAtMeta,
        peerLocationCapturedAt.isAcceptableOrUnknown(
          data['peer_location_captured_at']!,
          _peerLocationCapturedAtMeta,
        ),
      );
    }
    if (data.containsKey('peer_device_model')) {
      context.handle(
        _peerDeviceModelMeta,
        peerDeviceModel.isAcceptableOrUnknown(
          data['peer_device_model']!,
          _peerDeviceModelMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  NearbyDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NearbyDevice(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
      signalQuality: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}signal_quality'],
      ),
      approxDistance: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}approx_distance'],
      ),
      isTrusted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_trusted'],
      )!,
      isBlocked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_blocked'],
      )!,
      autoReconnectEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_reconnect_enabled'],
      )!,
      publicIdentityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_identity_key'],
      ),
      publicIdentityFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_identity_fingerprint'],
      ),
      batteryLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}battery_level'],
      ),
      isCharging: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_charging'],
      ),
      batteryUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}battery_updated_at'],
      ),
      peerLatitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}peer_latitude'],
      ),
      peerLongitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}peer_longitude'],
      ),
      peerLocationAccuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}peer_location_accuracy'],
      ),
      peerLocationCapturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}peer_location_captured_at'],
      ),
      peerDeviceModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_device_model'],
      ),
    );
  }

  @override
  $NearbyDevicesTable createAlias(String alias) {
    return $NearbyDevicesTable(attachedDatabase, alias);
  }
}

class NearbyDevice extends DataClass implements Insertable<NearbyDevice> {
  final String deviceId;
  final String displayName;
  final String status;
  final DateTime lastSeenAt;
  final int? signalQuality;
  final int? approxDistance;
  final bool isTrusted;
  final bool isBlocked;
  final bool autoReconnectEnabled;
  final String? publicIdentityKey;
  final String? publicIdentityFingerprint;
  final int? batteryLevel;
  final bool? isCharging;
  final DateTime? batteryUpdatedAt;
  final double? peerLatitude;
  final double? peerLongitude;
  final double? peerLocationAccuracy;
  final DateTime? peerLocationCapturedAt;
  final String? peerDeviceModel;
  const NearbyDevice({
    required this.deviceId,
    required this.displayName,
    required this.status,
    required this.lastSeenAt,
    this.signalQuality,
    this.approxDistance,
    required this.isTrusted,
    required this.isBlocked,
    required this.autoReconnectEnabled,
    this.publicIdentityKey,
    this.publicIdentityFingerprint,
    this.batteryLevel,
    this.isCharging,
    this.batteryUpdatedAt,
    this.peerLatitude,
    this.peerLongitude,
    this.peerLocationAccuracy,
    this.peerLocationCapturedAt,
    this.peerDeviceModel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['display_name'] = Variable<String>(displayName);
    map['status'] = Variable<String>(status);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    if (!nullToAbsent || signalQuality != null) {
      map['signal_quality'] = Variable<int>(signalQuality);
    }
    if (!nullToAbsent || approxDistance != null) {
      map['approx_distance'] = Variable<int>(approxDistance);
    }
    map['is_trusted'] = Variable<bool>(isTrusted);
    map['is_blocked'] = Variable<bool>(isBlocked);
    map['auto_reconnect_enabled'] = Variable<bool>(autoReconnectEnabled);
    if (!nullToAbsent || publicIdentityKey != null) {
      map['public_identity_key'] = Variable<String>(publicIdentityKey);
    }
    if (!nullToAbsent || publicIdentityFingerprint != null) {
      map['public_identity_fingerprint'] = Variable<String>(
        publicIdentityFingerprint,
      );
    }
    if (!nullToAbsent || batteryLevel != null) {
      map['battery_level'] = Variable<int>(batteryLevel);
    }
    if (!nullToAbsent || isCharging != null) {
      map['is_charging'] = Variable<bool>(isCharging);
    }
    if (!nullToAbsent || batteryUpdatedAt != null) {
      map['battery_updated_at'] = Variable<DateTime>(batteryUpdatedAt);
    }
    if (!nullToAbsent || peerLatitude != null) {
      map['peer_latitude'] = Variable<double>(peerLatitude);
    }
    if (!nullToAbsent || peerLongitude != null) {
      map['peer_longitude'] = Variable<double>(peerLongitude);
    }
    if (!nullToAbsent || peerLocationAccuracy != null) {
      map['peer_location_accuracy'] = Variable<double>(peerLocationAccuracy);
    }
    if (!nullToAbsent || peerLocationCapturedAt != null) {
      map['peer_location_captured_at'] = Variable<DateTime>(
        peerLocationCapturedAt,
      );
    }
    if (!nullToAbsent || peerDeviceModel != null) {
      map['peer_device_model'] = Variable<String>(peerDeviceModel);
    }
    return map;
  }

  NearbyDevicesCompanion toCompanion(bool nullToAbsent) {
    return NearbyDevicesCompanion(
      deviceId: Value(deviceId),
      displayName: Value(displayName),
      status: Value(status),
      lastSeenAt: Value(lastSeenAt),
      signalQuality: signalQuality == null && nullToAbsent
          ? const Value.absent()
          : Value(signalQuality),
      approxDistance: approxDistance == null && nullToAbsent
          ? const Value.absent()
          : Value(approxDistance),
      isTrusted: Value(isTrusted),
      isBlocked: Value(isBlocked),
      autoReconnectEnabled: Value(autoReconnectEnabled),
      publicIdentityKey: publicIdentityKey == null && nullToAbsent
          ? const Value.absent()
          : Value(publicIdentityKey),
      publicIdentityFingerprint:
          publicIdentityFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(publicIdentityFingerprint),
      batteryLevel: batteryLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryLevel),
      isCharging: isCharging == null && nullToAbsent
          ? const Value.absent()
          : Value(isCharging),
      batteryUpdatedAt: batteryUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryUpdatedAt),
      peerLatitude: peerLatitude == null && nullToAbsent
          ? const Value.absent()
          : Value(peerLatitude),
      peerLongitude: peerLongitude == null && nullToAbsent
          ? const Value.absent()
          : Value(peerLongitude),
      peerLocationAccuracy: peerLocationAccuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(peerLocationAccuracy),
      peerLocationCapturedAt: peerLocationCapturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(peerLocationCapturedAt),
      peerDeviceModel: peerDeviceModel == null && nullToAbsent
          ? const Value.absent()
          : Value(peerDeviceModel),
    );
  }

  factory NearbyDevice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NearbyDevice(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      status: serializer.fromJson<String>(json['status']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
      signalQuality: serializer.fromJson<int?>(json['signalQuality']),
      approxDistance: serializer.fromJson<int?>(json['approxDistance']),
      isTrusted: serializer.fromJson<bool>(json['isTrusted']),
      isBlocked: serializer.fromJson<bool>(json['isBlocked']),
      autoReconnectEnabled: serializer.fromJson<bool>(
        json['autoReconnectEnabled'],
      ),
      publicIdentityKey: serializer.fromJson<String?>(
        json['publicIdentityKey'],
      ),
      publicIdentityFingerprint: serializer.fromJson<String?>(
        json['publicIdentityFingerprint'],
      ),
      batteryLevel: serializer.fromJson<int?>(json['batteryLevel']),
      isCharging: serializer.fromJson<bool?>(json['isCharging']),
      batteryUpdatedAt: serializer.fromJson<DateTime?>(
        json['batteryUpdatedAt'],
      ),
      peerLatitude: serializer.fromJson<double?>(json['peerLatitude']),
      peerLongitude: serializer.fromJson<double?>(json['peerLongitude']),
      peerLocationAccuracy: serializer.fromJson<double?>(
        json['peerLocationAccuracy'],
      ),
      peerLocationCapturedAt: serializer.fromJson<DateTime?>(
        json['peerLocationCapturedAt'],
      ),
      peerDeviceModel: serializer.fromJson<String?>(json['peerDeviceModel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'displayName': serializer.toJson<String>(displayName),
      'status': serializer.toJson<String>(status),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
      'signalQuality': serializer.toJson<int?>(signalQuality),
      'approxDistance': serializer.toJson<int?>(approxDistance),
      'isTrusted': serializer.toJson<bool>(isTrusted),
      'isBlocked': serializer.toJson<bool>(isBlocked),
      'autoReconnectEnabled': serializer.toJson<bool>(autoReconnectEnabled),
      'publicIdentityKey': serializer.toJson<String?>(publicIdentityKey),
      'publicIdentityFingerprint': serializer.toJson<String?>(
        publicIdentityFingerprint,
      ),
      'batteryLevel': serializer.toJson<int?>(batteryLevel),
      'isCharging': serializer.toJson<bool?>(isCharging),
      'batteryUpdatedAt': serializer.toJson<DateTime?>(batteryUpdatedAt),
      'peerLatitude': serializer.toJson<double?>(peerLatitude),
      'peerLongitude': serializer.toJson<double?>(peerLongitude),
      'peerLocationAccuracy': serializer.toJson<double?>(peerLocationAccuracy),
      'peerLocationCapturedAt': serializer.toJson<DateTime?>(
        peerLocationCapturedAt,
      ),
      'peerDeviceModel': serializer.toJson<String?>(peerDeviceModel),
    };
  }

  NearbyDevice copyWith({
    String? deviceId,
    String? displayName,
    String? status,
    DateTime? lastSeenAt,
    Value<int?> signalQuality = const Value.absent(),
    Value<int?> approxDistance = const Value.absent(),
    bool? isTrusted,
    bool? isBlocked,
    bool? autoReconnectEnabled,
    Value<String?> publicIdentityKey = const Value.absent(),
    Value<String?> publicIdentityFingerprint = const Value.absent(),
    Value<int?> batteryLevel = const Value.absent(),
    Value<bool?> isCharging = const Value.absent(),
    Value<DateTime?> batteryUpdatedAt = const Value.absent(),
    Value<double?> peerLatitude = const Value.absent(),
    Value<double?> peerLongitude = const Value.absent(),
    Value<double?> peerLocationAccuracy = const Value.absent(),
    Value<DateTime?> peerLocationCapturedAt = const Value.absent(),
    Value<String?> peerDeviceModel = const Value.absent(),
  }) => NearbyDevice(
    deviceId: deviceId ?? this.deviceId,
    displayName: displayName ?? this.displayName,
    status: status ?? this.status,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    signalQuality: signalQuality.present
        ? signalQuality.value
        : this.signalQuality,
    approxDistance: approxDistance.present
        ? approxDistance.value
        : this.approxDistance,
    isTrusted: isTrusted ?? this.isTrusted,
    isBlocked: isBlocked ?? this.isBlocked,
    autoReconnectEnabled: autoReconnectEnabled ?? this.autoReconnectEnabled,
    publicIdentityKey: publicIdentityKey.present
        ? publicIdentityKey.value
        : this.publicIdentityKey,
    publicIdentityFingerprint: publicIdentityFingerprint.present
        ? publicIdentityFingerprint.value
        : this.publicIdentityFingerprint,
    batteryLevel: batteryLevel.present ? batteryLevel.value : this.batteryLevel,
    isCharging: isCharging.present ? isCharging.value : this.isCharging,
    batteryUpdatedAt: batteryUpdatedAt.present
        ? batteryUpdatedAt.value
        : this.batteryUpdatedAt,
    peerLatitude: peerLatitude.present ? peerLatitude.value : this.peerLatitude,
    peerLongitude: peerLongitude.present
        ? peerLongitude.value
        : this.peerLongitude,
    peerLocationAccuracy: peerLocationAccuracy.present
        ? peerLocationAccuracy.value
        : this.peerLocationAccuracy,
    peerLocationCapturedAt: peerLocationCapturedAt.present
        ? peerLocationCapturedAt.value
        : this.peerLocationCapturedAt,
    peerDeviceModel: peerDeviceModel.present
        ? peerDeviceModel.value
        : this.peerDeviceModel,
  );
  NearbyDevice copyWithCompanion(NearbyDevicesCompanion data) {
    return NearbyDevice(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      status: data.status.present ? data.status.value : this.status,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      signalQuality: data.signalQuality.present
          ? data.signalQuality.value
          : this.signalQuality,
      approxDistance: data.approxDistance.present
          ? data.approxDistance.value
          : this.approxDistance,
      isTrusted: data.isTrusted.present ? data.isTrusted.value : this.isTrusted,
      isBlocked: data.isBlocked.present ? data.isBlocked.value : this.isBlocked,
      autoReconnectEnabled: data.autoReconnectEnabled.present
          ? data.autoReconnectEnabled.value
          : this.autoReconnectEnabled,
      publicIdentityKey: data.publicIdentityKey.present
          ? data.publicIdentityKey.value
          : this.publicIdentityKey,
      publicIdentityFingerprint: data.publicIdentityFingerprint.present
          ? data.publicIdentityFingerprint.value
          : this.publicIdentityFingerprint,
      batteryLevel: data.batteryLevel.present
          ? data.batteryLevel.value
          : this.batteryLevel,
      isCharging: data.isCharging.present
          ? data.isCharging.value
          : this.isCharging,
      batteryUpdatedAt: data.batteryUpdatedAt.present
          ? data.batteryUpdatedAt.value
          : this.batteryUpdatedAt,
      peerLatitude: data.peerLatitude.present
          ? data.peerLatitude.value
          : this.peerLatitude,
      peerLongitude: data.peerLongitude.present
          ? data.peerLongitude.value
          : this.peerLongitude,
      peerLocationAccuracy: data.peerLocationAccuracy.present
          ? data.peerLocationAccuracy.value
          : this.peerLocationAccuracy,
      peerLocationCapturedAt: data.peerLocationCapturedAt.present
          ? data.peerLocationCapturedAt.value
          : this.peerLocationCapturedAt,
      peerDeviceModel: data.peerDeviceModel.present
          ? data.peerDeviceModel.value
          : this.peerDeviceModel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NearbyDevice(')
          ..write('deviceId: $deviceId, ')
          ..write('displayName: $displayName, ')
          ..write('status: $status, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('signalQuality: $signalQuality, ')
          ..write('approxDistance: $approxDistance, ')
          ..write('isTrusted: $isTrusted, ')
          ..write('isBlocked: $isBlocked, ')
          ..write('autoReconnectEnabled: $autoReconnectEnabled, ')
          ..write('publicIdentityKey: $publicIdentityKey, ')
          ..write('publicIdentityFingerprint: $publicIdentityFingerprint, ')
          ..write('batteryLevel: $batteryLevel, ')
          ..write('isCharging: $isCharging, ')
          ..write('batteryUpdatedAt: $batteryUpdatedAt, ')
          ..write('peerLatitude: $peerLatitude, ')
          ..write('peerLongitude: $peerLongitude, ')
          ..write('peerLocationAccuracy: $peerLocationAccuracy, ')
          ..write('peerLocationCapturedAt: $peerLocationCapturedAt, ')
          ..write('peerDeviceModel: $peerDeviceModel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    displayName,
    status,
    lastSeenAt,
    signalQuality,
    approxDistance,
    isTrusted,
    isBlocked,
    autoReconnectEnabled,
    publicIdentityKey,
    publicIdentityFingerprint,
    batteryLevel,
    isCharging,
    batteryUpdatedAt,
    peerLatitude,
    peerLongitude,
    peerLocationAccuracy,
    peerLocationCapturedAt,
    peerDeviceModel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NearbyDevice &&
          other.deviceId == this.deviceId &&
          other.displayName == this.displayName &&
          other.status == this.status &&
          other.lastSeenAt == this.lastSeenAt &&
          other.signalQuality == this.signalQuality &&
          other.approxDistance == this.approxDistance &&
          other.isTrusted == this.isTrusted &&
          other.isBlocked == this.isBlocked &&
          other.autoReconnectEnabled == this.autoReconnectEnabled &&
          other.publicIdentityKey == this.publicIdentityKey &&
          other.publicIdentityFingerprint == this.publicIdentityFingerprint &&
          other.batteryLevel == this.batteryLevel &&
          other.isCharging == this.isCharging &&
          other.batteryUpdatedAt == this.batteryUpdatedAt &&
          other.peerLatitude == this.peerLatitude &&
          other.peerLongitude == this.peerLongitude &&
          other.peerLocationAccuracy == this.peerLocationAccuracy &&
          other.peerLocationCapturedAt == this.peerLocationCapturedAt &&
          other.peerDeviceModel == this.peerDeviceModel);
}

class NearbyDevicesCompanion extends UpdateCompanion<NearbyDevice> {
  final Value<String> deviceId;
  final Value<String> displayName;
  final Value<String> status;
  final Value<DateTime> lastSeenAt;
  final Value<int?> signalQuality;
  final Value<int?> approxDistance;
  final Value<bool> isTrusted;
  final Value<bool> isBlocked;
  final Value<bool> autoReconnectEnabled;
  final Value<String?> publicIdentityKey;
  final Value<String?> publicIdentityFingerprint;
  final Value<int?> batteryLevel;
  final Value<bool?> isCharging;
  final Value<DateTime?> batteryUpdatedAt;
  final Value<double?> peerLatitude;
  final Value<double?> peerLongitude;
  final Value<double?> peerLocationAccuracy;
  final Value<DateTime?> peerLocationCapturedAt;
  final Value<String?> peerDeviceModel;
  final Value<int> rowid;
  const NearbyDevicesCompanion({
    this.deviceId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.status = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.signalQuality = const Value.absent(),
    this.approxDistance = const Value.absent(),
    this.isTrusted = const Value.absent(),
    this.isBlocked = const Value.absent(),
    this.autoReconnectEnabled = const Value.absent(),
    this.publicIdentityKey = const Value.absent(),
    this.publicIdentityFingerprint = const Value.absent(),
    this.batteryLevel = const Value.absent(),
    this.isCharging = const Value.absent(),
    this.batteryUpdatedAt = const Value.absent(),
    this.peerLatitude = const Value.absent(),
    this.peerLongitude = const Value.absent(),
    this.peerLocationAccuracy = const Value.absent(),
    this.peerLocationCapturedAt = const Value.absent(),
    this.peerDeviceModel = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NearbyDevicesCompanion.insert({
    required String deviceId,
    required String displayName,
    required String status,
    required DateTime lastSeenAt,
    this.signalQuality = const Value.absent(),
    this.approxDistance = const Value.absent(),
    this.isTrusted = const Value.absent(),
    this.isBlocked = const Value.absent(),
    this.autoReconnectEnabled = const Value.absent(),
    this.publicIdentityKey = const Value.absent(),
    this.publicIdentityFingerprint = const Value.absent(),
    this.batteryLevel = const Value.absent(),
    this.isCharging = const Value.absent(),
    this.batteryUpdatedAt = const Value.absent(),
    this.peerLatitude = const Value.absent(),
    this.peerLongitude = const Value.absent(),
    this.peerLocationAccuracy = const Value.absent(),
    this.peerLocationCapturedAt = const Value.absent(),
    this.peerDeviceModel = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       displayName = Value(displayName),
       status = Value(status),
       lastSeenAt = Value(lastSeenAt);
  static Insertable<NearbyDevice> custom({
    Expression<String>? deviceId,
    Expression<String>? displayName,
    Expression<String>? status,
    Expression<DateTime>? lastSeenAt,
    Expression<int>? signalQuality,
    Expression<int>? approxDistance,
    Expression<bool>? isTrusted,
    Expression<bool>? isBlocked,
    Expression<bool>? autoReconnectEnabled,
    Expression<String>? publicIdentityKey,
    Expression<String>? publicIdentityFingerprint,
    Expression<int>? batteryLevel,
    Expression<bool>? isCharging,
    Expression<DateTime>? batteryUpdatedAt,
    Expression<double>? peerLatitude,
    Expression<double>? peerLongitude,
    Expression<double>? peerLocationAccuracy,
    Expression<DateTime>? peerLocationCapturedAt,
    Expression<String>? peerDeviceModel,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (displayName != null) 'display_name': displayName,
      if (status != null) 'status': status,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (signalQuality != null) 'signal_quality': signalQuality,
      if (approxDistance != null) 'approx_distance': approxDistance,
      if (isTrusted != null) 'is_trusted': isTrusted,
      if (isBlocked != null) 'is_blocked': isBlocked,
      if (autoReconnectEnabled != null)
        'auto_reconnect_enabled': autoReconnectEnabled,
      if (publicIdentityKey != null) 'public_identity_key': publicIdentityKey,
      if (publicIdentityFingerprint != null)
        'public_identity_fingerprint': publicIdentityFingerprint,
      if (batteryLevel != null) 'battery_level': batteryLevel,
      if (isCharging != null) 'is_charging': isCharging,
      if (batteryUpdatedAt != null) 'battery_updated_at': batteryUpdatedAt,
      if (peerLatitude != null) 'peer_latitude': peerLatitude,
      if (peerLongitude != null) 'peer_longitude': peerLongitude,
      if (peerLocationAccuracy != null)
        'peer_location_accuracy': peerLocationAccuracy,
      if (peerLocationCapturedAt != null)
        'peer_location_captured_at': peerLocationCapturedAt,
      if (peerDeviceModel != null) 'peer_device_model': peerDeviceModel,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NearbyDevicesCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? displayName,
    Value<String>? status,
    Value<DateTime>? lastSeenAt,
    Value<int?>? signalQuality,
    Value<int?>? approxDistance,
    Value<bool>? isTrusted,
    Value<bool>? isBlocked,
    Value<bool>? autoReconnectEnabled,
    Value<String?>? publicIdentityKey,
    Value<String?>? publicIdentityFingerprint,
    Value<int?>? batteryLevel,
    Value<bool?>? isCharging,
    Value<DateTime?>? batteryUpdatedAt,
    Value<double?>? peerLatitude,
    Value<double?>? peerLongitude,
    Value<double?>? peerLocationAccuracy,
    Value<DateTime?>? peerLocationCapturedAt,
    Value<String?>? peerDeviceModel,
    Value<int>? rowid,
  }) {
    return NearbyDevicesCompanion(
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      signalQuality: signalQuality ?? this.signalQuality,
      approxDistance: approxDistance ?? this.approxDistance,
      isTrusted: isTrusted ?? this.isTrusted,
      isBlocked: isBlocked ?? this.isBlocked,
      autoReconnectEnabled: autoReconnectEnabled ?? this.autoReconnectEnabled,
      publicIdentityKey: publicIdentityKey ?? this.publicIdentityKey,
      publicIdentityFingerprint:
          publicIdentityFingerprint ?? this.publicIdentityFingerprint,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      batteryUpdatedAt: batteryUpdatedAt ?? this.batteryUpdatedAt,
      peerLatitude: peerLatitude ?? this.peerLatitude,
      peerLongitude: peerLongitude ?? this.peerLongitude,
      peerLocationAccuracy: peerLocationAccuracy ?? this.peerLocationAccuracy,
      peerLocationCapturedAt:
          peerLocationCapturedAt ?? this.peerLocationCapturedAt,
      peerDeviceModel: peerDeviceModel ?? this.peerDeviceModel,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (signalQuality.present) {
      map['signal_quality'] = Variable<int>(signalQuality.value);
    }
    if (approxDistance.present) {
      map['approx_distance'] = Variable<int>(approxDistance.value);
    }
    if (isTrusted.present) {
      map['is_trusted'] = Variable<bool>(isTrusted.value);
    }
    if (isBlocked.present) {
      map['is_blocked'] = Variable<bool>(isBlocked.value);
    }
    if (autoReconnectEnabled.present) {
      map['auto_reconnect_enabled'] = Variable<bool>(
        autoReconnectEnabled.value,
      );
    }
    if (publicIdentityKey.present) {
      map['public_identity_key'] = Variable<String>(publicIdentityKey.value);
    }
    if (publicIdentityFingerprint.present) {
      map['public_identity_fingerprint'] = Variable<String>(
        publicIdentityFingerprint.value,
      );
    }
    if (batteryLevel.present) {
      map['battery_level'] = Variable<int>(batteryLevel.value);
    }
    if (isCharging.present) {
      map['is_charging'] = Variable<bool>(isCharging.value);
    }
    if (batteryUpdatedAt.present) {
      map['battery_updated_at'] = Variable<DateTime>(batteryUpdatedAt.value);
    }
    if (peerLatitude.present) {
      map['peer_latitude'] = Variable<double>(peerLatitude.value);
    }
    if (peerLongitude.present) {
      map['peer_longitude'] = Variable<double>(peerLongitude.value);
    }
    if (peerLocationAccuracy.present) {
      map['peer_location_accuracy'] = Variable<double>(
        peerLocationAccuracy.value,
      );
    }
    if (peerLocationCapturedAt.present) {
      map['peer_location_captured_at'] = Variable<DateTime>(
        peerLocationCapturedAt.value,
      );
    }
    if (peerDeviceModel.present) {
      map['peer_device_model'] = Variable<String>(peerDeviceModel.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NearbyDevicesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('displayName: $displayName, ')
          ..write('status: $status, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('signalQuality: $signalQuality, ')
          ..write('approxDistance: $approxDistance, ')
          ..write('isTrusted: $isTrusted, ')
          ..write('isBlocked: $isBlocked, ')
          ..write('autoReconnectEnabled: $autoReconnectEnabled, ')
          ..write('publicIdentityKey: $publicIdentityKey, ')
          ..write('publicIdentityFingerprint: $publicIdentityFingerprint, ')
          ..write('batteryLevel: $batteryLevel, ')
          ..write('isCharging: $isCharging, ')
          ..write('batteryUpdatedAt: $batteryUpdatedAt, ')
          ..write('peerLatitude: $peerLatitude, ')
          ..write('peerLongitude: $peerLongitude, ')
          ..write('peerLocationAccuracy: $peerLocationAccuracy, ')
          ..write('peerLocationCapturedAt: $peerLocationCapturedAt, ')
          ..write('peerDeviceModel: $peerDeviceModel, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueTable extends SyncQueue
    with TableInfo<$SyncQueueTable, SyncQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    operation,
    status,
    attemptCount,
    lastError,
    createdAt,
    updatedAt,
    nextAttemptAt,
    ownerUserId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncQueueData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      ),
    );
  }

  @override
  $SyncQueueTable createAlias(String alias) {
    return $SyncQueueTable(attachedDatabase, alias);
  }
}

class SyncQueueData extends DataClass implements Insertable<SyncQueueData> {
  final String id;
  final String entityType;
  final String entityId;
  final String operation;
  final String status;
  final int attemptCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextAttemptAt;
  final String? ownerUserId;
  const SyncQueueData({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.status,
    required this.attemptCount,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
    this.nextAttemptAt,
    this.ownerUserId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || ownerUserId != null) {
      map['owner_user_id'] = Variable<String>(ownerUserId);
    }
    return map;
  }

  SyncQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      status: Value(status),
      attemptCount: Value(attemptCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      ownerUserId: ownerUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerUserId),
    );
  }

  factory SyncQueueData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueData(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      ownerUserId: serializer.fromJson<String?>(json['ownerUserId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'ownerUserId': serializer.toJson<String?>(ownerUserId),
    };
  }

  SyncQueueData copyWith({
    String? id,
    String? entityType,
    String? entityId,
    String? operation,
    String? status,
    int? attemptCount,
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> ownerUserId = const Value.absent(),
  }) => SyncQueueData(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    ownerUserId: ownerUserId.present ? ownerUserId.value : this.ownerUserId,
  );
  SyncQueueData copyWithCompanion(SyncQueueCompanion data) {
    return SyncQueueData(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueData(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('ownerUserId: $ownerUserId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    operation,
    status,
    attemptCount,
    lastError,
    createdAt,
    updatedAt,
    nextAttemptAt,
    ownerUserId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueData &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.ownerUserId == this.ownerUserId);
}

class SyncQueueCompanion extends UpdateCompanion<SyncQueueData> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> ownerUserId;
  final Value<int> rowid;
  const SyncQueueCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.ownerUserId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncQueueCompanion.insert({
    required String id,
    required String entityType,
    required String entityId,
    required String operation,
    required String status,
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.nextAttemptAt = const Value.absent(),
    this.ownerUserId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SyncQueueData> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? ownerUserId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncQueueCompanion copyWith({
    Value<String>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? ownerUserId,
    Value<int>? rowid,
  }) {
    return SyncQueueCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SosEventsTable extends SosEvents
    with TableInfo<$SosEventsTable, SosEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SosEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerDeviceIdMeta = const VerificationMeta(
    'ownerDeviceId',
  );
  @override
  late final GeneratedColumn<String> ownerDeviceId = GeneratedColumn<String>(
    'owner_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationAccuracyMeta = const VerificationMeta(
    'locationAccuracy',
  );
  @override
  late final GeneratedColumn<double> locationAccuracy = GeneratedColumn<double>(
    'location_accuracy',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationCapturedAtMeta =
      const VerificationMeta('locationCapturedAt');
  @override
  late final GeneratedColumn<DateTime> locationCapturedAt =
      GeneratedColumn<DateTime>(
        'location_captured_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
  );
  static const VerificationMeta _deliveryStatusMeta = const VerificationMeta(
    'deliveryStatus',
  );
  @override
  late final GeneratedColumn<String> deliveryStatus = GeneratedColumn<String>(
    'delivery_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerDeviceId,
    ownerUserId,
    message,
    latitude,
    longitude,
    locationAccuracy,
    locationCapturedAt,
    createdAt,
    updatedAt,
    isActive,
    deliveryStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sos_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<SosEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_device_id')) {
      context.handle(
        _ownerDeviceIdMeta,
        ownerDeviceId.isAcceptableOrUnknown(
          data['owner_device_id']!,
          _ownerDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerDeviceIdMeta);
    }
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('location_accuracy')) {
      context.handle(
        _locationAccuracyMeta,
        locationAccuracy.isAcceptableOrUnknown(
          data['location_accuracy']!,
          _locationAccuracyMeta,
        ),
      );
    }
    if (data.containsKey('location_captured_at')) {
      context.handle(
        _locationCapturedAtMeta,
        locationCapturedAt.isAcceptableOrUnknown(
          data['location_captured_at']!,
          _locationCapturedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    } else if (isInserting) {
      context.missing(_isActiveMeta);
    }
    if (data.containsKey('delivery_status')) {
      context.handle(
        _deliveryStatusMeta,
        deliveryStatus.isAcceptableOrUnknown(
          data['delivery_status']!,
          _deliveryStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deliveryStatusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SosEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SosEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_device_id'],
      )!,
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      locationAccuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}location_accuracy'],
      ),
      locationCapturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}location_captured_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      deliveryStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_status'],
      )!,
    );
  }

  @override
  $SosEventsTable createAlias(String alias) {
    return $SosEventsTable(attachedDatabase, alias);
  }
}

class SosEvent extends DataClass implements Insertable<SosEvent> {
  final String id;
  final String ownerDeviceId;
  final String ownerUserId;
  final String? message;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracy;
  final DateTime? locationCapturedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final String deliveryStatus;
  const SosEvent({
    required this.id,
    required this.ownerDeviceId,
    required this.ownerUserId,
    this.message,
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    this.locationCapturedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    required this.deliveryStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_device_id'] = Variable<String>(ownerDeviceId);
    map['owner_user_id'] = Variable<String>(ownerUserId);
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || locationAccuracy != null) {
      map['location_accuracy'] = Variable<double>(locationAccuracy);
    }
    if (!nullToAbsent || locationCapturedAt != null) {
      map['location_captured_at'] = Variable<DateTime>(locationCapturedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_active'] = Variable<bool>(isActive);
    map['delivery_status'] = Variable<String>(deliveryStatus);
    return map;
  }

  SosEventsCompanion toCompanion(bool nullToAbsent) {
    return SosEventsCompanion(
      id: Value(id),
      ownerDeviceId: Value(ownerDeviceId),
      ownerUserId: Value(ownerUserId),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      locationAccuracy: locationAccuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(locationAccuracy),
      locationCapturedAt: locationCapturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(locationCapturedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isActive: Value(isActive),
      deliveryStatus: Value(deliveryStatus),
    );
  }

  factory SosEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SosEvent(
      id: serializer.fromJson<String>(json['id']),
      ownerDeviceId: serializer.fromJson<String>(json['ownerDeviceId']),
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      message: serializer.fromJson<String?>(json['message']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      locationAccuracy: serializer.fromJson<double?>(json['locationAccuracy']),
      locationCapturedAt: serializer.fromJson<DateTime?>(
        json['locationCapturedAt'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      deliveryStatus: serializer.fromJson<String>(json['deliveryStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerDeviceId': serializer.toJson<String>(ownerDeviceId),
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'message': serializer.toJson<String?>(message),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'locationAccuracy': serializer.toJson<double?>(locationAccuracy),
      'locationCapturedAt': serializer.toJson<DateTime?>(locationCapturedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isActive': serializer.toJson<bool>(isActive),
      'deliveryStatus': serializer.toJson<String>(deliveryStatus),
    };
  }

  SosEvent copyWith({
    String? id,
    String? ownerDeviceId,
    String? ownerUserId,
    Value<String?> message = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> locationAccuracy = const Value.absent(),
    Value<DateTime?> locationCapturedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    String? deliveryStatus,
  }) => SosEvent(
    id: id ?? this.id,
    ownerDeviceId: ownerDeviceId ?? this.ownerDeviceId,
    ownerUserId: ownerUserId ?? this.ownerUserId,
    message: message.present ? message.value : this.message,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    locationAccuracy: locationAccuracy.present
        ? locationAccuracy.value
        : this.locationAccuracy,
    locationCapturedAt: locationCapturedAt.present
        ? locationCapturedAt.value
        : this.locationCapturedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isActive: isActive ?? this.isActive,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
  );
  SosEvent copyWithCompanion(SosEventsCompanion data) {
    return SosEvent(
      id: data.id.present ? data.id.value : this.id,
      ownerDeviceId: data.ownerDeviceId.present
          ? data.ownerDeviceId.value
          : this.ownerDeviceId,
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      message: data.message.present ? data.message.value : this.message,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      locationAccuracy: data.locationAccuracy.present
          ? data.locationAccuracy.value
          : this.locationAccuracy,
      locationCapturedAt: data.locationCapturedAt.present
          ? data.locationCapturedAt.value
          : this.locationCapturedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      deliveryStatus: data.deliveryStatus.present
          ? data.deliveryStatus.value
          : this.deliveryStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SosEvent(')
          ..write('id: $id, ')
          ..write('ownerDeviceId: $ownerDeviceId, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('message: $message, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracy: $locationAccuracy, ')
          ..write('locationCapturedAt: $locationCapturedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isActive: $isActive, ')
          ..write('deliveryStatus: $deliveryStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerDeviceId,
    ownerUserId,
    message,
    latitude,
    longitude,
    locationAccuracy,
    locationCapturedAt,
    createdAt,
    updatedAt,
    isActive,
    deliveryStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SosEvent &&
          other.id == this.id &&
          other.ownerDeviceId == this.ownerDeviceId &&
          other.ownerUserId == this.ownerUserId &&
          other.message == this.message &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.locationAccuracy == this.locationAccuracy &&
          other.locationCapturedAt == this.locationCapturedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isActive == this.isActive &&
          other.deliveryStatus == this.deliveryStatus);
}

class SosEventsCompanion extends UpdateCompanion<SosEvent> {
  final Value<String> id;
  final Value<String> ownerDeviceId;
  final Value<String> ownerUserId;
  final Value<String?> message;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> locationAccuracy;
  final Value<DateTime?> locationCapturedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isActive;
  final Value<String> deliveryStatus;
  final Value<int> rowid;
  const SosEventsCompanion({
    this.id = const Value.absent(),
    this.ownerDeviceId = const Value.absent(),
    this.ownerUserId = const Value.absent(),
    this.message = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracy = const Value.absent(),
    this.locationCapturedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.deliveryStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SosEventsCompanion.insert({
    required String id,
    required String ownerDeviceId,
    required String ownerUserId,
    this.message = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracy = const Value.absent(),
    this.locationCapturedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    required bool isActive,
    required String deliveryStatus,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerDeviceId = Value(ownerDeviceId),
       ownerUserId = Value(ownerUserId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       isActive = Value(isActive),
       deliveryStatus = Value(deliveryStatus);
  static Insertable<SosEvent> custom({
    Expression<String>? id,
    Expression<String>? ownerDeviceId,
    Expression<String>? ownerUserId,
    Expression<String>? message,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? locationAccuracy,
    Expression<DateTime>? locationCapturedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isActive,
    Expression<String>? deliveryStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerDeviceId != null) 'owner_device_id': ownerDeviceId,
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (message != null) 'message': message,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracy != null) 'location_accuracy': locationAccuracy,
      if (locationCapturedAt != null)
        'location_captured_at': locationCapturedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isActive != null) 'is_active': isActive,
      if (deliveryStatus != null) 'delivery_status': deliveryStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SosEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerDeviceId,
    Value<String>? ownerUserId,
    Value<String?>? message,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? locationAccuracy,
    Value<DateTime?>? locationCapturedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isActive,
    Value<String>? deliveryStatus,
    Value<int>? rowid,
  }) {
    return SosEventsCompanion(
      id: id ?? this.id,
      ownerDeviceId: ownerDeviceId ?? this.ownerDeviceId,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      message: message ?? this.message,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracy: locationAccuracy ?? this.locationAccuracy,
      locationCapturedAt: locationCapturedAt ?? this.locationCapturedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerDeviceId.present) {
      map['owner_device_id'] = Variable<String>(ownerDeviceId.value);
    }
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (locationAccuracy.present) {
      map['location_accuracy'] = Variable<double>(locationAccuracy.value);
    }
    if (locationCapturedAt.present) {
      map['location_captured_at'] = Variable<DateTime>(
        locationCapturedAt.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (deliveryStatus.present) {
      map['delivery_status'] = Variable<String>(deliveryStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SosEventsCompanion(')
          ..write('id: $id, ')
          ..write('ownerDeviceId: $ownerDeviceId, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('message: $message, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracy: $locationAccuracy, ')
          ..write('locationCapturedAt: $locationCapturedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isActive: $isActive, ')
          ..write('deliveryStatus: $deliveryStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSetting copyWith({String? key, String? value, DateTime? updatedAt}) =>
      AppSetting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentsTable extends Attachments
    with TableInfo<$AttachmentsTable, Attachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transferIdMeta = const VerificationMeta(
    'transferId',
  );
  @override
  late final GeneratedColumn<String> transferId = GeneratedColumn<String>(
    'transfer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteFileNameMeta = const VerificationMeta(
    'remoteFileName',
  );
  @override
  late final GeneratedColumn<String> remoteFileName = GeneratedColumn<String>(
    'remote_file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesTransferredMeta = const VerificationMeta(
    'bytesTransferred',
  );
  @override
  late final GeneratedColumn<int> bytesTransferred = GeneratedColumn<int>(
    'bytes_transferred',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _transferStatusMeta = const VerificationMeta(
    'transferStatus',
  );
  @override
  late final GeneratedColumn<String> transferStatus = GeneratedColumn<String>(
    'transfer_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cloudMetadataStatusMeta =
      const VerificationMeta('cloudMetadataStatus');
  @override
  late final GeneratedColumn<String> cloudMetadataStatus =
      GeneratedColumn<String>(
        'cloud_metadata_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('notQueued'),
      );
  static const VerificationMeta _cloudFileStatusMeta = const VerificationMeta(
    'cloudFileStatus',
  );
  @override
  late final GeneratedColumn<String> cloudFileStatus = GeneratedColumn<String>(
    'cloud_file_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('notQueued'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checksumSha256Meta = const VerificationMeta(
    'checksumSha256',
  );
  @override
  late final GeneratedColumn<String> checksumSha256 = GeneratedColumn<String>(
    'checksum_sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageId,
    transferId,
    mediaType,
    fileName,
    mimeType,
    localPath,
    remoteFileName,
    byteSize,
    bytesTransferred,
    transferStatus,
    cloudMetadataStatus,
    cloudFileStatus,
    createdAt,
    updatedAt,
    width,
    height,
    durationMs,
    errorCode,
    checksumSha256,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Attachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('transfer_id')) {
      context.handle(
        _transferIdMeta,
        transferId.isAcceptableOrUnknown(data['transfer_id']!, _transferIdMeta),
      );
    } else if (isInserting) {
      context.missing(_transferIdMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('remote_file_name')) {
      context.handle(
        _remoteFileNameMeta,
        remoteFileName.isAcceptableOrUnknown(
          data['remote_file_name']!,
          _remoteFileNameMeta,
        ),
      );
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('bytes_transferred')) {
      context.handle(
        _bytesTransferredMeta,
        bytesTransferred.isAcceptableOrUnknown(
          data['bytes_transferred']!,
          _bytesTransferredMeta,
        ),
      );
    }
    if (data.containsKey('transfer_status')) {
      context.handle(
        _transferStatusMeta,
        transferStatus.isAcceptableOrUnknown(
          data['transfer_status']!,
          _transferStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transferStatusMeta);
    }
    if (data.containsKey('cloud_metadata_status')) {
      context.handle(
        _cloudMetadataStatusMeta,
        cloudMetadataStatus.isAcceptableOrUnknown(
          data['cloud_metadata_status']!,
          _cloudMetadataStatusMeta,
        ),
      );
    }
    if (data.containsKey('cloud_file_status')) {
      context.handle(
        _cloudFileStatusMeta,
        cloudFileStatus.isAcceptableOrUnknown(
          data['cloud_file_status']!,
          _cloudFileStatusMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('checksum_sha256')) {
      context.handle(
        _checksumSha256Meta,
        checksumSha256.isAcceptableOrUnknown(
          data['checksum_sha256']!,
          _checksumSha256Meta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Attachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Attachment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      transferId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_id'],
      )!,
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      remoteFileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_file_name'],
      ),
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      bytesTransferred: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes_transferred'],
      )!,
      transferStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_status'],
      )!,
      cloudMetadataStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_metadata_status'],
      )!,
      cloudFileStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_file_status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      checksumSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum_sha256'],
      ),
    );
  }

  @override
  $AttachmentsTable createAlias(String alias) {
    return $AttachmentsTable(attachedDatabase, alias);
  }
}

class Attachment extends DataClass implements Insertable<Attachment> {
  final String id;
  final String messageId;
  final String transferId;
  final String mediaType;
  final String fileName;
  final String mimeType;
  final String localPath;
  final String? remoteFileName;
  final int byteSize;
  final int bytesTransferred;
  final String transferStatus;
  final String cloudMetadataStatus;
  final String cloudFileStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? errorCode;
  final String? checksumSha256;
  const Attachment({
    required this.id,
    required this.messageId,
    required this.transferId,
    required this.mediaType,
    required this.fileName,
    required this.mimeType,
    required this.localPath,
    this.remoteFileName,
    required this.byteSize,
    required this.bytesTransferred,
    required this.transferStatus,
    required this.cloudMetadataStatus,
    required this.cloudFileStatus,
    required this.createdAt,
    required this.updatedAt,
    this.width,
    this.height,
    this.durationMs,
    this.errorCode,
    this.checksumSha256,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['message_id'] = Variable<String>(messageId);
    map['transfer_id'] = Variable<String>(transferId);
    map['media_type'] = Variable<String>(mediaType);
    map['file_name'] = Variable<String>(fileName);
    map['mime_type'] = Variable<String>(mimeType);
    map['local_path'] = Variable<String>(localPath);
    if (!nullToAbsent || remoteFileName != null) {
      map['remote_file_name'] = Variable<String>(remoteFileName);
    }
    map['byte_size'] = Variable<int>(byteSize);
    map['bytes_transferred'] = Variable<int>(bytesTransferred);
    map['transfer_status'] = Variable<String>(transferStatus);
    map['cloud_metadata_status'] = Variable<String>(cloudMetadataStatus);
    map['cloud_file_status'] = Variable<String>(cloudFileStatus);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || checksumSha256 != null) {
      map['checksum_sha256'] = Variable<String>(checksumSha256);
    }
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      id: Value(id),
      messageId: Value(messageId),
      transferId: Value(transferId),
      mediaType: Value(mediaType),
      fileName: Value(fileName),
      mimeType: Value(mimeType),
      localPath: Value(localPath),
      remoteFileName: remoteFileName == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteFileName),
      byteSize: Value(byteSize),
      bytesTransferred: Value(bytesTransferred),
      transferStatus: Value(transferStatus),
      cloudMetadataStatus: Value(cloudMetadataStatus),
      cloudFileStatus: Value(cloudFileStatus),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      checksumSha256: checksumSha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(checksumSha256),
    );
  }

  factory Attachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Attachment(
      id: serializer.fromJson<String>(json['id']),
      messageId: serializer.fromJson<String>(json['messageId']),
      transferId: serializer.fromJson<String>(json['transferId']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      fileName: serializer.fromJson<String>(json['fileName']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      localPath: serializer.fromJson<String>(json['localPath']),
      remoteFileName: serializer.fromJson<String?>(json['remoteFileName']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      bytesTransferred: serializer.fromJson<int>(json['bytesTransferred']),
      transferStatus: serializer.fromJson<String>(json['transferStatus']),
      cloudMetadataStatus: serializer.fromJson<String>(
        json['cloudMetadataStatus'],
      ),
      cloudFileStatus: serializer.fromJson<String>(json['cloudFileStatus']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      checksumSha256: serializer.fromJson<String?>(json['checksumSha256']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'messageId': serializer.toJson<String>(messageId),
      'transferId': serializer.toJson<String>(transferId),
      'mediaType': serializer.toJson<String>(mediaType),
      'fileName': serializer.toJson<String>(fileName),
      'mimeType': serializer.toJson<String>(mimeType),
      'localPath': serializer.toJson<String>(localPath),
      'remoteFileName': serializer.toJson<String?>(remoteFileName),
      'byteSize': serializer.toJson<int>(byteSize),
      'bytesTransferred': serializer.toJson<int>(bytesTransferred),
      'transferStatus': serializer.toJson<String>(transferStatus),
      'cloudMetadataStatus': serializer.toJson<String>(cloudMetadataStatus),
      'cloudFileStatus': serializer.toJson<String>(cloudFileStatus),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'durationMs': serializer.toJson<int?>(durationMs),
      'errorCode': serializer.toJson<String?>(errorCode),
      'checksumSha256': serializer.toJson<String?>(checksumSha256),
    };
  }

  Attachment copyWith({
    String? id,
    String? messageId,
    String? transferId,
    String? mediaType,
    String? fileName,
    String? mimeType,
    String? localPath,
    Value<String?> remoteFileName = const Value.absent(),
    int? byteSize,
    int? bytesTransferred,
    String? transferStatus,
    String? cloudMetadataStatus,
    String? cloudFileStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
    Value<String?> checksumSha256 = const Value.absent(),
  }) => Attachment(
    id: id ?? this.id,
    messageId: messageId ?? this.messageId,
    transferId: transferId ?? this.transferId,
    mediaType: mediaType ?? this.mediaType,
    fileName: fileName ?? this.fileName,
    mimeType: mimeType ?? this.mimeType,
    localPath: localPath ?? this.localPath,
    remoteFileName: remoteFileName.present
        ? remoteFileName.value
        : this.remoteFileName,
    byteSize: byteSize ?? this.byteSize,
    bytesTransferred: bytesTransferred ?? this.bytesTransferred,
    transferStatus: transferStatus ?? this.transferStatus,
    cloudMetadataStatus: cloudMetadataStatus ?? this.cloudMetadataStatus,
    cloudFileStatus: cloudFileStatus ?? this.cloudFileStatus,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    checksumSha256: checksumSha256.present
        ? checksumSha256.value
        : this.checksumSha256,
  );
  Attachment copyWithCompanion(AttachmentsCompanion data) {
    return Attachment(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      transferId: data.transferId.present
          ? data.transferId.value
          : this.transferId,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      remoteFileName: data.remoteFileName.present
          ? data.remoteFileName.value
          : this.remoteFileName,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      bytesTransferred: data.bytesTransferred.present
          ? data.bytesTransferred.value
          : this.bytesTransferred,
      transferStatus: data.transferStatus.present
          ? data.transferStatus.value
          : this.transferStatus,
      cloudMetadataStatus: data.cloudMetadataStatus.present
          ? data.cloudMetadataStatus.value
          : this.cloudMetadataStatus,
      cloudFileStatus: data.cloudFileStatus.present
          ? data.cloudFileStatus.value
          : this.cloudFileStatus,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      checksumSha256: data.checksumSha256.present
          ? data.checksumSha256.value
          : this.checksumSha256,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Attachment(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('transferId: $transferId, ')
          ..write('mediaType: $mediaType, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('localPath: $localPath, ')
          ..write('remoteFileName: $remoteFileName, ')
          ..write('byteSize: $byteSize, ')
          ..write('bytesTransferred: $bytesTransferred, ')
          ..write('transferStatus: $transferStatus, ')
          ..write('cloudMetadataStatus: $cloudMetadataStatus, ')
          ..write('cloudFileStatus: $cloudFileStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('errorCode: $errorCode, ')
          ..write('checksumSha256: $checksumSha256')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageId,
    transferId,
    mediaType,
    fileName,
    mimeType,
    localPath,
    remoteFileName,
    byteSize,
    bytesTransferred,
    transferStatus,
    cloudMetadataStatus,
    cloudFileStatus,
    createdAt,
    updatedAt,
    width,
    height,
    durationMs,
    errorCode,
    checksumSha256,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Attachment &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.transferId == this.transferId &&
          other.mediaType == this.mediaType &&
          other.fileName == this.fileName &&
          other.mimeType == this.mimeType &&
          other.localPath == this.localPath &&
          other.remoteFileName == this.remoteFileName &&
          other.byteSize == this.byteSize &&
          other.bytesTransferred == this.bytesTransferred &&
          other.transferStatus == this.transferStatus &&
          other.cloudMetadataStatus == this.cloudMetadataStatus &&
          other.cloudFileStatus == this.cloudFileStatus &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.width == this.width &&
          other.height == this.height &&
          other.durationMs == this.durationMs &&
          other.errorCode == this.errorCode &&
          other.checksumSha256 == this.checksumSha256);
}

class AttachmentsCompanion extends UpdateCompanion<Attachment> {
  final Value<String> id;
  final Value<String> messageId;
  final Value<String> transferId;
  final Value<String> mediaType;
  final Value<String> fileName;
  final Value<String> mimeType;
  final Value<String> localPath;
  final Value<String?> remoteFileName;
  final Value<int> byteSize;
  final Value<int> bytesTransferred;
  final Value<String> transferStatus;
  final Value<String> cloudMetadataStatus;
  final Value<String> cloudFileStatus;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> durationMs;
  final Value<String?> errorCode;
  final Value<String?> checksumSha256;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.transferId = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.fileName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.localPath = const Value.absent(),
    this.remoteFileName = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.bytesTransferred = const Value.absent(),
    this.transferStatus = const Value.absent(),
    this.cloudMetadataStatus = const Value.absent(),
    this.cloudFileStatus = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.checksumSha256 = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    required String id,
    required String messageId,
    required String transferId,
    required String mediaType,
    required String fileName,
    required String mimeType,
    required String localPath,
    this.remoteFileName = const Value.absent(),
    required int byteSize,
    this.bytesTransferred = const Value.absent(),
    required String transferStatus,
    this.cloudMetadataStatus = const Value.absent(),
    this.cloudFileStatus = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.checksumSha256 = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       messageId = Value(messageId),
       transferId = Value(transferId),
       mediaType = Value(mediaType),
       fileName = Value(fileName),
       mimeType = Value(mimeType),
       localPath = Value(localPath),
       byteSize = Value(byteSize),
       transferStatus = Value(transferStatus),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Attachment> custom({
    Expression<String>? id,
    Expression<String>? messageId,
    Expression<String>? transferId,
    Expression<String>? mediaType,
    Expression<String>? fileName,
    Expression<String>? mimeType,
    Expression<String>? localPath,
    Expression<String>? remoteFileName,
    Expression<int>? byteSize,
    Expression<int>? bytesTransferred,
    Expression<String>? transferStatus,
    Expression<String>? cloudMetadataStatus,
    Expression<String>? cloudFileStatus,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? durationMs,
    Expression<String>? errorCode,
    Expression<String>? checksumSha256,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (transferId != null) 'transfer_id': transferId,
      if (mediaType != null) 'media_type': mediaType,
      if (fileName != null) 'file_name': fileName,
      if (mimeType != null) 'mime_type': mimeType,
      if (localPath != null) 'local_path': localPath,
      if (remoteFileName != null) 'remote_file_name': remoteFileName,
      if (byteSize != null) 'byte_size': byteSize,
      if (bytesTransferred != null) 'bytes_transferred': bytesTransferred,
      if (transferStatus != null) 'transfer_status': transferStatus,
      if (cloudMetadataStatus != null)
        'cloud_metadata_status': cloudMetadataStatus,
      if (cloudFileStatus != null) 'cloud_file_status': cloudFileStatus,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (errorCode != null) 'error_code': errorCode,
      if (checksumSha256 != null) 'checksum_sha256': checksumSha256,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? messageId,
    Value<String>? transferId,
    Value<String>? mediaType,
    Value<String>? fileName,
    Value<String>? mimeType,
    Value<String>? localPath,
    Value<String?>? remoteFileName,
    Value<int>? byteSize,
    Value<int>? bytesTransferred,
    Value<String>? transferStatus,
    Value<String>? cloudMetadataStatus,
    Value<String>? cloudFileStatus,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? durationMs,
    Value<String?>? errorCode,
    Value<String?>? checksumSha256,
    Value<int>? rowid,
  }) {
    return AttachmentsCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      transferId: transferId ?? this.transferId,
      mediaType: mediaType ?? this.mediaType,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      localPath: localPath ?? this.localPath,
      remoteFileName: remoteFileName ?? this.remoteFileName,
      byteSize: byteSize ?? this.byteSize,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      transferStatus: transferStatus ?? this.transferStatus,
      cloudMetadataStatus: cloudMetadataStatus ?? this.cloudMetadataStatus,
      cloudFileStatus: cloudFileStatus ?? this.cloudFileStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      errorCode: errorCode ?? this.errorCode,
      checksumSha256: checksumSha256 ?? this.checksumSha256,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (transferId.present) {
      map['transfer_id'] = Variable<String>(transferId.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (remoteFileName.present) {
      map['remote_file_name'] = Variable<String>(remoteFileName.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (bytesTransferred.present) {
      map['bytes_transferred'] = Variable<int>(bytesTransferred.value);
    }
    if (transferStatus.present) {
      map['transfer_status'] = Variable<String>(transferStatus.value);
    }
    if (cloudMetadataStatus.present) {
      map['cloud_metadata_status'] = Variable<String>(
        cloudMetadataStatus.value,
      );
    }
    if (cloudFileStatus.present) {
      map['cloud_file_status'] = Variable<String>(cloudFileStatus.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (checksumSha256.present) {
      map['checksum_sha256'] = Variable<String>(checksumSha256.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('transferId: $transferId, ')
          ..write('mediaType: $mediaType, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('localPath: $localPath, ')
          ..write('remoteFileName: $remoteFileName, ')
          ..write('byteSize: $byteSize, ')
          ..write('bytesTransferred: $bytesTransferred, ')
          ..write('transferStatus: $transferStatus, ')
          ..write('cloudMetadataStatus: $cloudMetadataStatus, ')
          ..write('cloudFileStatus: $cloudFileStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('errorCode: $errorCode, ')
          ..write('checksumSha256: $checksumSha256, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RelayPacketsTable extends RelayPackets
    with TableInfo<$RelayPacketsTable, RelayPacket> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RelayPacketsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _packetIdMeta = const VerificationMeta(
    'packetId',
  );
  @override
  late final GeneratedColumn<String> packetId = GeneratedColumn<String>(
    'packet_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originDeviceIdMeta = const VerificationMeta(
    'originDeviceId',
  );
  @override
  late final GeneratedColumn<String> originDeviceId = GeneratedColumn<String>(
    'origin_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationDeviceIdMeta =
      const VerificationMeta('destinationDeviceId');
  @override
  late final GeneratedColumn<String> destinationDeviceId =
      GeneratedColumn<String>(
        'destination_device_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _payloadTypeMeta = const VerificationMeta(
    'payloadType',
  );
  @override
  late final GeneratedColumn<String> payloadType = GeneratedColumn<String>(
    'payload_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadIdMeta = const VerificationMeta(
    'payloadId',
  );
  @override
  late final GeneratedColumn<String> payloadId = GeneratedColumn<String>(
    'payload_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hopCountMeta = const VerificationMeta(
    'hopCount',
  );
  @override
  late final GeneratedColumn<int> hopCount = GeneratedColumn<int>(
    'hop_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxHopsMeta = const VerificationMeta(
    'maxHops',
  );
  @override
  late final GeneratedColumn<int> maxHops = GeneratedColumn<int>(
    'max_hops',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previousHopDeviceIdMeta =
      const VerificationMeta('previousHopDeviceId');
  @override
  late final GeneratedColumn<String> previousHopDeviceId =
      GeneratedColumn<String>(
        'previous_hop_device_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _protocolMeta = const VerificationMeta(
    'protocol',
  );
  @override
  late final GeneratedColumn<String> protocol = GeneratedColumn<String>(
    'protocol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storedAtMeta = const VerificationMeta(
    'storedAt',
  );
  @override
  late final GeneratedColumn<DateTime> storedAt = GeneratedColumn<DateTime>(
    'stored_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    packetId,
    originDeviceId,
    destinationDeviceId,
    payloadType,
    payloadId,
    createdAt,
    expiresAt,
    hopCount,
    maxHops,
    priority,
    previousHopDeviceId,
    protocol,
    payloadJson,
    state,
    storedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'relay_packets';
  @override
  VerificationContext validateIntegrity(
    Insertable<RelayPacket> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('packet_id')) {
      context.handle(
        _packetIdMeta,
        packetId.isAcceptableOrUnknown(data['packet_id']!, _packetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_packetIdMeta);
    }
    if (data.containsKey('origin_device_id')) {
      context.handle(
        _originDeviceIdMeta,
        originDeviceId.isAcceptableOrUnknown(
          data['origin_device_id']!,
          _originDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceIdMeta);
    }
    if (data.containsKey('destination_device_id')) {
      context.handle(
        _destinationDeviceIdMeta,
        destinationDeviceId.isAcceptableOrUnknown(
          data['destination_device_id']!,
          _destinationDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_destinationDeviceIdMeta);
    }
    if (data.containsKey('payload_type')) {
      context.handle(
        _payloadTypeMeta,
        payloadType.isAcceptableOrUnknown(
          data['payload_type']!,
          _payloadTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadTypeMeta);
    }
    if (data.containsKey('payload_id')) {
      context.handle(
        _payloadIdMeta,
        payloadId.isAcceptableOrUnknown(data['payload_id']!, _payloadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('hop_count')) {
      context.handle(
        _hopCountMeta,
        hopCount.isAcceptableOrUnknown(data['hop_count']!, _hopCountMeta),
      );
    } else if (isInserting) {
      context.missing(_hopCountMeta);
    }
    if (data.containsKey('max_hops')) {
      context.handle(
        _maxHopsMeta,
        maxHops.isAcceptableOrUnknown(data['max_hops']!, _maxHopsMeta),
      );
    } else if (isInserting) {
      context.missing(_maxHopsMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('previous_hop_device_id')) {
      context.handle(
        _previousHopDeviceIdMeta,
        previousHopDeviceId.isAcceptableOrUnknown(
          data['previous_hop_device_id']!,
          _previousHopDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('protocol')) {
      context.handle(
        _protocolMeta,
        protocol.isAcceptableOrUnknown(data['protocol']!, _protocolMeta),
      );
    } else if (isInserting) {
      context.missing(_protocolMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('stored_at')) {
      context.handle(
        _storedAtMeta,
        storedAt.isAcceptableOrUnknown(data['stored_at']!, _storedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_storedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {packetId};
  @override
  RelayPacket map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RelayPacket(
      packetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}packet_id'],
      )!,
      originDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device_id'],
      )!,
      destinationDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_device_id'],
      )!,
      payloadType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_type'],
      )!,
      payloadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
      hopCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hop_count'],
      )!,
      maxHops: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_hops'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      previousHopDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_hop_device_id'],
      ),
      protocol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}protocol'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      storedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}stored_at'],
      )!,
    );
  }

  @override
  $RelayPacketsTable createAlias(String alias) {
    return $RelayPacketsTable(attachedDatabase, alias);
  }
}

class RelayPacket extends DataClass implements Insertable<RelayPacket> {
  final String packetId;
  final String originDeviceId;
  final String destinationDeviceId;
  final String payloadType;
  final String payloadId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int hopCount;
  final int maxHops;
  final int priority;
  final String? previousHopDeviceId;
  final String protocol;
  final String payloadJson;
  final String state;
  final DateTime storedAt;
  const RelayPacket({
    required this.packetId,
    required this.originDeviceId,
    required this.destinationDeviceId,
    required this.payloadType,
    required this.payloadId,
    required this.createdAt,
    required this.expiresAt,
    required this.hopCount,
    required this.maxHops,
    required this.priority,
    this.previousHopDeviceId,
    required this.protocol,
    required this.payloadJson,
    required this.state,
    required this.storedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['packet_id'] = Variable<String>(packetId);
    map['origin_device_id'] = Variable<String>(originDeviceId);
    map['destination_device_id'] = Variable<String>(destinationDeviceId);
    map['payload_type'] = Variable<String>(payloadType);
    map['payload_id'] = Variable<String>(payloadId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['expires_at'] = Variable<DateTime>(expiresAt);
    map['hop_count'] = Variable<int>(hopCount);
    map['max_hops'] = Variable<int>(maxHops);
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || previousHopDeviceId != null) {
      map['previous_hop_device_id'] = Variable<String>(previousHopDeviceId);
    }
    map['protocol'] = Variable<String>(protocol);
    map['payload_json'] = Variable<String>(payloadJson);
    map['state'] = Variable<String>(state);
    map['stored_at'] = Variable<DateTime>(storedAt);
    return map;
  }

  RelayPacketsCompanion toCompanion(bool nullToAbsent) {
    return RelayPacketsCompanion(
      packetId: Value(packetId),
      originDeviceId: Value(originDeviceId),
      destinationDeviceId: Value(destinationDeviceId),
      payloadType: Value(payloadType),
      payloadId: Value(payloadId),
      createdAt: Value(createdAt),
      expiresAt: Value(expiresAt),
      hopCount: Value(hopCount),
      maxHops: Value(maxHops),
      priority: Value(priority),
      previousHopDeviceId: previousHopDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(previousHopDeviceId),
      protocol: Value(protocol),
      payloadJson: Value(payloadJson),
      state: Value(state),
      storedAt: Value(storedAt),
    );
  }

  factory RelayPacket.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RelayPacket(
      packetId: serializer.fromJson<String>(json['packetId']),
      originDeviceId: serializer.fromJson<String>(json['originDeviceId']),
      destinationDeviceId: serializer.fromJson<String>(
        json['destinationDeviceId'],
      ),
      payloadType: serializer.fromJson<String>(json['payloadType']),
      payloadId: serializer.fromJson<String>(json['payloadId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
      hopCount: serializer.fromJson<int>(json['hopCount']),
      maxHops: serializer.fromJson<int>(json['maxHops']),
      priority: serializer.fromJson<int>(json['priority']),
      previousHopDeviceId: serializer.fromJson<String?>(
        json['previousHopDeviceId'],
      ),
      protocol: serializer.fromJson<String>(json['protocol']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      state: serializer.fromJson<String>(json['state']),
      storedAt: serializer.fromJson<DateTime>(json['storedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'packetId': serializer.toJson<String>(packetId),
      'originDeviceId': serializer.toJson<String>(originDeviceId),
      'destinationDeviceId': serializer.toJson<String>(destinationDeviceId),
      'payloadType': serializer.toJson<String>(payloadType),
      'payloadId': serializer.toJson<String>(payloadId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
      'hopCount': serializer.toJson<int>(hopCount),
      'maxHops': serializer.toJson<int>(maxHops),
      'priority': serializer.toJson<int>(priority),
      'previousHopDeviceId': serializer.toJson<String?>(previousHopDeviceId),
      'protocol': serializer.toJson<String>(protocol),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'state': serializer.toJson<String>(state),
      'storedAt': serializer.toJson<DateTime>(storedAt),
    };
  }

  RelayPacket copyWith({
    String? packetId,
    String? originDeviceId,
    String? destinationDeviceId,
    String? payloadType,
    String? payloadId,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? hopCount,
    int? maxHops,
    int? priority,
    Value<String?> previousHopDeviceId = const Value.absent(),
    String? protocol,
    String? payloadJson,
    String? state,
    DateTime? storedAt,
  }) => RelayPacket(
    packetId: packetId ?? this.packetId,
    originDeviceId: originDeviceId ?? this.originDeviceId,
    destinationDeviceId: destinationDeviceId ?? this.destinationDeviceId,
    payloadType: payloadType ?? this.payloadType,
    payloadId: payloadId ?? this.payloadId,
    createdAt: createdAt ?? this.createdAt,
    expiresAt: expiresAt ?? this.expiresAt,
    hopCount: hopCount ?? this.hopCount,
    maxHops: maxHops ?? this.maxHops,
    priority: priority ?? this.priority,
    previousHopDeviceId: previousHopDeviceId.present
        ? previousHopDeviceId.value
        : this.previousHopDeviceId,
    protocol: protocol ?? this.protocol,
    payloadJson: payloadJson ?? this.payloadJson,
    state: state ?? this.state,
    storedAt: storedAt ?? this.storedAt,
  );
  RelayPacket copyWithCompanion(RelayPacketsCompanion data) {
    return RelayPacket(
      packetId: data.packetId.present ? data.packetId.value : this.packetId,
      originDeviceId: data.originDeviceId.present
          ? data.originDeviceId.value
          : this.originDeviceId,
      destinationDeviceId: data.destinationDeviceId.present
          ? data.destinationDeviceId.value
          : this.destinationDeviceId,
      payloadType: data.payloadType.present
          ? data.payloadType.value
          : this.payloadType,
      payloadId: data.payloadId.present ? data.payloadId.value : this.payloadId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      hopCount: data.hopCount.present ? data.hopCount.value : this.hopCount,
      maxHops: data.maxHops.present ? data.maxHops.value : this.maxHops,
      priority: data.priority.present ? data.priority.value : this.priority,
      previousHopDeviceId: data.previousHopDeviceId.present
          ? data.previousHopDeviceId.value
          : this.previousHopDeviceId,
      protocol: data.protocol.present ? data.protocol.value : this.protocol,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      state: data.state.present ? data.state.value : this.state,
      storedAt: data.storedAt.present ? data.storedAt.value : this.storedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RelayPacket(')
          ..write('packetId: $packetId, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('destinationDeviceId: $destinationDeviceId, ')
          ..write('payloadType: $payloadType, ')
          ..write('payloadId: $payloadId, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('hopCount: $hopCount, ')
          ..write('maxHops: $maxHops, ')
          ..write('priority: $priority, ')
          ..write('previousHopDeviceId: $previousHopDeviceId, ')
          ..write('protocol: $protocol, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('state: $state, ')
          ..write('storedAt: $storedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    packetId,
    originDeviceId,
    destinationDeviceId,
    payloadType,
    payloadId,
    createdAt,
    expiresAt,
    hopCount,
    maxHops,
    priority,
    previousHopDeviceId,
    protocol,
    payloadJson,
    state,
    storedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RelayPacket &&
          other.packetId == this.packetId &&
          other.originDeviceId == this.originDeviceId &&
          other.destinationDeviceId == this.destinationDeviceId &&
          other.payloadType == this.payloadType &&
          other.payloadId == this.payloadId &&
          other.createdAt == this.createdAt &&
          other.expiresAt == this.expiresAt &&
          other.hopCount == this.hopCount &&
          other.maxHops == this.maxHops &&
          other.priority == this.priority &&
          other.previousHopDeviceId == this.previousHopDeviceId &&
          other.protocol == this.protocol &&
          other.payloadJson == this.payloadJson &&
          other.state == this.state &&
          other.storedAt == this.storedAt);
}

class RelayPacketsCompanion extends UpdateCompanion<RelayPacket> {
  final Value<String> packetId;
  final Value<String> originDeviceId;
  final Value<String> destinationDeviceId;
  final Value<String> payloadType;
  final Value<String> payloadId;
  final Value<DateTime> createdAt;
  final Value<DateTime> expiresAt;
  final Value<int> hopCount;
  final Value<int> maxHops;
  final Value<int> priority;
  final Value<String?> previousHopDeviceId;
  final Value<String> protocol;
  final Value<String> payloadJson;
  final Value<String> state;
  final Value<DateTime> storedAt;
  final Value<int> rowid;
  const RelayPacketsCompanion({
    this.packetId = const Value.absent(),
    this.originDeviceId = const Value.absent(),
    this.destinationDeviceId = const Value.absent(),
    this.payloadType = const Value.absent(),
    this.payloadId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.hopCount = const Value.absent(),
    this.maxHops = const Value.absent(),
    this.priority = const Value.absent(),
    this.previousHopDeviceId = const Value.absent(),
    this.protocol = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.state = const Value.absent(),
    this.storedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RelayPacketsCompanion.insert({
    required String packetId,
    required String originDeviceId,
    required String destinationDeviceId,
    required String payloadType,
    required String payloadId,
    required DateTime createdAt,
    required DateTime expiresAt,
    required int hopCount,
    required int maxHops,
    required int priority,
    this.previousHopDeviceId = const Value.absent(),
    required String protocol,
    required String payloadJson,
    required String state,
    required DateTime storedAt,
    this.rowid = const Value.absent(),
  }) : packetId = Value(packetId),
       originDeviceId = Value(originDeviceId),
       destinationDeviceId = Value(destinationDeviceId),
       payloadType = Value(payloadType),
       payloadId = Value(payloadId),
       createdAt = Value(createdAt),
       expiresAt = Value(expiresAt),
       hopCount = Value(hopCount),
       maxHops = Value(maxHops),
       priority = Value(priority),
       protocol = Value(protocol),
       payloadJson = Value(payloadJson),
       state = Value(state),
       storedAt = Value(storedAt);
  static Insertable<RelayPacket> custom({
    Expression<String>? packetId,
    Expression<String>? originDeviceId,
    Expression<String>? destinationDeviceId,
    Expression<String>? payloadType,
    Expression<String>? payloadId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? expiresAt,
    Expression<int>? hopCount,
    Expression<int>? maxHops,
    Expression<int>? priority,
    Expression<String>? previousHopDeviceId,
    Expression<String>? protocol,
    Expression<String>? payloadJson,
    Expression<String>? state,
    Expression<DateTime>? storedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (packetId != null) 'packet_id': packetId,
      if (originDeviceId != null) 'origin_device_id': originDeviceId,
      if (destinationDeviceId != null)
        'destination_device_id': destinationDeviceId,
      if (payloadType != null) 'payload_type': payloadType,
      if (payloadId != null) 'payload_id': payloadId,
      if (createdAt != null) 'created_at': createdAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (hopCount != null) 'hop_count': hopCount,
      if (maxHops != null) 'max_hops': maxHops,
      if (priority != null) 'priority': priority,
      if (previousHopDeviceId != null)
        'previous_hop_device_id': previousHopDeviceId,
      if (protocol != null) 'protocol': protocol,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (state != null) 'state': state,
      if (storedAt != null) 'stored_at': storedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RelayPacketsCompanion copyWith({
    Value<String>? packetId,
    Value<String>? originDeviceId,
    Value<String>? destinationDeviceId,
    Value<String>? payloadType,
    Value<String>? payloadId,
    Value<DateTime>? createdAt,
    Value<DateTime>? expiresAt,
    Value<int>? hopCount,
    Value<int>? maxHops,
    Value<int>? priority,
    Value<String?>? previousHopDeviceId,
    Value<String>? protocol,
    Value<String>? payloadJson,
    Value<String>? state,
    Value<DateTime>? storedAt,
    Value<int>? rowid,
  }) {
    return RelayPacketsCompanion(
      packetId: packetId ?? this.packetId,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      destinationDeviceId: destinationDeviceId ?? this.destinationDeviceId,
      payloadType: payloadType ?? this.payloadType,
      payloadId: payloadId ?? this.payloadId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      hopCount: hopCount ?? this.hopCount,
      maxHops: maxHops ?? this.maxHops,
      priority: priority ?? this.priority,
      previousHopDeviceId: previousHopDeviceId ?? this.previousHopDeviceId,
      protocol: protocol ?? this.protocol,
      payloadJson: payloadJson ?? this.payloadJson,
      state: state ?? this.state,
      storedAt: storedAt ?? this.storedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (packetId.present) {
      map['packet_id'] = Variable<String>(packetId.value);
    }
    if (originDeviceId.present) {
      map['origin_device_id'] = Variable<String>(originDeviceId.value);
    }
    if (destinationDeviceId.present) {
      map['destination_device_id'] = Variable<String>(
        destinationDeviceId.value,
      );
    }
    if (payloadType.present) {
      map['payload_type'] = Variable<String>(payloadType.value);
    }
    if (payloadId.present) {
      map['payload_id'] = Variable<String>(payloadId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (hopCount.present) {
      map['hop_count'] = Variable<int>(hopCount.value);
    }
    if (maxHops.present) {
      map['max_hops'] = Variable<int>(maxHops.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (previousHopDeviceId.present) {
      map['previous_hop_device_id'] = Variable<String>(
        previousHopDeviceId.value,
      );
    }
    if (protocol.present) {
      map['protocol'] = Variable<String>(protocol.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (storedAt.present) {
      map['stored_at'] = Variable<DateTime>(storedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RelayPacketsCompanion(')
          ..write('packetId: $packetId, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('destinationDeviceId: $destinationDeviceId, ')
          ..write('payloadType: $payloadType, ')
          ..write('payloadId: $payloadId, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('hopCount: $hopCount, ')
          ..write('maxHops: $maxHops, ')
          ..write('priority: $priority, ')
          ..write('previousHopDeviceId: $previousHopDeviceId, ')
          ..write('protocol: $protocol, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('state: $state, ')
          ..write('storedAt: $storedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RelayForwardHistoryTable extends RelayForwardHistory
    with TableInfo<$RelayForwardHistoryTable, RelayForwardHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RelayForwardHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _packetIdMeta = const VerificationMeta(
    'packetId',
  );
  @override
  late final GeneratedColumn<String> packetId = GeneratedColumn<String>(
    'packet_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetDeviceIdMeta = const VerificationMeta(
    'targetDeviceId',
  );
  @override
  late final GeneratedColumn<String> targetDeviceId = GeneratedColumn<String>(
    'target_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetEndpointIdMeta = const VerificationMeta(
    'targetEndpointId',
  );
  @override
  late final GeneratedColumn<String> targetEndpointId = GeneratedColumn<String>(
    'target_endpoint_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    packetId,
    targetDeviceId,
    targetEndpointId,
    status,
    attemptCount,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'relay_forward_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<RelayForwardHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('packet_id')) {
      context.handle(
        _packetIdMeta,
        packetId.isAcceptableOrUnknown(data['packet_id']!, _packetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_packetIdMeta);
    }
    if (data.containsKey('target_device_id')) {
      context.handle(
        _targetDeviceIdMeta,
        targetDeviceId.isAcceptableOrUnknown(
          data['target_device_id']!,
          _targetDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetDeviceIdMeta);
    }
    if (data.containsKey('target_endpoint_id')) {
      context.handle(
        _targetEndpointIdMeta,
        targetEndpointId.isAcceptableOrUnknown(
          data['target_endpoint_id']!,
          _targetEndpointIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetEndpointIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {packetId, targetDeviceId};
  @override
  RelayForwardHistoryData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RelayForwardHistoryData(
      packetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}packet_id'],
      )!,
      targetDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_device_id'],
      )!,
      targetEndpointId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_endpoint_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RelayForwardHistoryTable createAlias(String alias) {
    return $RelayForwardHistoryTable(attachedDatabase, alias);
  }
}

class RelayForwardHistoryData extends DataClass
    implements Insertable<RelayForwardHistoryData> {
  final String packetId;
  final String targetDeviceId;
  final String targetEndpointId;
  final String status;
  final int attemptCount;
  final DateTime updatedAt;
  const RelayForwardHistoryData({
    required this.packetId,
    required this.targetDeviceId,
    required this.targetEndpointId,
    required this.status,
    required this.attemptCount,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['packet_id'] = Variable<String>(packetId);
    map['target_device_id'] = Variable<String>(targetDeviceId);
    map['target_endpoint_id'] = Variable<String>(targetEndpointId);
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RelayForwardHistoryCompanion toCompanion(bool nullToAbsent) {
    return RelayForwardHistoryCompanion(
      packetId: Value(packetId),
      targetDeviceId: Value(targetDeviceId),
      targetEndpointId: Value(targetEndpointId),
      status: Value(status),
      attemptCount: Value(attemptCount),
      updatedAt: Value(updatedAt),
    );
  }

  factory RelayForwardHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RelayForwardHistoryData(
      packetId: serializer.fromJson<String>(json['packetId']),
      targetDeviceId: serializer.fromJson<String>(json['targetDeviceId']),
      targetEndpointId: serializer.fromJson<String>(json['targetEndpointId']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'packetId': serializer.toJson<String>(packetId),
      'targetDeviceId': serializer.toJson<String>(targetDeviceId),
      'targetEndpointId': serializer.toJson<String>(targetEndpointId),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RelayForwardHistoryData copyWith({
    String? packetId,
    String? targetDeviceId,
    String? targetEndpointId,
    String? status,
    int? attemptCount,
    DateTime? updatedAt,
  }) => RelayForwardHistoryData(
    packetId: packetId ?? this.packetId,
    targetDeviceId: targetDeviceId ?? this.targetDeviceId,
    targetEndpointId: targetEndpointId ?? this.targetEndpointId,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RelayForwardHistoryData copyWithCompanion(RelayForwardHistoryCompanion data) {
    return RelayForwardHistoryData(
      packetId: data.packetId.present ? data.packetId.value : this.packetId,
      targetDeviceId: data.targetDeviceId.present
          ? data.targetDeviceId.value
          : this.targetDeviceId,
      targetEndpointId: data.targetEndpointId.present
          ? data.targetEndpointId.value
          : this.targetEndpointId,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RelayForwardHistoryData(')
          ..write('packetId: $packetId, ')
          ..write('targetDeviceId: $targetDeviceId, ')
          ..write('targetEndpointId: $targetEndpointId, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    packetId,
    targetDeviceId,
    targetEndpointId,
    status,
    attemptCount,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RelayForwardHistoryData &&
          other.packetId == this.packetId &&
          other.targetDeviceId == this.targetDeviceId &&
          other.targetEndpointId == this.targetEndpointId &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.updatedAt == this.updatedAt);
}

class RelayForwardHistoryCompanion
    extends UpdateCompanion<RelayForwardHistoryData> {
  final Value<String> packetId;
  final Value<String> targetDeviceId;
  final Value<String> targetEndpointId;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RelayForwardHistoryCompanion({
    this.packetId = const Value.absent(),
    this.targetDeviceId = const Value.absent(),
    this.targetEndpointId = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RelayForwardHistoryCompanion.insert({
    required String packetId,
    required String targetDeviceId,
    required String targetEndpointId,
    required String status,
    this.attemptCount = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : packetId = Value(packetId),
       targetDeviceId = Value(targetDeviceId),
       targetEndpointId = Value(targetEndpointId),
       status = Value(status),
       updatedAt = Value(updatedAt);
  static Insertable<RelayForwardHistoryData> custom({
    Expression<String>? packetId,
    Expression<String>? targetDeviceId,
    Expression<String>? targetEndpointId,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (packetId != null) 'packet_id': packetId,
      if (targetDeviceId != null) 'target_device_id': targetDeviceId,
      if (targetEndpointId != null) 'target_endpoint_id': targetEndpointId,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RelayForwardHistoryCompanion copyWith({
    Value<String>? packetId,
    Value<String>? targetDeviceId,
    Value<String>? targetEndpointId,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RelayForwardHistoryCompanion(
      packetId: packetId ?? this.packetId,
      targetDeviceId: targetDeviceId ?? this.targetDeviceId,
      targetEndpointId: targetEndpointId ?? this.targetEndpointId,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (packetId.present) {
      map['packet_id'] = Variable<String>(packetId.value);
    }
    if (targetDeviceId.present) {
      map['target_device_id'] = Variable<String>(targetDeviceId.value);
    }
    if (targetEndpointId.present) {
      map['target_endpoint_id'] = Variable<String>(targetEndpointId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RelayForwardHistoryCompanion(')
          ..write('packetId: $packetId, ')
          ..write('targetDeviceId: $targetDeviceId, ')
          ..write('targetEndpointId: $targetEndpointId, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $CloudConversationLinksTable cloudConversationLinks =
      $CloudConversationLinksTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $NearbyDevicesTable nearbyDevices = $NearbyDevicesTable(this);
  late final $SyncQueueTable syncQueue = $SyncQueueTable(this);
  late final $SosEventsTable sosEvents = $SosEventsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final $RelayPacketsTable relayPackets = $RelayPacketsTable(this);
  late final $RelayForwardHistoryTable relayForwardHistory =
      $RelayForwardHistoryTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    conversations,
    cloudConversationLinks,
    messages,
    nearbyDevices,
    syncQueue,
    sosEvents,
    appSettings,
    attachments,
    relayPackets,
    relayForwardHistory,
  ];
}

typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String id,
      required String participantId,
      required String displayName,
      required String participantStatus,
      Value<int> unreadCount,
      Value<DateTime?> lastMessageAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> id,
      Value<String> participantId,
      Value<String> displayName,
      Value<String> participantStatus,
      Value<int> unreadCount,
      Value<DateTime?> lastMessageAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get participantStatus => $composableBuilder(
    column: $table.participantStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get participantStatus => $composableBuilder(
    column: $table.participantStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get participantStatus => $composableBuilder(
    column: $table.participantStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (
            Conversation,
            BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>,
          ),
          Conversation,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableManager(_$AppDatabase db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> participantId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> participantStatus = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                participantId: participantId,
                displayName: displayName,
                participantStatus: participantStatus,
                unreadCount: unreadCount,
                lastMessageAt: lastMessageAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String participantId,
                required String displayName,
                required String participantStatus,
                Value<int> unreadCount = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                id: id,
                participantId: participantId,
                displayName: displayName,
                participantStatus: participantStatus,
                unreadCount: unreadCount,
                lastMessageAt: lastMessageAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConversationsTable, Conversation>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ConversationsTable,
                    Conversation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (
        Conversation,
        BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>,
      ),
      Conversation,
      PrefetchHooks Function()
    >;
typedef $$CloudConversationLinksTableCreateCompanionBuilder =
    CloudConversationLinksCompanion Function({
      required String localConversationId,
      required String cloudConversationId,
      required String ownerUserId,
      required String peerUserId,
      Value<DateTime?> messageCursorAt,
      Value<String?> messageCursorId,
      Value<DateTime?> receiptCursorAt,
      Value<String?> receiptCursorMessageId,
      Value<String?> receiptCursorReaderId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CloudConversationLinksTableUpdateCompanionBuilder =
    CloudConversationLinksCompanion Function({
      Value<String> localConversationId,
      Value<String> cloudConversationId,
      Value<String> ownerUserId,
      Value<String> peerUserId,
      Value<DateTime?> messageCursorAt,
      Value<String?> messageCursorId,
      Value<DateTime?> receiptCursorAt,
      Value<String?> receiptCursorMessageId,
      Value<String?> receiptCursorReaderId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CloudConversationLinksTableFilterComposer
    extends Composer<_$AppDatabase, $CloudConversationLinksTable> {
  $$CloudConversationLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localConversationId => $composableBuilder(
    column: $table.localConversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudConversationId => $composableBuilder(
    column: $table.cloudConversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerUserId => $composableBuilder(
    column: $table.peerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get messageCursorAt => $composableBuilder(
    column: $table.messageCursorAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageCursorId => $composableBuilder(
    column: $table.messageCursorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receiptCursorAt => $composableBuilder(
    column: $table.receiptCursorAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptCursorMessageId => $composableBuilder(
    column: $table.receiptCursorMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptCursorReaderId => $composableBuilder(
    column: $table.receiptCursorReaderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CloudConversationLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $CloudConversationLinksTable> {
  $$CloudConversationLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localConversationId => $composableBuilder(
    column: $table.localConversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudConversationId => $composableBuilder(
    column: $table.cloudConversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerUserId => $composableBuilder(
    column: $table.peerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get messageCursorAt => $composableBuilder(
    column: $table.messageCursorAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageCursorId => $composableBuilder(
    column: $table.messageCursorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receiptCursorAt => $composableBuilder(
    column: $table.receiptCursorAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptCursorMessageId => $composableBuilder(
    column: $table.receiptCursorMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptCursorReaderId => $composableBuilder(
    column: $table.receiptCursorReaderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CloudConversationLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $CloudConversationLinksTable> {
  $$CloudConversationLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localConversationId => $composableBuilder(
    column: $table.localConversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudConversationId => $composableBuilder(
    column: $table.cloudConversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerUserId => $composableBuilder(
    column: $table.peerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get messageCursorAt => $composableBuilder(
    column: $table.messageCursorAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageCursorId => $composableBuilder(
    column: $table.messageCursorId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get receiptCursorAt => $composableBuilder(
    column: $table.receiptCursorAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptCursorMessageId => $composableBuilder(
    column: $table.receiptCursorMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptCursorReaderId => $composableBuilder(
    column: $table.receiptCursorReaderId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CloudConversationLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CloudConversationLinksTable,
          CloudConversationLink,
          $$CloudConversationLinksTableFilterComposer,
          $$CloudConversationLinksTableOrderingComposer,
          $$CloudConversationLinksTableAnnotationComposer,
          $$CloudConversationLinksTableCreateCompanionBuilder,
          $$CloudConversationLinksTableUpdateCompanionBuilder,
          (
            CloudConversationLink,
            BaseReferences<
              _$AppDatabase,
              $CloudConversationLinksTable,
              CloudConversationLink
            >,
          ),
          CloudConversationLink,
          PrefetchHooks Function()
        > {
  $$CloudConversationLinksTableTableManager(
    _$AppDatabase db,
    $CloudConversationLinksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CloudConversationLinksTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CloudConversationLinksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CloudConversationLinksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> localConversationId = const Value.absent(),
                Value<String> cloudConversationId = const Value.absent(),
                Value<String> ownerUserId = const Value.absent(),
                Value<String> peerUserId = const Value.absent(),
                Value<DateTime?> messageCursorAt = const Value.absent(),
                Value<String?> messageCursorId = const Value.absent(),
                Value<DateTime?> receiptCursorAt = const Value.absent(),
                Value<String?> receiptCursorMessageId = const Value.absent(),
                Value<String?> receiptCursorReaderId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CloudConversationLinksCompanion(
                localConversationId: localConversationId,
                cloudConversationId: cloudConversationId,
                ownerUserId: ownerUserId,
                peerUserId: peerUserId,
                messageCursorAt: messageCursorAt,
                messageCursorId: messageCursorId,
                receiptCursorAt: receiptCursorAt,
                receiptCursorMessageId: receiptCursorMessageId,
                receiptCursorReaderId: receiptCursorReaderId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localConversationId,
                required String cloudConversationId,
                required String ownerUserId,
                required String peerUserId,
                Value<DateTime?> messageCursorAt = const Value.absent(),
                Value<String?> messageCursorId = const Value.absent(),
                Value<DateTime?> receiptCursorAt = const Value.absent(),
                Value<String?> receiptCursorMessageId = const Value.absent(),
                Value<String?> receiptCursorReaderId = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CloudConversationLinksCompanion.insert(
                localConversationId: localConversationId,
                cloudConversationId: cloudConversationId,
                ownerUserId: ownerUserId,
                peerUserId: peerUserId,
                messageCursorAt: messageCursorAt,
                messageCursorId: messageCursorId,
                receiptCursorAt: receiptCursorAt,
                receiptCursorMessageId: receiptCursorMessageId,
                receiptCursorReaderId: receiptCursorReaderId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $CloudConversationLinksTable,
                    CloudConversationLink
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CloudConversationLinksTable,
                    CloudConversationLink
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CloudConversationLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CloudConversationLinksTable,
      CloudConversationLink,
      $$CloudConversationLinksTableFilterComposer,
      $$CloudConversationLinksTableOrderingComposer,
      $$CloudConversationLinksTableAnnotationComposer,
      $$CloudConversationLinksTableCreateCompanionBuilder,
      $$CloudConversationLinksTableUpdateCompanionBuilder,
      (
        CloudConversationLink,
        BaseReferences<
          _$AppDatabase,
          $CloudConversationLinksTable,
          CloudConversationLink
        >,
      ),
      CloudConversationLink,
      PrefetchHooks Function()
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String id,
      required String conversationId,
      required String senderId,
      Value<String?> senderDeviceId,
      required String messageType,
      required String content,
      required DateTime createdAt,
      required DateTime updatedAt,
      required String deliveryStatus,
      Value<String> cloudSyncStatus,
      required bool isOutgoing,
      Value<String?> localFilePath,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracy,
      Value<DateTime?> locationCapturedAt,
      Value<String?> nearbyMessageId,
      Value<DateTime?> readAt,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String> senderId,
      Value<String?> senderDeviceId,
      Value<String> messageType,
      Value<String> content,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> deliveryStatus,
      Value<String> cloudSyncStatus,
      Value<bool> isOutgoing,
      Value<String?> localFilePath,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracy,
      Value<DateTime?> locationCapturedAt,
      Value<String?> nearbyMessageId,
      Value<DateTime?> readAt,
      Value<int> rowid,
    });

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderDeviceId => $composableBuilder(
    column: $table.senderDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudSyncStatus => $composableBuilder(
    column: $table.cloudSyncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get locationAccuracy => $composableBuilder(
    column: $table.locationAccuracy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get locationCapturedAt => $composableBuilder(
    column: $table.locationCapturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nearbyMessageId => $composableBuilder(
    column: $table.nearbyMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderDeviceId => $composableBuilder(
    column: $table.senderDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudSyncStatus => $composableBuilder(
    column: $table.cloudSyncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get locationAccuracy => $composableBuilder(
    column: $table.locationAccuracy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get locationCapturedAt => $composableBuilder(
    column: $table.locationCapturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nearbyMessageId => $composableBuilder(
    column: $table.nearbyMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get senderDeviceId => $composableBuilder(
    column: $table.senderDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudSyncStatus => $composableBuilder(
    column: $table.cloudSyncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get locationAccuracy => $composableBuilder(
    column: $table.locationAccuracy,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get locationCapturedAt => $composableBuilder(
    column: $table.locationCapturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nearbyMessageId => $composableBuilder(
    column: $table.nearbyMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
          Message,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<String?> senderDeviceId = const Value.absent(),
                Value<String> messageType = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> deliveryStatus = const Value.absent(),
                Value<String> cloudSyncStatus = const Value.absent(),
                Value<bool> isOutgoing = const Value.absent(),
                Value<String?> localFilePath = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracy = const Value.absent(),
                Value<DateTime?> locationCapturedAt = const Value.absent(),
                Value<String?> nearbyMessageId = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                senderDeviceId: senderDeviceId,
                messageType: messageType,
                content: content,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deliveryStatus: deliveryStatus,
                cloudSyncStatus: cloudSyncStatus,
                isOutgoing: isOutgoing,
                localFilePath: localFilePath,
                latitude: latitude,
                longitude: longitude,
                locationAccuracy: locationAccuracy,
                locationCapturedAt: locationCapturedAt,
                nearbyMessageId: nearbyMessageId,
                readAt: readAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String senderId,
                Value<String?> senderDeviceId = const Value.absent(),
                required String messageType,
                required String content,
                required DateTime createdAt,
                required DateTime updatedAt,
                required String deliveryStatus,
                Value<String> cloudSyncStatus = const Value.absent(),
                required bool isOutgoing,
                Value<String?> localFilePath = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracy = const Value.absent(),
                Value<DateTime?> locationCapturedAt = const Value.absent(),
                Value<String?> nearbyMessageId = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                senderDeviceId: senderDeviceId,
                messageType: messageType,
                content: content,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deliveryStatus: deliveryStatus,
                cloudSyncStatus: cloudSyncStatus,
                isOutgoing: isOutgoing,
                localFilePath: localFilePath,
                latitude: latitude,
                longitude: longitude,
                locationAccuracy: locationAccuracy,
                locationCapturedAt: locationCapturedAt,
                nearbyMessageId: nearbyMessageId,
                readAt: readAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, Message>(table),
                  BaseReferences<_$AppDatabase, $MessagesTable, Message>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
      Message,
      PrefetchHooks Function()
    >;
typedef $$NearbyDevicesTableCreateCompanionBuilder =
    NearbyDevicesCompanion Function({
      required String deviceId,
      required String displayName,
      required String status,
      required DateTime lastSeenAt,
      Value<int?> signalQuality,
      Value<int?> approxDistance,
      Value<bool> isTrusted,
      Value<bool> isBlocked,
      Value<bool> autoReconnectEnabled,
      Value<String?> publicIdentityKey,
      Value<String?> publicIdentityFingerprint,
      Value<int?> batteryLevel,
      Value<bool?> isCharging,
      Value<DateTime?> batteryUpdatedAt,
      Value<double?> peerLatitude,
      Value<double?> peerLongitude,
      Value<double?> peerLocationAccuracy,
      Value<DateTime?> peerLocationCapturedAt,
      Value<String?> peerDeviceModel,
      Value<int> rowid,
    });
typedef $$NearbyDevicesTableUpdateCompanionBuilder =
    NearbyDevicesCompanion Function({
      Value<String> deviceId,
      Value<String> displayName,
      Value<String> status,
      Value<DateTime> lastSeenAt,
      Value<int?> signalQuality,
      Value<int?> approxDistance,
      Value<bool> isTrusted,
      Value<bool> isBlocked,
      Value<bool> autoReconnectEnabled,
      Value<String?> publicIdentityKey,
      Value<String?> publicIdentityFingerprint,
      Value<int?> batteryLevel,
      Value<bool?> isCharging,
      Value<DateTime?> batteryUpdatedAt,
      Value<double?> peerLatitude,
      Value<double?> peerLongitude,
      Value<double?> peerLocationAccuracy,
      Value<DateTime?> peerLocationCapturedAt,
      Value<String?> peerDeviceModel,
      Value<int> rowid,
    });

class $$NearbyDevicesTableFilterComposer
    extends Composer<_$AppDatabase, $NearbyDevicesTable> {
  $$NearbyDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get signalQuality => $composableBuilder(
    column: $table.signalQuality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get approxDistance => $composableBuilder(
    column: $table.approxDistance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isTrusted => $composableBuilder(
    column: $table.isTrusted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBlocked => $composableBuilder(
    column: $table.isBlocked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoReconnectEnabled => $composableBuilder(
    column: $table.autoReconnectEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicIdentityKey => $composableBuilder(
    column: $table.publicIdentityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicIdentityFingerprint => $composableBuilder(
    column: $table.publicIdentityFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get batteryLevel => $composableBuilder(
    column: $table.batteryLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCharging => $composableBuilder(
    column: $table.isCharging,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get batteryUpdatedAt => $composableBuilder(
    column: $table.batteryUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get peerLatitude => $composableBuilder(
    column: $table.peerLatitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get peerLongitude => $composableBuilder(
    column: $table.peerLongitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get peerLocationAccuracy => $composableBuilder(
    column: $table.peerLocationAccuracy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get peerLocationCapturedAt => $composableBuilder(
    column: $table.peerLocationCapturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDeviceModel => $composableBuilder(
    column: $table.peerDeviceModel,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NearbyDevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $NearbyDevicesTable> {
  $$NearbyDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get signalQuality => $composableBuilder(
    column: $table.signalQuality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get approxDistance => $composableBuilder(
    column: $table.approxDistance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isTrusted => $composableBuilder(
    column: $table.isTrusted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBlocked => $composableBuilder(
    column: $table.isBlocked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoReconnectEnabled => $composableBuilder(
    column: $table.autoReconnectEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicIdentityKey => $composableBuilder(
    column: $table.publicIdentityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicIdentityFingerprint => $composableBuilder(
    column: $table.publicIdentityFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get batteryLevel => $composableBuilder(
    column: $table.batteryLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCharging => $composableBuilder(
    column: $table.isCharging,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get batteryUpdatedAt => $composableBuilder(
    column: $table.batteryUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get peerLatitude => $composableBuilder(
    column: $table.peerLatitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get peerLongitude => $composableBuilder(
    column: $table.peerLongitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get peerLocationAccuracy => $composableBuilder(
    column: $table.peerLocationAccuracy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get peerLocationCapturedAt => $composableBuilder(
    column: $table.peerLocationCapturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDeviceModel => $composableBuilder(
    column: $table.peerDeviceModel,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NearbyDevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NearbyDevicesTable> {
  $$NearbyDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get signalQuality => $composableBuilder(
    column: $table.signalQuality,
    builder: (column) => column,
  );

  GeneratedColumn<int> get approxDistance => $composableBuilder(
    column: $table.approxDistance,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isTrusted =>
      $composableBuilder(column: $table.isTrusted, builder: (column) => column);

  GeneratedColumn<bool> get isBlocked =>
      $composableBuilder(column: $table.isBlocked, builder: (column) => column);

  GeneratedColumn<bool> get autoReconnectEnabled => $composableBuilder(
    column: $table.autoReconnectEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get publicIdentityKey => $composableBuilder(
    column: $table.publicIdentityKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get publicIdentityFingerprint => $composableBuilder(
    column: $table.publicIdentityFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get batteryLevel => $composableBuilder(
    column: $table.batteryLevel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCharging => $composableBuilder(
    column: $table.isCharging,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get batteryUpdatedAt => $composableBuilder(
    column: $table.batteryUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get peerLatitude => $composableBuilder(
    column: $table.peerLatitude,
    builder: (column) => column,
  );

  GeneratedColumn<double> get peerLongitude => $composableBuilder(
    column: $table.peerLongitude,
    builder: (column) => column,
  );

  GeneratedColumn<double> get peerLocationAccuracy => $composableBuilder(
    column: $table.peerLocationAccuracy,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get peerLocationCapturedAt => $composableBuilder(
    column: $table.peerLocationCapturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerDeviceModel => $composableBuilder(
    column: $table.peerDeviceModel,
    builder: (column) => column,
  );
}

class $$NearbyDevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NearbyDevicesTable,
          NearbyDevice,
          $$NearbyDevicesTableFilterComposer,
          $$NearbyDevicesTableOrderingComposer,
          $$NearbyDevicesTableAnnotationComposer,
          $$NearbyDevicesTableCreateCompanionBuilder,
          $$NearbyDevicesTableUpdateCompanionBuilder,
          (
            NearbyDevice,
            BaseReferences<_$AppDatabase, $NearbyDevicesTable, NearbyDevice>,
          ),
          NearbyDevice,
          PrefetchHooks Function()
        > {
  $$NearbyDevicesTableTableManager(_$AppDatabase db, $NearbyDevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NearbyDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NearbyDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NearbyDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<int?> signalQuality = const Value.absent(),
                Value<int?> approxDistance = const Value.absent(),
                Value<bool> isTrusted = const Value.absent(),
                Value<bool> isBlocked = const Value.absent(),
                Value<bool> autoReconnectEnabled = const Value.absent(),
                Value<String?> publicIdentityKey = const Value.absent(),
                Value<String?> publicIdentityFingerprint = const Value.absent(),
                Value<int?> batteryLevel = const Value.absent(),
                Value<bool?> isCharging = const Value.absent(),
                Value<DateTime?> batteryUpdatedAt = const Value.absent(),
                Value<double?> peerLatitude = const Value.absent(),
                Value<double?> peerLongitude = const Value.absent(),
                Value<double?> peerLocationAccuracy = const Value.absent(),
                Value<DateTime?> peerLocationCapturedAt = const Value.absent(),
                Value<String?> peerDeviceModel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NearbyDevicesCompanion(
                deviceId: deviceId,
                displayName: displayName,
                status: status,
                lastSeenAt: lastSeenAt,
                signalQuality: signalQuality,
                approxDistance: approxDistance,
                isTrusted: isTrusted,
                isBlocked: isBlocked,
                autoReconnectEnabled: autoReconnectEnabled,
                publicIdentityKey: publicIdentityKey,
                publicIdentityFingerprint: publicIdentityFingerprint,
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                batteryUpdatedAt: batteryUpdatedAt,
                peerLatitude: peerLatitude,
                peerLongitude: peerLongitude,
                peerLocationAccuracy: peerLocationAccuracy,
                peerLocationCapturedAt: peerLocationCapturedAt,
                peerDeviceModel: peerDeviceModel,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required String displayName,
                required String status,
                required DateTime lastSeenAt,
                Value<int?> signalQuality = const Value.absent(),
                Value<int?> approxDistance = const Value.absent(),
                Value<bool> isTrusted = const Value.absent(),
                Value<bool> isBlocked = const Value.absent(),
                Value<bool> autoReconnectEnabled = const Value.absent(),
                Value<String?> publicIdentityKey = const Value.absent(),
                Value<String?> publicIdentityFingerprint = const Value.absent(),
                Value<int?> batteryLevel = const Value.absent(),
                Value<bool?> isCharging = const Value.absent(),
                Value<DateTime?> batteryUpdatedAt = const Value.absent(),
                Value<double?> peerLatitude = const Value.absent(),
                Value<double?> peerLongitude = const Value.absent(),
                Value<double?> peerLocationAccuracy = const Value.absent(),
                Value<DateTime?> peerLocationCapturedAt = const Value.absent(),
                Value<String?> peerDeviceModel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NearbyDevicesCompanion.insert(
                deviceId: deviceId,
                displayName: displayName,
                status: status,
                lastSeenAt: lastSeenAt,
                signalQuality: signalQuality,
                approxDistance: approxDistance,
                isTrusted: isTrusted,
                isBlocked: isBlocked,
                autoReconnectEnabled: autoReconnectEnabled,
                publicIdentityKey: publicIdentityKey,
                publicIdentityFingerprint: publicIdentityFingerprint,
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                batteryUpdatedAt: batteryUpdatedAt,
                peerLatitude: peerLatitude,
                peerLongitude: peerLongitude,
                peerLocationAccuracy: peerLocationAccuracy,
                peerLocationCapturedAt: peerLocationCapturedAt,
                peerDeviceModel: peerDeviceModel,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NearbyDevicesTable, NearbyDevice>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $NearbyDevicesTable,
                    NearbyDevice
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NearbyDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NearbyDevicesTable,
      NearbyDevice,
      $$NearbyDevicesTableFilterComposer,
      $$NearbyDevicesTableOrderingComposer,
      $$NearbyDevicesTableAnnotationComposer,
      $$NearbyDevicesTableCreateCompanionBuilder,
      $$NearbyDevicesTableUpdateCompanionBuilder,
      (
        NearbyDevice,
        BaseReferences<_$AppDatabase, $NearbyDevicesTable, NearbyDevice>,
      ),
      NearbyDevice,
      PrefetchHooks Function()
    >;
typedef $$SyncQueueTableCreateCompanionBuilder =
    SyncQueueCompanion Function({
      required String id,
      required String entityType,
      required String entityId,
      required String operation,
      required String status,
      Value<int> attemptCount,
      Value<String?> lastError,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> nextAttemptAt,
      Value<String?> ownerUserId,
      Value<int> rowid,
    });
typedef $$SyncQueueTableUpdateCompanionBuilder =
    SyncQueueCompanion Function({
      Value<String> id,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String> status,
      Value<int> attemptCount,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> nextAttemptAt,
      Value<String?> ownerUserId,
      Value<int> rowid,
    });

class $$SyncQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );
}

class $$SyncQueueTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncQueueTable,
          SyncQueueData,
          $$SyncQueueTableFilterComposer,
          $$SyncQueueTableOrderingComposer,
          $$SyncQueueTableAnnotationComposer,
          $$SyncQueueTableCreateCompanionBuilder,
          $$SyncQueueTableUpdateCompanionBuilder,
          (
            SyncQueueData,
            BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>,
          ),
          SyncQueueData,
          PrefetchHooks Function()
        > {
  $$SyncQueueTableTableManager(_$AppDatabase db, $SyncQueueTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> ownerUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueCompanion(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                status: status,
                attemptCount: attemptCount,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                nextAttemptAt: nextAttemptAt,
                ownerUserId: ownerUserId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entityType,
                required String entityId,
                required String operation,
                required String status,
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> ownerUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueCompanion.insert(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                status: status,
                attemptCount: attemptCount,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                nextAttemptAt: nextAttemptAt,
                ownerUserId: ownerUserId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncQueueTable, SyncQueueData>(table),
                  BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncQueueTable,
      SyncQueueData,
      $$SyncQueueTableFilterComposer,
      $$SyncQueueTableOrderingComposer,
      $$SyncQueueTableAnnotationComposer,
      $$SyncQueueTableCreateCompanionBuilder,
      $$SyncQueueTableUpdateCompanionBuilder,
      (
        SyncQueueData,
        BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>,
      ),
      SyncQueueData,
      PrefetchHooks Function()
    >;
typedef $$SosEventsTableCreateCompanionBuilder =
    SosEventsCompanion Function({
      required String id,
      required String ownerDeviceId,
      required String ownerUserId,
      Value<String?> message,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracy,
      Value<DateTime?> locationCapturedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      required bool isActive,
      required String deliveryStatus,
      Value<int> rowid,
    });
typedef $$SosEventsTableUpdateCompanionBuilder =
    SosEventsCompanion Function({
      Value<String> id,
      Value<String> ownerDeviceId,
      Value<String> ownerUserId,
      Value<String?> message,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracy,
      Value<DateTime?> locationCapturedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isActive,
      Value<String> deliveryStatus,
      Value<int> rowid,
    });

class $$SosEventsTableFilterComposer
    extends Composer<_$AppDatabase, $SosEventsTable> {
  $$SosEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerDeviceId => $composableBuilder(
    column: $table.ownerDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get locationAccuracy => $composableBuilder(
    column: $table.locationAccuracy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get locationCapturedAt => $composableBuilder(
    column: $table.locationCapturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SosEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $SosEventsTable> {
  $$SosEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerDeviceId => $composableBuilder(
    column: $table.ownerDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get locationAccuracy => $composableBuilder(
    column: $table.locationAccuracy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get locationCapturedAt => $composableBuilder(
    column: $table.locationCapturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SosEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SosEventsTable> {
  $$SosEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerDeviceId => $composableBuilder(
    column: $table.ownerDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get locationAccuracy => $composableBuilder(
    column: $table.locationAccuracy,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get locationCapturedAt => $composableBuilder(
    column: $table.locationCapturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => column,
  );
}

class $$SosEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SosEventsTable,
          SosEvent,
          $$SosEventsTableFilterComposer,
          $$SosEventsTableOrderingComposer,
          $$SosEventsTableAnnotationComposer,
          $$SosEventsTableCreateCompanionBuilder,
          $$SosEventsTableUpdateCompanionBuilder,
          (SosEvent, BaseReferences<_$AppDatabase, $SosEventsTable, SosEvent>),
          SosEvent,
          PrefetchHooks Function()
        > {
  $$SosEventsTableTableManager(_$AppDatabase db, $SosEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SosEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SosEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SosEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerDeviceId = const Value.absent(),
                Value<String> ownerUserId = const Value.absent(),
                Value<String?> message = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracy = const Value.absent(),
                Value<DateTime?> locationCapturedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<String> deliveryStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SosEventsCompanion(
                id: id,
                ownerDeviceId: ownerDeviceId,
                ownerUserId: ownerUserId,
                message: message,
                latitude: latitude,
                longitude: longitude,
                locationAccuracy: locationAccuracy,
                locationCapturedAt: locationCapturedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isActive: isActive,
                deliveryStatus: deliveryStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerDeviceId,
                required String ownerUserId,
                Value<String?> message = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracy = const Value.absent(),
                Value<DateTime?> locationCapturedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                required bool isActive,
                required String deliveryStatus,
                Value<int> rowid = const Value.absent(),
              }) => SosEventsCompanion.insert(
                id: id,
                ownerDeviceId: ownerDeviceId,
                ownerUserId: ownerUserId,
                message: message,
                latitude: latitude,
                longitude: longitude,
                locationAccuracy: locationAccuracy,
                locationCapturedAt: locationCapturedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isActive: isActive,
                deliveryStatus: deliveryStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SosEventsTable, SosEvent>(table),
                  BaseReferences<_$AppDatabase, $SosEventsTable, SosEvent>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SosEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SosEventsTable,
      SosEvent,
      $$SosEventsTableFilterComposer,
      $$SosEventsTableOrderingComposer,
      $$SosEventsTableAnnotationComposer,
      $$SosEventsTableCreateCompanionBuilder,
      $$SosEventsTableUpdateCompanionBuilder,
      (SosEvent, BaseReferences<_$AppDatabase, $SosEventsTable, SosEvent>),
      SosEvent,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$AttachmentsTableCreateCompanionBuilder =
    AttachmentsCompanion Function({
      required String id,
      required String messageId,
      required String transferId,
      required String mediaType,
      required String fileName,
      required String mimeType,
      required String localPath,
      Value<String?> remoteFileName,
      required int byteSize,
      Value<int> bytesTransferred,
      required String transferStatus,
      Value<String> cloudMetadataStatus,
      Value<String> cloudFileStatus,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<String?> errorCode,
      Value<String?> checksumSha256,
      Value<int> rowid,
    });
typedef $$AttachmentsTableUpdateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<String> id,
      Value<String> messageId,
      Value<String> transferId,
      Value<String> mediaType,
      Value<String> fileName,
      Value<String> mimeType,
      Value<String> localPath,
      Value<String?> remoteFileName,
      Value<int> byteSize,
      Value<int> bytesTransferred,
      Value<String> transferStatus,
      Value<String> cloudMetadataStatus,
      Value<String> cloudFileStatus,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<String?> errorCode,
      Value<String?> checksumSha256,
      Value<int> rowid,
    });

class $$AttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteFileName => $composableBuilder(
    column: $table.remoteFileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytesTransferred => $composableBuilder(
    column: $table.bytesTransferred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferStatus => $composableBuilder(
    column: $table.transferStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudMetadataStatus => $composableBuilder(
    column: $table.cloudMetadataStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudFileStatus => $composableBuilder(
    column: $table.cloudFileStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksumSha256 => $composableBuilder(
    column: $table.checksumSha256,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteFileName => $composableBuilder(
    column: $table.remoteFileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytesTransferred => $composableBuilder(
    column: $table.bytesTransferred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferStatus => $composableBuilder(
    column: $table.transferStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudMetadataStatus => $composableBuilder(
    column: $table.cloudMetadataStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudFileStatus => $composableBuilder(
    column: $table.cloudFileStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksumSha256 => $composableBuilder(
    column: $table.checksumSha256,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get remoteFileName => $composableBuilder(
    column: $table.remoteFileName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<int> get bytesTransferred => $composableBuilder(
    column: $table.bytesTransferred,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transferStatus => $composableBuilder(
    column: $table.transferStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudMetadataStatus => $composableBuilder(
    column: $table.cloudMetadataStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudFileStatus => $composableBuilder(
    column: $table.cloudFileStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get checksumSha256 => $composableBuilder(
    column: $table.checksumSha256,
    builder: (column) => column,
  );
}

class $$AttachmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AttachmentsTable,
          Attachment,
          $$AttachmentsTableFilterComposer,
          $$AttachmentsTableOrderingComposer,
          $$AttachmentsTableAnnotationComposer,
          $$AttachmentsTableCreateCompanionBuilder,
          $$AttachmentsTableUpdateCompanionBuilder,
          (
            Attachment,
            BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>,
          ),
          Attachment,
          PrefetchHooks Function()
        > {
  $$AttachmentsTableTableManager(_$AppDatabase db, $AttachmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> transferId = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<String?> remoteFileName = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int> bytesTransferred = const Value.absent(),
                Value<String> transferStatus = const Value.absent(),
                Value<String> cloudMetadataStatus = const Value.absent(),
                Value<String> cloudFileStatus = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> checksumSha256 = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion(
                id: id,
                messageId: messageId,
                transferId: transferId,
                mediaType: mediaType,
                fileName: fileName,
                mimeType: mimeType,
                localPath: localPath,
                remoteFileName: remoteFileName,
                byteSize: byteSize,
                bytesTransferred: bytesTransferred,
                transferStatus: transferStatus,
                cloudMetadataStatus: cloudMetadataStatus,
                cloudFileStatus: cloudFileStatus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                width: width,
                height: height,
                durationMs: durationMs,
                errorCode: errorCode,
                checksumSha256: checksumSha256,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String messageId,
                required String transferId,
                required String mediaType,
                required String fileName,
                required String mimeType,
                required String localPath,
                Value<String?> remoteFileName = const Value.absent(),
                required int byteSize,
                Value<int> bytesTransferred = const Value.absent(),
                required String transferStatus,
                Value<String> cloudMetadataStatus = const Value.absent(),
                Value<String> cloudFileStatus = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> checksumSha256 = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion.insert(
                id: id,
                messageId: messageId,
                transferId: transferId,
                mediaType: mediaType,
                fileName: fileName,
                mimeType: mimeType,
                localPath: localPath,
                remoteFileName: remoteFileName,
                byteSize: byteSize,
                bytesTransferred: bytesTransferred,
                transferStatus: transferStatus,
                cloudMetadataStatus: cloudMetadataStatus,
                cloudFileStatus: cloudFileStatus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                width: width,
                height: height,
                durationMs: durationMs,
                errorCode: errorCode,
                checksumSha256: checksumSha256,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AttachmentsTable, Attachment>(table),
                  BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AttachmentsTable,
      Attachment,
      $$AttachmentsTableFilterComposer,
      $$AttachmentsTableOrderingComposer,
      $$AttachmentsTableAnnotationComposer,
      $$AttachmentsTableCreateCompanionBuilder,
      $$AttachmentsTableUpdateCompanionBuilder,
      (
        Attachment,
        BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>,
      ),
      Attachment,
      PrefetchHooks Function()
    >;
typedef $$RelayPacketsTableCreateCompanionBuilder =
    RelayPacketsCompanion Function({
      required String packetId,
      required String originDeviceId,
      required String destinationDeviceId,
      required String payloadType,
      required String payloadId,
      required DateTime createdAt,
      required DateTime expiresAt,
      required int hopCount,
      required int maxHops,
      required int priority,
      Value<String?> previousHopDeviceId,
      required String protocol,
      required String payloadJson,
      required String state,
      required DateTime storedAt,
      Value<int> rowid,
    });
typedef $$RelayPacketsTableUpdateCompanionBuilder =
    RelayPacketsCompanion Function({
      Value<String> packetId,
      Value<String> originDeviceId,
      Value<String> destinationDeviceId,
      Value<String> payloadType,
      Value<String> payloadId,
      Value<DateTime> createdAt,
      Value<DateTime> expiresAt,
      Value<int> hopCount,
      Value<int> maxHops,
      Value<int> priority,
      Value<String?> previousHopDeviceId,
      Value<String> protocol,
      Value<String> payloadJson,
      Value<String> state,
      Value<DateTime> storedAt,
      Value<int> rowid,
    });

class $$RelayPacketsTableFilterComposer
    extends Composer<_$AppDatabase, $RelayPacketsTable> {
  $$RelayPacketsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get packetId => $composableBuilder(
    column: $table.packetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationDeviceId => $composableBuilder(
    column: $table.destinationDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadId => $composableBuilder(
    column: $table.payloadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hopCount => $composableBuilder(
    column: $table.hopCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxHops => $composableBuilder(
    column: $table.maxHops,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousHopDeviceId => $composableBuilder(
    column: $table.previousHopDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get storedAt => $composableBuilder(
    column: $table.storedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RelayPacketsTableOrderingComposer
    extends Composer<_$AppDatabase, $RelayPacketsTable> {
  $$RelayPacketsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get packetId => $composableBuilder(
    column: $table.packetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationDeviceId => $composableBuilder(
    column: $table.destinationDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadId => $composableBuilder(
    column: $table.payloadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hopCount => $composableBuilder(
    column: $table.hopCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxHops => $composableBuilder(
    column: $table.maxHops,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousHopDeviceId => $composableBuilder(
    column: $table.previousHopDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get storedAt => $composableBuilder(
    column: $table.storedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RelayPacketsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RelayPacketsTable> {
  $$RelayPacketsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get packetId =>
      $composableBuilder(column: $table.packetId, builder: (column) => column);

  GeneratedColumn<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationDeviceId => $composableBuilder(
    column: $table.destinationDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadId =>
      $composableBuilder(column: $table.payloadId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get hopCount =>
      $composableBuilder(column: $table.hopCount, builder: (column) => column);

  GeneratedColumn<int> get maxHops =>
      $composableBuilder(column: $table.maxHops, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get previousHopDeviceId => $composableBuilder(
    column: $table.previousHopDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get protocol =>
      $composableBuilder(column: $table.protocol, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get storedAt =>
      $composableBuilder(column: $table.storedAt, builder: (column) => column);
}

class $$RelayPacketsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RelayPacketsTable,
          RelayPacket,
          $$RelayPacketsTableFilterComposer,
          $$RelayPacketsTableOrderingComposer,
          $$RelayPacketsTableAnnotationComposer,
          $$RelayPacketsTableCreateCompanionBuilder,
          $$RelayPacketsTableUpdateCompanionBuilder,
          (
            RelayPacket,
            BaseReferences<_$AppDatabase, $RelayPacketsTable, RelayPacket>,
          ),
          RelayPacket,
          PrefetchHooks Function()
        > {
  $$RelayPacketsTableTableManager(_$AppDatabase db, $RelayPacketsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RelayPacketsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RelayPacketsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RelayPacketsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> packetId = const Value.absent(),
                Value<String> originDeviceId = const Value.absent(),
                Value<String> destinationDeviceId = const Value.absent(),
                Value<String> payloadType = const Value.absent(),
                Value<String> payloadId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<int> hopCount = const Value.absent(),
                Value<int> maxHops = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> previousHopDeviceId = const Value.absent(),
                Value<String> protocol = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> storedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RelayPacketsCompanion(
                packetId: packetId,
                originDeviceId: originDeviceId,
                destinationDeviceId: destinationDeviceId,
                payloadType: payloadType,
                payloadId: payloadId,
                createdAt: createdAt,
                expiresAt: expiresAt,
                hopCount: hopCount,
                maxHops: maxHops,
                priority: priority,
                previousHopDeviceId: previousHopDeviceId,
                protocol: protocol,
                payloadJson: payloadJson,
                state: state,
                storedAt: storedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String packetId,
                required String originDeviceId,
                required String destinationDeviceId,
                required String payloadType,
                required String payloadId,
                required DateTime createdAt,
                required DateTime expiresAt,
                required int hopCount,
                required int maxHops,
                required int priority,
                Value<String?> previousHopDeviceId = const Value.absent(),
                required String protocol,
                required String payloadJson,
                required String state,
                required DateTime storedAt,
                Value<int> rowid = const Value.absent(),
              }) => RelayPacketsCompanion.insert(
                packetId: packetId,
                originDeviceId: originDeviceId,
                destinationDeviceId: destinationDeviceId,
                payloadType: payloadType,
                payloadId: payloadId,
                createdAt: createdAt,
                expiresAt: expiresAt,
                hopCount: hopCount,
                maxHops: maxHops,
                priority: priority,
                previousHopDeviceId: previousHopDeviceId,
                protocol: protocol,
                payloadJson: payloadJson,
                state: state,
                storedAt: storedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RelayPacketsTable, RelayPacket>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RelayPacketsTable,
                    RelayPacket
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RelayPacketsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RelayPacketsTable,
      RelayPacket,
      $$RelayPacketsTableFilterComposer,
      $$RelayPacketsTableOrderingComposer,
      $$RelayPacketsTableAnnotationComposer,
      $$RelayPacketsTableCreateCompanionBuilder,
      $$RelayPacketsTableUpdateCompanionBuilder,
      (
        RelayPacket,
        BaseReferences<_$AppDatabase, $RelayPacketsTable, RelayPacket>,
      ),
      RelayPacket,
      PrefetchHooks Function()
    >;
typedef $$RelayForwardHistoryTableCreateCompanionBuilder =
    RelayForwardHistoryCompanion Function({
      required String packetId,
      required String targetDeviceId,
      required String targetEndpointId,
      required String status,
      Value<int> attemptCount,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RelayForwardHistoryTableUpdateCompanionBuilder =
    RelayForwardHistoryCompanion Function({
      Value<String> packetId,
      Value<String> targetDeviceId,
      Value<String> targetEndpointId,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$RelayForwardHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $RelayForwardHistoryTable> {
  $$RelayForwardHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get packetId => $composableBuilder(
    column: $table.packetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetDeviceId => $composableBuilder(
    column: $table.targetDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetEndpointId => $composableBuilder(
    column: $table.targetEndpointId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RelayForwardHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $RelayForwardHistoryTable> {
  $$RelayForwardHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get packetId => $composableBuilder(
    column: $table.packetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetDeviceId => $composableBuilder(
    column: $table.targetDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetEndpointId => $composableBuilder(
    column: $table.targetEndpointId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RelayForwardHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $RelayForwardHistoryTable> {
  $$RelayForwardHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get packetId =>
      $composableBuilder(column: $table.packetId, builder: (column) => column);

  GeneratedColumn<String> get targetDeviceId => $composableBuilder(
    column: $table.targetDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetEndpointId => $composableBuilder(
    column: $table.targetEndpointId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RelayForwardHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RelayForwardHistoryTable,
          RelayForwardHistoryData,
          $$RelayForwardHistoryTableFilterComposer,
          $$RelayForwardHistoryTableOrderingComposer,
          $$RelayForwardHistoryTableAnnotationComposer,
          $$RelayForwardHistoryTableCreateCompanionBuilder,
          $$RelayForwardHistoryTableUpdateCompanionBuilder,
          (
            RelayForwardHistoryData,
            BaseReferences<
              _$AppDatabase,
              $RelayForwardHistoryTable,
              RelayForwardHistoryData
            >,
          ),
          RelayForwardHistoryData,
          PrefetchHooks Function()
        > {
  $$RelayForwardHistoryTableTableManager(
    _$AppDatabase db,
    $RelayForwardHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RelayForwardHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RelayForwardHistoryTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RelayForwardHistoryTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> packetId = const Value.absent(),
                Value<String> targetDeviceId = const Value.absent(),
                Value<String> targetEndpointId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RelayForwardHistoryCompanion(
                packetId: packetId,
                targetDeviceId: targetDeviceId,
                targetEndpointId: targetEndpointId,
                status: status,
                attemptCount: attemptCount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String packetId,
                required String targetDeviceId,
                required String targetEndpointId,
                required String status,
                Value<int> attemptCount = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RelayForwardHistoryCompanion.insert(
                packetId: packetId,
                targetDeviceId: targetDeviceId,
                targetEndpointId: targetEndpointId,
                status: status,
                attemptCount: attemptCount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $RelayForwardHistoryTable,
                    RelayForwardHistoryData
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RelayForwardHistoryTable,
                    RelayForwardHistoryData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RelayForwardHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RelayForwardHistoryTable,
      RelayForwardHistoryData,
      $$RelayForwardHistoryTableFilterComposer,
      $$RelayForwardHistoryTableOrderingComposer,
      $$RelayForwardHistoryTableAnnotationComposer,
      $$RelayForwardHistoryTableCreateCompanionBuilder,
      $$RelayForwardHistoryTableUpdateCompanionBuilder,
      (
        RelayForwardHistoryData,
        BaseReferences<
          _$AppDatabase,
          $RelayForwardHistoryTable,
          RelayForwardHistoryData
        >,
      ),
      RelayForwardHistoryData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$CloudConversationLinksTableTableManager get cloudConversationLinks =>
      $$CloudConversationLinksTableTableManager(
        _db,
        _db.cloudConversationLinks,
      );
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$NearbyDevicesTableTableManager get nearbyDevices =>
      $$NearbyDevicesTableTableManager(_db, _db.nearbyDevices);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db, _db.syncQueue);
  $$SosEventsTableTableManager get sosEvents =>
      $$SosEventsTableTableManager(_db, _db.sosEvents);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db, _db.attachments);
  $$RelayPacketsTableTableManager get relayPackets =>
      $$RelayPacketsTableTableManager(_db, _db.relayPackets);
  $$RelayForwardHistoryTableTableManager get relayForwardHistory =>
      $$RelayForwardHistoryTableTableManager(_db, _db.relayForwardHistory);
}
