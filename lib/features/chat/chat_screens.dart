import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
import '../../core/cloud/cloud_models.dart';
import '../../data/mock_data.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/location/location_service.dart';
import '../../data/models/prototype_models.dart';
import '../../shared/widgets/relio_widgets.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repositories = RelioDependencyScope.of(context).repositories;
    return Scaffold(
      appBar: const RelioAppBar(
        title: 'แชท',
        subtitle: 'ข้อความ Nearby และ SOS',
      ),
      body: StreamBuilder<List<RelioConversation>>(
        stream: repositories.conversations.watchConversations(),
        builder: (context, snapshot) {
          final allConversations = snapshot.data ?? const <RelioConversation>[];
          final nearby = RelioDependencyScope.of(context).nearbyService;
          final conversations = [
            ...allConversations.where(
              (conversation) =>
                  !RelioMockData.isDemoId(conversation.participantId) &&
                  nearby.isDeviceConnected(conversation.participantId),
            ),
            ...allConversations.where(
              (conversation) =>
                  !RelioMockData.isDemoId(conversation.participantId) &&
                  !nearby.isDeviceConnected(conversation.participantId),
            ),
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
                chat: _preview(conversation),
                onTap: () => context.push('/chat/${conversation.id}'),
              );
            },
          );
        },
      ),
    );
  }

  RelioChatPreview _preview(RelioConversation conversation) => RelioChatPreview(
    id: conversation.id,
    name: conversation.displayName,
    message: conversation.lastMessageText ?? 'เริ่มการสนทนา Nearby',
    time: conversation.lastMessageAt == null
        ? ''
        : '${conversation.lastMessageAt!.hour.toString().padLeft(2, '0')}:${conversation.lastMessageAt!.minute.toString().padLeft(2, '0')}',
    status: conversation.participantStatus,
    unread: conversation.unreadCount,
    isDemo: RelioMockData.isDemoId(conversation.participantId),
  );
}

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({required this.chatId, super.key});

  final String chatId;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  RelioDevice? _demoDevice;
  late Stream<List<RelioMessage>> _messagesStream;
  String? _persistedPeerName;
  String? _persistedPeerDeviceId;
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

  Future<void> _linkCloudConversation() => RelioDependencyScope.of(context)
      .repositories
      .ownerContext
      .run(() => _linkCloudConversationOwned())
      .catchError((Object _) {});

  Future<void> _linkCloudConversationOwned() async {
    final dependencies = _dependencies;
    if (!_routeResolved ||
        dependencies == null ||
        dependencies.authService.identity == null) {
      return;
    }
    final controller = TextEditingController();
    final peerUserId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('เชื่อมแชทผ่าน Cloud'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: const InputDecoration(
            labelText: 'Cloud Account ID ของคู่สนทนา',
            helperText: 'ให้คู่สนทนาแชร์ ID จากหน้าโปรไฟล์โดยตรง',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('เชื่อมต่อ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (peerUserId == null || peerUserId.isEmpty || !mounted) return;
    try {
      await dependencies.syncEngine.linkConversationToCloud(
        localConversationId: _activeChatId,
        peerUserId: peerUserId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เชื่อมบทสนทนา Cloud แล้ว')),
        );
      }
    } on CloudException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _pickMedia(MessageType type, {ImageSource? source}) =>
      RelioDependencyScope.of(context).repositories.ownerContext
          .run(() => _pickMediaOwned(type, source: source))
          .catchError((Object _) {});

  Future<void> _pickMediaOwned(MessageType type, {ImageSource? source}) async {
    if (!_routeResolved) return;
    final dependencies = RelioDependencyScope.of(context);
    final picker = ImagePicker();
    final picked = type == MessageType.image
        ? await picker.pickImage(source: source ?? ImageSource.gallery)
        : await picker.pickVideo(source: source ?? ImageSource.gallery);
    if (picked == null) return;
    try {
      final deviceId = await dependencies.identity.getDeviceId();
      final validation = await dependencies.mediaStorageService.validateFile(
        picked.path,
      );
      final localPath = await dependencies.mediaStorageService.copySelectedFile(
        picked.path,
      );
      final messageId = const Uuid().v4();
      final attachmentId = const Uuid().v4();
      final transferId = const Uuid().v4();
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
      final attachment = await dependencies.repositories.attachments.getById(
        attachmentId,
      );
      if (attachment != null) {
        await dependencies.nearbyService.sendMediaMessage(message, attachment);
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
    LocationFailure.serviceDisabled => 'บริการตำแหน่งยังไม่เปิดใช้งาน',
    LocationFailure.timeout => 'หาตำแหน่งไม่ทันเวลา ลองอีกครั้ง',
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
    final isDemo = RelioMockData.isDemoId(
      _persistedPeerDeviceId ?? widget.chatId,
    );
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AnimatedBuilder(
          animation: nearby,
          builder: (context, _) {
            final connected = nearby.isDeviceConnected(
              _persistedPeerDeviceId ?? widget.chatId,
            );
            return RelioAppBar(
              title: _persistedPeerName ?? _demoDevice?.name ?? 'อุปกรณ์ RELIO',
              subtitle: isDemo
                  ? 'ตัวอย่าง • ประวัติสนทนา DEMO'
                  : connected
                  ? 'Nearby • เชื่อมต่อโดยตรงแล้ว'
                  : 'Nearby • ยังไม่เชื่อมต่อ — ข้อความจะค้างในเครื่อง',
              onBack: () => context.pop(),
              actions: [
                if (!isDemo && _dependencies?.authService.identity != null)
                  IconButton(
                    onPressed: _linkCloudConversation,
                    tooltip: 'เชื่อมแชท Cloud',
                    icon: const Icon(Icons.cloud_sync_outlined),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Chip(label: Text(isDemo ? 'DEMO' : 'REAL')),
                ),
              ],
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
                  itemBuilder: (_, index) {
                    final message = messages[messages.length - 1 - index];
                    return Column(
                      crossAxisAlignment: message.outgoing
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onLongPress:
                              message.outgoing &&
                                  message.type == MessageType.text &&
                                  (message.text == 'WEEK3 DELETE TEST' ||
                                      message.text == 'W3DELETETEST')
                              ? () => _confirmDeleteDemoMessage(message)
                              : null,
                          child: RelioMessageBubble(message: message),
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
                    onPressed: () => _pickMedia(
                      MessageType.image,
                      source: ImageSource.camera,
                    ),
                    tooltip: 'กล้อง',
                    icon: const Icon(Icons.camera_alt_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'พิมพ์ข้อความ...',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
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
