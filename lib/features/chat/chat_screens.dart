// หน้ารายการสนทนาและห้องแชต รวมการแสดงสถานะข้อความและการส่งเนื้อหาผ่านขอบเขต repository
import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
import '../../data/mock_data.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/location/location_service.dart';
import '../../core/presentation/peer_connection_presence.dart';
import '../../core/presentation/live_route_presentation.dart';
import '../../data/models/prototype_models.dart';
import 'chat_location_navigation.dart';
import 'chat_date_separator.dart';
import '../../shared/widgets/relio_widgets.dart';

// แสดงรายการบทสนทนาจากข้อมูล local และตัวอย่างที่กำหนดไว้ใน data layer
// สถานะ Nearby, Cloud และการอ่านเป็นข้อมูลคนละมิติของข้อความ
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = RelioDependencyScope.of(context);
    final repositories = dependencies.repositories;
    final nearby = dependencies.nearbyService;
    final listUpdates = Listenable.merge([
      nearby,
      dependencies.internalExperience,
    ]);
    return Scaffold(
      appBar: const RelioAppBar(
        title: 'แชท',
        subtitle: 'ข้อความ Nearby และ SOS',
      ),
      body: AnimatedBuilder(
        animation: listUpdates,
        builder: (context, _) => StreamBuilder<List<RelioConversation>>(
          stream: repositories.conversations.watchConversations(),
          builder: (context, snapshot) {
            final allConversations =
                snapshot.data ?? const <RelioConversation>[];
            return FutureBuilder<Map<String, PeerConnectionPresence>>(
              future: () async {
                final entries = await Future.wait(
                  allConversations.map((conversation) async {
                    final principal = await repositories.conversations
                        .remotePrincipalForConversation(conversation.id);
                    return MapEntry(
                      conversation.id,
                      chatReachabilityFor(
                        nearby,
                        conversation.participantId,
                        principal: principal,
                      ),
                    );
                  }),
                );
                return Map.fromEntries(entries);
              }(),
              builder: (context, resolved) {
                final presence = {
                  for (final c in allConversations)
                    c.id:
                        resolved.data?[c.id] ?? PeerConnectionPresence.unknown,
                };
                final real = allConversations
                    .where(
                      (conversation) =>
                          !RelioMockData.isDemoId(conversation.participantId),
                    )
                    .toList();
                final conversations = [
                  ...real.where(
                    (conversation) =>
                        presence[conversation.id] ==
                        PeerConnectionPresence.online,
                  ),
                  ...real.where(
                    (conversation) =>
                        presence[conversation.id] !=
                        PeerConnectionPresence.online,
                  ),
                  if (dependencies.internalExperience.demoEnabled)
                    ...allConversations.where(
                      (conversation) =>
                          RelioMockData.isDemoId(conversation.participantId),
                    ),
                ];
                if (conversations.isEmpty) {
                  return const RelioEmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'ยังไม่มีบทสนทนา',
                    subtitle: 'บทสนทนาจะถูกบันทึกไว้ในเครื่องนี้',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    RelioSpacing.lg,
                    12,
                    RelioSpacing.lg,
                    24,
                  ),
                  itemCount: conversations.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    return RelioChatListTile(
                      chat: _preview(
                        conversation,
                        presence[conversation.id]!,
                        nearby.avatarPathFor(conversation.participantId),
                      ),
                      onTap: () => context.push('/chat/${conversation.id}'),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  RelioChatPreview _preview(
    RelioConversation conversation,
    PeerConnectionPresence presence,
    String? avatarPath,
  ) => RelioChatPreview(
    id: conversation.id,
    name: conversation.displayName,
    message: _chatListPreview(conversation.lastMessageText),
    time: conversation.lastMessageAt == null
        ? ''
        : '${conversation.lastMessageAt!.hour.toString().padLeft(2, '0')}:${conversation.lastMessageAt!.minute.toString().padLeft(2, '0')}',
    status: conversation.participantStatus,
    unread: conversation.unreadCount,
    isDemo: RelioMockData.isDemoId(conversation.participantId),
    identityKey: conversation.participantId,
    presence: presence,
    avatarPath: avatarPath,
  );
}

String _chatListPreview(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return 'เริ่มการสนทนา Nearby';
  final lower = text.toLowerCase();
  if (RegExp(r'\.(jpe?g|png|webp|gif)$').hasMatch(lower)) {
    return '📷 รูปภาพ';
  }
  if (RegExp(r'\.(mp4|mov|m4v|webm)$').hasMatch(lower)) {
    return '▶ วิดีโอ';
  }
  final hasPath = text.contains('/') || text.contains('\\');
  final looksLikeId = RegExp(
    r'\b[0-9a-f]{8}-[0-9a-f-]{27,}\b|\b[0-9a-f]{32,}\b',
    caseSensitive: false,
  ).hasMatch(text);
  final looksLikeMetadata =
      text.startsWith('{') ||
      text.startsWith('[') ||
      lower.startsWith('file:') ||
      lower.startsWith('content:') ||
      lower.contains('transferid');
  if (hasPath || looksLikeId || looksLikeMetadata) return '📎 ไฟล์แนบ';
  return text;
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Chat Room Screen
class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({required this.chatId, super.key});

  final String chatId;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Chat Room Screen State)
class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  RelioDevice? _demoDevice;
  late Stream<List<RelioMessage>> _messagesStream;
  String? _persistedPeerName;
  String? _persistedPeerDeviceId;
  String? _persistedRemotePrincipal;
  RelioDependencies? _dependencies;
  String? _resolvedChatId;
  bool _routeResolutionStarted = false;
  bool _routeResolved = false;
  StreamSubscription<Object?>? _ownerSubscription;
  StreamSubscription<List<RelioConversation>>? _titleSubscription;
  int _routeGeneration = 0;

  String get _activeChatId => _resolvedChatId ?? widget.chatId;

  @override
  void initState() {
    super.initState();
    for (final device in RelioMockData.devices) {
      if (device.id == widget.chatId) _demoDevice = device;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependencies = RelioDependencyScope.of(context);
    if (_routeResolutionStarted) return;
    _routeResolutionStarted = true;
    _ownerSubscription = _dependencies!.repositories.ownerContext.changes
        .listen((_) {
          if (!mounted) return;
          _routeGeneration++;
          _dependencies!.nearbyService.setActiveConversation(null);
          setState(() {
            _resolvedChatId = null;
            _persistedPeerName = null;
            _persistedPeerDeviceId = null;
            _persistedRemotePrincipal = null;
            _demoDevice = null;
            _routeResolved = false;
            _messagesStream = Stream.value(const []);
            _composer.clear();
          });
          unawaited(_resolveChatRoute());
        });
    _titleSubscription = _dependencies!.repositories.conversations
        .watchConversations()
        .listen((rows) {
          if (!mounted || !_routeResolved) return;
          for (final row in rows) {
            if (row.id == _resolvedChatId &&
                row.displayName != _persistedPeerName) {
              setState(() => _persistedPeerName = row.displayName);
            }
          }
        });
    _messagesStream = _dependencies!.repositories.messages.watchMessages(
      widget.chatId,
    );
    unawaited(_resolveChatRoute());
  }

  // แปลง route ที่อาจใช้รหัสอุปกรณ์ให้เป็นบทสนทนาของ principal ปัจจุบันก่อนอ่านข้อมูล
  Future<void> _resolveChatRoute() async {
    final dependencies = _dependencies!;
    final generation = _routeGeneration;
    final owner = dependencies.repositories.ownerContext.capture();
    RelioConversation conversation;
    try {
      conversation = await dependencies.repositories.conversations
          .resolveRouteTarget(widget.chatId);
    } on Object {
      return;
    }
    final remotePrincipal = await dependencies.repositories.conversations
        .remotePrincipalForConversation(conversation.id);
    if (!mounted ||
        generation != _routeGeneration ||
        !dependencies.repositories.ownerContext.isCurrent(owner)) {
      return;
    }
    setState(() {
      _resolvedChatId = conversation.id;
      _routeResolved = true;
      _persistedPeerName = conversation.displayName;
      _persistedPeerDeviceId = conversation.participantId;
      _persistedRemotePrincipal = remotePrincipal;
      _messagesStream = dependencies.repositories.messages.watchMessages(
        conversation.id,
      );
    });
    dependencies.nearbyService.setActiveConversation(conversation.id);
    await _markConversationRead();
  }

  Future<void> _markConversationRead() => RelioDependencyScope.of(context)
      .repositories
      .ownerContext
      .run(() => _markConversationReadOwned())
      .catchError((Object _) {});

  Future<void> _markConversationReadOwned() async {
    final dependencies = _dependencies;
    if (dependencies == null) return;
    final conversation = await dependencies.repositories.conversations
        .getConversation(_activeChatId);
    final peerDeviceId = conversation?.participantId ?? _activeChatId;
    final messageIds = await dependencies.repositories.messages
        .markConversationRead(_activeChatId);
    for (final messageId in messageIds) {
      await dependencies.nearbyService.sendReadReceipt(
        messageId: messageId,
        peerDeviceId: peerDeviceId,
      );
    }
    await dependencies.syncEngine.queueReadReceipts(
      localConversationId: _activeChatId,
      messageIds: messageIds,
    );
  }

  @override
  void dispose() {
    _dependencies?.nearbyService.setActiveConversation(null);
    _ownerSubscription?.cancel();
    _titleSubscription?.cancel();
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() => RelioDependencyScope.of(
    context,
  ).repositories.ownerContext.run(() => _sendOwned()).catchError((Object _) {});

  Future<void> _sendOwned() async {
    if (!_routeResolved) return;
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final dependencies = RelioDependencyScope.of(context);
    try {
      final deviceId = await dependencies.identity.getDeviceId();
      // บันทึกผ่าน Repository ก่อนส่ง Nearby เพื่อให้ข้อความอยู่ในเครื่องเสมอ
      final message = await dependencies.repositories.messages
          .createOutgoingText(
            conversationId: _activeChatId,
            senderId: dependencies.authService.identity?.userId ?? deviceId,
            senderDeviceId: deviceId,
            text: text,
          );
      _composer.clear();
      await dependencies.nearbyService.sendMessage(message);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกข้อความไม่สำเร็จ กรุณาลองอีกครั้ง'),
        ),
      );
    }
  }

  Future<void> _confirmDeleteDemoMessage(RelioMessage message) async {
    if (!message.outgoing ||
        message.type != MessageType.text ||
        (message.text != 'WEEK3 DELETE TEST' &&
            message.text != 'W3DELETETEST')) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบข้อความทดสอบ?'),
        content: const Text('ลบได้เฉพาะข้อความ Week 3 ที่ยังไม่ซิงก์'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบข้อความ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await _dependencies!.repositories.messages
        .deleteWeek3DemoMessage(message.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'ลบข้อความทดสอบออกจากเครื่องและคิวแล้ว'
              : 'ลบไม่ได้: ข้อความอาจเริ่มซิงก์หรือไม่ใช่รายการทดสอบที่ยังค้าง',
        ),
      ),
    );
  }

  Future<void> _pickMedia(MessageType type, {ImageSource? source}) {
    final dependencies = RelioDependencyScope.of(context);
    final pipelineClock = Stopwatch()..start();
    dependencies.diagnostics.record(
      'media',
      'MEDIA_SEND_TAP',
      fields: {'mediaType': type.name, 'source': source?.name},
    );
    return dependencies.repositories.ownerContext
        .run(
          () => _pickMediaOwned(
            type,
            source: source,
            pipelineClock: pipelineClock,
          ),
        )
        .catchError((Object _) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('เปิดกล้องหรือเลือกสื่อไม่สำเร็จ')),
            );
          }
        });
  }

  Future<void> _showCameraChoices() async {
    final choice = await showModalBottomSheet<MessageType>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ถ่ายรูป'),
              onTap: () => Navigator.pop(context, MessageType.image),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('ถ่ายวิดีโอ'),
              onTap: () => Navigator.pop(context, MessageType.video),
            ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) {
      await _pickMedia(choice, source: ImageSource.camera);
    }
  }

  Future<bool> _confirmCameraVideo({
    required String path,
    required String name,
    required int bytes,
  }) async {
    final size = bytes >= 1024 * 1024
        ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).ceil()} KB';
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('ตรวจสอบวิดีโอ'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name · $size'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await const MethodChannel(
                        'relio/media',
                      ).invokeMethod<void>('playLocalVideo', {'path': path});
                    } on PlatformException {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('เล่นตัวอย่างวิดีโอไม่ได้'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('เล่นตัวอย่าง'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('ส่งวิดีโอ'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // บีบอัดรูปภาพแชทล่วงหน้าในเครื่อง เพื่อความรวดเร็วในการส่งผ่าน Nearby/Bluetooth ขณะ Offline (1024px / 70%)
  static const double _chatImageMaxDimension = 1024;
  static const int _chatImageQuality = 70;

  Future<void> _pickMediaOwned(
    MessageType type, {
    ImageSource? source,
    required Stopwatch pipelineClock,
  }) async {
    if (!_routeResolved) return;
    final dependencies = RelioDependencyScope.of(context);
    final picker = ImagePicker();
    final picked = type == MessageType.image
        ? await picker.pickImage(
            source: source ?? ImageSource.gallery,
            maxWidth: _chatImageMaxDimension,
            maxHeight: _chatImageMaxDimension,
            imageQuality: _chatImageQuality,
            requestFullMetadata: false,
          )
        : await picker.pickVideo(source: source ?? ImageSource.gallery);
    if (picked == null) return;
    try {
      dependencies.diagnostics.record(
        'media',
        'MEDIA_PICKER_COMPLETED',
        fields: {
          'mediaType': type.name,
          'tapToPickMs': pipelineClock.elapsedMilliseconds,
        },
      );
      final deviceId = await dependencies.identity.getDeviceId();
      final traceId = const Uuid().v4();
      final messageId = const Uuid().v4();
      final attachmentId = const Uuid().v4();
      dependencies.diagnostics.record(
        'media',
        'MEDIA_SEND_REQUESTED',
        fields: {
          'traceId': traceId,
          'messageId': messageId,
          'attachmentId': attachmentId,
          'mediaType': type.name,
          'tapToPickMs': pipelineClock.elapsedMilliseconds,
        },
      );
      final validation = await dependencies.mediaStorageService.validateFile(
        picked.path,
      );
      dependencies.diagnostics.record(
        'media',
        'MEDIA_SOURCE_VALIDATED',
        fields: {
          'traceId': traceId,
          'mediaType': type.name,
          'sizeBytes': validation.byteSize,
          'validationMs': pipelineClock.elapsedMilliseconds,
        },
      );
      final localPath = await dependencies.mediaStorageService.copySelectedFile(
        picked.path,
      );
      if (type == MessageType.video && source == ImageSource.camera) {
        final confirmed = await _confirmCameraVideo(
          path: localPath,
          name: picked.name,
          bytes: validation.byteSize,
        );
        if (!confirmed) {
          await dependencies.mediaStorageService.deleteManagedFile(localPath);
          return;
        }
      }
      final transferId = traceId;
      await dependencies.repositories.attachments.createPending(
        id: attachmentId,
        conversationId: _activeChatId,
        messageId: messageId,
        transferId: transferId,
        mediaType: type == MessageType.video
            ? MediaType.video
            : MediaType.image,
        fileName: picked.name,
        mimeType: validation.mimeType,
        localPath: localPath,
        byteSize: validation.byteSize,
      );
      dependencies.diagnostics.record(
        'media',
        'ATTACHMENT_CREATED',
        fields: {
          'traceId': traceId,
          'messageId': messageId,
          'attachmentId': attachmentId,
          'queueInsertElapsedMs': pipelineClock.elapsedMilliseconds,
        },
      );
      final message = await dependencies.repositories.messages
          .createOutgoingMedia(
            conversationId: _activeChatId,
            senderId: dependencies.authService.identity?.userId ?? deviceId,
            senderDeviceId: deviceId,
            type: type,
            fileName: picked.name,
            localPath: localPath,
            attachmentId: attachmentId,
            messageId: messageId,
          );
      dependencies.diagnostics.record(
        'media',
        'LOCAL_MESSAGE_CREATED',
        fields: {
          'traceId': traceId,
          'messageId': messageId,
          'attachmentId': attachmentId,
          'localMessageElapsedMs': pipelineClock.elapsedMilliseconds,
        },
      );
      final attachment = await dependencies.repositories.attachments.getById(
        attachmentId,
      );
      if (attachment != null) {
        await dependencies.nearbyService.sendMediaMessage(
          message,
          attachment,
          pipelineClock: pipelineClock,
        );
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งสื่อไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
    }
  }

  Future<void> _sendLocation() => RelioDependencyScope.of(context)
      .repositories
      .ownerContext
      .run(() => _sendLocationOwned())
      .catchError((Object _) {});

  // ขอพิกัดจาก LocationService เฉพาะเมื่อผู้ใช้สั่งแชร์ และตรวจ owner ก่อนทำงานต่อ
  Future<void> _sendLocationOwned() async {
    if (!_routeResolved) return;
    final dependencies = RelioDependencyScope.of(context);
    final result = await dependencies.locationService.getCurrentOrLastKnown();
    if (!result.isSuccess) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_locationFailureText(result.failure))),
      );
      return;
    }
    try {
      final deviceId = await dependencies.identity.getDeviceId();
      final message = await dependencies.repositories.messages
          .createOutgoingLocation(
            conversationId: _activeChatId,
            senderId: dependencies.authService.identity?.userId ?? deviceId,
            senderDeviceId: deviceId,
            location: result.location!,
          );
      await dependencies.nearbyService.sendLocationMessage(message);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งตำแหน่งไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
    }
  }

  String _locationFailureText(LocationFailure? failure) => switch (failure) {
    LocationFailure.permissionDenied => 'ต้องอนุญาตตำแหน่งเพื่อส่งพิกัด',
    LocationFailure.permissionDeniedForever =>
      'ตำแหน่งถูกปฏิเสธถาวร กรุณาเปิดการตั้งค่า',
    LocationFailure.approximatePermission =>
      'ตำแหน่งเป็นแบบคร่าว ๆ กรุณาเลือก Precise Location ในการตั้งค่า',
    LocationFailure.serviceDisabled => 'บริการตำแหน่งยังไม่เปิดใช้งาน',
    LocationFailure.timeout => 'หาตำแหน่งไม่ทันเวลา ลองอีกครั้ง',
    LocationFailure.staleFix => 'ตำแหน่งเก่าเกินไป กรุณาลองอีกครั้ง',
    LocationFailure.invalidFix => 'ข้อมูลตำแหน่งไม่ถูกต้อง',
    LocationFailure.unavailable || null => 'ยังไม่พบตำแหน่งปัจจุบัน',
  };

  Future<void> _showAttachments() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('รูปภาพ'),
              onTap: () {
                Navigator.pop(context);
                _pickMedia(MessageType.image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('วิดีโอ'),
              onTap: () {
                Navigator.pop(context);
                _pickMedia(MessageType.video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('ส่งตำแหน่ง'),
              onTap: () {
                Navigator.pop(context);
                _sendLocation();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nearby = RelioDependencyScope.of(context).nearbyService;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(82),
        child: AnimatedBuilder(
          animation: nearby,
          builder: (context, _) {
            final connectionPresence = chatReachabilityFor(
              nearby,
              _persistedPeerDeviceId ?? widget.chatId,
              principal: _persistedRemotePrincipal,
            );
            final connected =
                connectionPresence == PeerConnectionPresence.online;
            final route = liveRoutePresentationFor(
              nearby,
              _persistedPeerDeviceId ?? widget.chatId,
              presence: connectionPresence,
            );
            final peerName =
                _persistedPeerName ?? _demoDevice?.name ?? 'อุปกรณ์ RELIO';
            return AppBar(
              leading: IconButton(
                onPressed: () => context.pop(),
                tooltip: 'ย้อนกลับ',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
              ),
              titleSpacing: 0,
              title: Row(
                children: [
                  RelioUserAvatar(
                    name: peerName,
                    identityKey: _persistedPeerDeviceId ?? widget.chatId,
                    presence: connectionPresence,
                    size: 52,
                    imagePath: nearby.avatarPathFor(
                      _persistedPeerDeviceId ?? widget.chatId,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          peerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: connected
                                    ? RelioColors.success
                                    : Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                route.chatSubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: route.kind == LiveRouteKind.relay
                                          ? RelioColors.success
                                          : null,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<RelioMessage>>(
              key: ValueKey(_routeGeneration),
              stream: _messagesStream,
              builder: (context, snapshot) {
                final messages = snapshot.data ?? const <RelioMessage>[];
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(
                    RelioSpacing.lg,
                    12,
                    RelioSpacing.lg,
                    8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (itemContext, index) {
                    final messageIndex = messages.length - 1 - index;
                    final message = messages[messageIndex];
                    final newerMessage = messageIndex + 1 < messages.length
                        ? messages[messageIndex + 1]
                        : null;
                    final showDate = shouldShowChatDateSeparator(
                      message.createdAt,
                      newerMessage?.createdAt,
                    );
                    return Column(
                      crossAxisAlignment: message.outgoing
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (showDate)
                          ChatDateSeparator(date: message.createdAt!),
                        GestureDetector(
                          onLongPress:
                              message.outgoing &&
                                  message.type == MessageType.text &&
                                  (message.text == 'WEEK3 DELETE TEST' ||
                                      message.text == 'W3DELETETEST')
                              ? () => _confirmDeleteDemoMessage(message)
                              : null,
                          child: RelioMessageBubble(
                            message: message,
                            onOpenLocation: message.type != MessageType.location
                                ? null
                                : () {
                                    final target = chatSharedLocationUri(
                                      message,
                                    );
                                    if (target == null) {
                                      ScaffoldMessenger.of(
                                        itemContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'ตำแหน่งนี้ไม่พร้อมเปิดดู',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    itemContext.push(target.toString());
                                  },
                          ),
                        ),
                        if (message.status == DeliveryStatus.failed)
                          TextButton.icon(
                            onPressed: () => RelioDependencyScope.of(
                              context,
                            ).nearbyService.retryMessage(message.id),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('ลองส่งอีกครั้ง'),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _showAttachments,
                    tooltip: 'แนบไฟล์',
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  IconButton(
                    onPressed: _showCameraChoices,
                    tooltip: 'กล้อง',
                    icon: const Icon(Icons.camera_alt_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'พิมพ์ข้อความ...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: RelioColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    tooltip: 'ส่ง',
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
