import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
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
                  !RelioMockData.isDemoId(conversation.id) &&
                  nearby.isDeviceConnected(conversation.participantId),
            ),
            ...allConversations.where(
              (conversation) =>
                  !RelioMockData.isDemoId(conversation.id) &&
                  !nearby.isDeviceConnected(conversation.participantId),
            ),
            ...allConversations.where(
              (conversation) => RelioMockData.isDemoId(conversation.id),
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
    unread: 0,
    isDemo: RelioMockData.isDemoId(conversation.id),
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
    _messagesStream = RelioDependencyScope.of(
      context,
    ).repositories.messages.watchMessages(widget.chatId);
    RelioDependencyScope.of(context).repositories.conversations
        .getConversation(widget.chatId)
        .then((conversation) {
          if (mounted && conversation != null) {
            setState(() => _persistedPeerName = conversation.displayName);
          }
        });
  }

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final dependencies = RelioDependencyScope.of(context);
    try {
      final deviceId = await dependencies.identity.getDeviceId();
      final message = await dependencies.repositories.messages
          .createOutgoingText(
            conversationId: widget.chatId,
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

  Future<void> _pickMedia(MessageType type, {ImageSource? source}) async {
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
            conversationId: widget.chatId,
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

  Future<void> _sendLocation() async {
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
            conversationId: widget.chatId,
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
    final isDemo = RelioMockData.isDemoId(widget.chatId);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AnimatedBuilder(
          animation: nearby,
          builder: (context, _) {
            final connected = nearby.isDeviceConnected(widget.chatId);
            return RelioAppBar(
              title: _persistedPeerName ?? _demoDevice?.name ?? 'อุปกรณ์ RELIO',
              subtitle: isDemo
                  ? 'ตัวอย่าง • ประวัติสนทนา DEMO'
                  : connected
                  ? 'Nearby • เชื่อมต่อโดยตรงแล้ว'
                  : 'Nearby • ยังไม่เชื่อมต่อ — ข้อความจะค้างในเครื่อง',
              onBack: () => context.pop(),
              actions: [
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
                        RelioMessageBubble(message: message),
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
