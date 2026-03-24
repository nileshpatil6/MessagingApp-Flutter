import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../core/socket_client.dart';
import '../models/group_data.dart';
import '../models/remote_message.dart';
import '../providers/messages_provider.dart';
import '../providers/groups_provider.dart';
import '../providers/users_provider.dart';
import 'forward_screen.dart';
import 'photo_view_screen.dart';
import 'pin_messages_screen.dart';
import 'video_player_screen.dart';

class GroupConversationScreen extends ConsumerStatefulWidget {
  final GroupData group;
  const GroupConversationScreen({super.key, required this.group});

  @override
  ConsumerState<GroupConversationScreen> createState() =>
      _GroupConversationScreenState();
}

class _GroupConversationScreenState
    extends ConsumerState<GroupConversationScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();

  String _myDeviceId = '';
  bool _showEmoji = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  RemoteMessage? _replyTo;

  String get _roomId =>
      '${AppConstants.grpPrefix}${widget.group.groupId}]';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    _myDeviceId = ref.read(usersProvider).myDeviceId;
    _listenToSocket();
    ref.read(groupsProvider.notifier).clearUnread(widget.group.groupId);
  }

  static dynamic _d(dynamic raw) {
    if (raw is String) {
      try { return jsonDecode(raw); } catch (_) { return raw; }
    }
    return raw;
  }

  void _listenToSocket() {
    final socket = SocketClient.instance;

    socket.on(AppConstants.pvMessageSended, (data) {
      if (data == null) return;
      final parsed = _d(data);
      if (parsed is! Map) return;
      final msg = RemoteMessage.fromJson(Map<String, dynamic>.from(parsed));

      final content = msg.messageContent ?? '';
      // Only handle messages for this group room
      if (!content.startsWith(_roomId)) return;

      // Strip group prefix for display
      final displayMsg = RemoteMessage(
        messageId: msg.messageId,
        roomId: msg.roomId,
        messageContent:
            content.startsWith('$_roomId:')
                ? content.substring(_roomId.length + 1)
                : content,
        deadTime: msg.deadTime,
        senderDeviceId: msg.senderDeviceId,
        typeMessage: msg.typeMessage,
        createdAt: msg.createdAt,
        replyMessageId: msg.replyMessageId,
        replyMessage: msg.replyMessage,
        isPin: msg.isPin,
        pinTime: msg.pinTime,
      );

      ref
          .read(messagesProvider(widget.group.groupId).notifier)
          .addMessage(displayMsg);
      _scrollToBottom();

      // Check for system messages
      final rawContent = msg.messageContent ?? '';
      if (rawContent.contains(AppConstants.grpNamePrefix)) {
        _handleGroupNameChange(rawContent);
      } else if (rawContent.contains(AppConstants.grpLeavePrefix)) {
        _handleMemberLeave(rawContent, msg.senderDeviceId ?? '');
      }

      ref.read(groupsProvider.notifier).updateLastMessage(
            widget.group.groupId,
            displayMsg.messageContent ?? '',
            DateTime.now(),
          );
    });

    socket.on(AppConstants.pvMessageDeleted, (data) {
      if (data == null) return;
      final parsed = _d(data);
      if (parsed is! Map) return;
      final id = parsed['message_id']?.toString();
      if (id != null) {
        ref
            .read(messagesProvider(widget.group.groupId).notifier)
            .removeMessage(id);
      }
    });

    socket.on(AppConstants.pvMessagesDeleted, (data) {
      if (data == null) return;
      final parsed = _d(data);
      if (parsed is! Map) return;
      final ids = (parsed['message_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      if (ids.isNotEmpty) {
        ref
            .read(messagesProvider(widget.group.groupId).notifier)
            .removeMessages(ids);
      }
    });

    socket.on(AppConstants.pvMessagePinList, (data) {
      if (data == null) return;
      final p = _d(data);
      List<dynamic> rawList;
      if (p is Map) {
        rawList = (p['messages'] as List?) ?? [];
      } else if (p is List) {
        rawList = p;
      } else {
        return;
      }
      final pinned = rawList
          .map((e) => RemoteMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      ref
          .read(messagesProvider(widget.group.groupId).notifier)
          .applyPinList(pinned);
    });
  }

  void _handleGroupNameChange(String content) {
    // [GRP_NAME:{groupId}:{newName}]
    try {
      final inner = content.substring(
          AppConstants.grpNamePrefix.length, content.length - 1);
      final parts = inner.split(':');
      if (parts.length >= 2) {
        final gid = parts[0];
        final newName = parts.sublist(1).join(':');
        if (gid == widget.group.groupId) {
          ref
              .read(groupsProvider.notifier)
              .updateGroupName(gid, newName);
        }
      }
    } catch (_) {}
  }

  void _handleMemberLeave(String content, String senderId) {
    // [GRP_LEAVE:{groupId}]
    try {
      final gid = content
          .substring(AppConstants.grpLeavePrefix.length, content.length - 1);
      if (gid == widget.group.groupId) {
        ref.read(groupsProvider.notifier).removeMember(gid, senderId);
      }
    } catch (_) {}
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  void _sendMessage(String content, int type) {
    if (content.isEmpty) return;
    final myId = _myDeviceId;
    final fullContent = '$_roomId:$content';

    // Send to each member individually
    for (final memberId in widget.group.memberIds) {
      if (memberId == myId) continue;
      final payload = {
        'room_id': widget.group.groupId,
        'message_content': fullContent,
        'type_message': type,
        'sender_device_id': myId,
        'receiver_device_id': memberId,
        if (_replyTo?.messageId != null)
          'reply_message_id': _replyTo!.messageId,
      };
      SocketClient.instance.emit(AppConstants.pvSendMessage, payload);
    }

    // Add locally immediately
    final localMsg = RemoteMessage(
      messageId:
          DateTime.now().millisecondsSinceEpoch.toString(),
      roomId: widget.group.groupId,
      messageContent: content,
      senderDeviceId: myId,
      typeMessage: type,
      createdAt: DateTime.now().toIso8601String(),
      replyMessage: _replyTo,
      isPin: 0,
    );
    ref
        .read(messagesProvider(widget.group.groupId).notifier)
        .addMessage(localMsg);
    ref.read(groupsProvider.notifier).updateLastMessage(
          widget.group.groupId,
          content,
          DateTime.now(),
        );
    _scrollToBottom();
    setState(() => _replyTo = null);
  }

  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _sendMessage(text, AppConstants.typeText);
  }

  Future<String?> _uploadFile(String filePath) async {
    try {
      final dio = Dio();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath,
            filename: filePath.split(Platform.pathSeparator).last),
      });
      final response = await dio.post(
        AppConstants.uploadFileChatUrl,
        data: formData,
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map) {
          return data['url'] ?? data['filename']?.toString();
        }
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    }
    return null;
  }

  Future<void> _pickImage() async {
    final xFile =
        await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Uploading image…')));
    }
    final url = await _uploadFile(xFile.path);
    if (url != null) {
      _sendMessage(
          '${AppConstants.serverUrl}/public/$url', AppConstants.typeImage);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Upload failed')));
    }
  }

  Future<void> _pickVideo() async {
    final xFile =
        await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (xFile == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Uploading video…')));
    }
    final url = await _uploadFile(xFile.path);
    if (url != null) {
      _sendMessage(
          '${AppConstants.serverUrl}/public/$url', AppConstants.typeVideo);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Upload failed')));
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Uploading file…')));
    }
    final url = await _uploadFile(result.files.single.path!);
    if (url != null) {
      _sendMessage(
          '${AppConstants.serverUrl}/public/$url', AppConstants.typeFile);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Upload failed')));
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  void _deleteMessage(RemoteMessage msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('Delete for everyone?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              SocketClient.instance.emit(AppConstants.pvDeleteMessage, {
                'message_id': msg.messageId,
                'room_id': widget.group.groupId,
              });
              ref
                  .read(messagesProvider(widget.group.groupId).notifier)
                  .removeMessage(msg.messageId!);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteSelected() {
    if (_selectedIds.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${_selectedIds.length} message(s)'),
        content:
            const Text('Delete for everyone? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final ids = _selectedIds.toList();
              SocketClient.instance.emit(AppConstants.pvDeleteMessages, {
                'message_ids': ids,
                'room_id': widget.group.groupId,
              });
              ref
                  .read(messagesProvider(widget.group.groupId).notifier)
                  .removeMessages(ids);
              setState(() {
                _selectedIds.clear();
                _isSelectionMode = false;
              });
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _togglePin(RemoteMessage msg) {
    if (msg.messageId == null) return;
    final newPin = msg.isPin == 0;
    SocketClient.instance.emit(AppConstants.pvPinMessage, {
      'message_id': msg.messageId,
      'room_id': widget.group.groupId,
      'is_pin': newPin ? 1 : 0,
    });
    ref
        .read(messagesProvider(widget.group.groupId).notifier)
        .pinMessage(msg.messageId!, newPin);
  }

  void _renameGroup(BuildContext context, GroupData group) {
    final controller =
        TextEditingController(text: group.groupName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(hintText: 'New group name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(context);
              // Broadcast name change to all members
              final changeMsg =
                  '${AppConstants.grpNamePrefix}${widget.group.groupId}:$newName]';
              _sendMessage(changeMsg, AppConstants.typeText);
              ref
                  .read(groupsProvider.notifier)
                  .updateGroupName(widget.group.groupId, newName);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete group'),
        content: const Text(
            'Delete this group for everyone? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Broadcast leave to all members then remove locally
              final leaveMsg =
                  '${AppConstants.grpLeavePrefix}${widget.group.groupId}]';
              _sendMessage(leaveMsg, AppConstants.typeText);
              ref
                  .read(groupsProvider.notifier)
                  .removeGroup(widget.group.groupId);
              Navigator.pop(context);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _leaveGroup() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final leaveMsg =
                  '${AppConstants.grpLeavePrefix}${widget.group.groupId}]';
              _sendMessage(leaveMsg, AppConstants.typeText);
              ref
                  .read(groupsProvider.notifier)
                  .removeGroup(widget.group.groupId);
              Navigator.pop(context);
            },
            child: const Text('Leave',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    SocketClient.instance.off(AppConstants.pvMessageSended);
    SocketClient.instance.off(AppConstants.pvMessageDeleted);
    SocketClient.instance.off(AppConstants.pvMessagesDeleted);
    SocketClient.instance.off(AppConstants.pvMessagePinList);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final messages =
        ref.watch(messagesProvider(widget.group.groupId));
    final colorScheme = Theme.of(context).colorScheme;
    // Watch group state for name updates
    final groups = ref.watch(groupsProvider);
    final currentGroup = groups.firstWhere(
      (g) => g.groupId == widget.group.groupId,
      orElse: () => widget.group,
    );

    return Scaffold(
      appBar: _isSelectionMode
          ? _buildSelectionAppBar(colorScheme, messages)
          : _buildNormalAppBar(currentGroup, colorScheme),
      body: GestureDetector(
        onTap: () {
          if (_showEmoji) setState(() => _showEmoji = false);
        },
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 8),
                itemCount: messages.length,
                itemBuilder: (_, i) =>
                    _buildMessageBubble(messages[i], colorScheme),
              ),
            ),
            if (_replyTo != null) _buildReplyPreview(colorScheme),
            _buildInputBar(colorScheme),
            if (_showEmoji)
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  textEditingController: _textController,
                  config: const Config(height: 250),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(
      GroupData group, ColorScheme colorScheme) {
    return AppBar(
      backgroundColor: colorScheme.surface,
      title: GestureDetector(
        onTap: () => _showMemberList(context, group),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: group.iconUrl != null
                  ? NetworkImage(group.iconUrl!)
                  : null,
              child: group.iconUrl == null
                  ? Text(group.groupName.isNotEmpty
                      ? group.groupName[0].toUpperCase()
                      : 'G')
                  : null,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.groupName,
                    style: const TextStyle(fontSize: 16)),
                Text(
                  '${group.memberIds.length} members',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.outline),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.push_pin_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PinMessagesScreen(roomId: widget.group.groupId),
            ),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (val) {
            if (val == 'leave') _leaveGroup();
            if (val == 'members') _showMemberList(context, group);
            if (val == 'rename') _renameGroup(context, group);
            if (val == 'delete') _deleteGroup(context);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'members', child: Text('View members')),
            const PopupMenuItem(
                value: 'rename', child: Text('Rename group')),
            const PopupMenuItem(
                value: 'leave',
                child: Text('Leave group',
                    style: TextStyle(color: Colors.orange))),
            if (group.adminId == _myDeviceId)
              const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete group',
                      style: TextStyle(color: Colors.red))),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(
      ColorScheme colorScheme, List<RemoteMessage> allMessages) {
    return AppBar(
      backgroundColor: colorScheme.secondaryContainer,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () {
          setState(() {
            _isSelectionMode = false;
            _selectedIds.clear();
          });
        },
      ),
      title: Text('${_selectedIds.length} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Select all',
          onPressed: () {
            setState(() {
              _selectedIds.clear();
              for (final m in allMessages) {
                if (m.messageId != null) _selectedIds.add(m.messageId!);
              }
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: _deleteSelected,
        ),
        IconButton(
          icon: const Icon(Icons.forward),
          onPressed: () {
            final messages =
                ref.read(messagesProvider(widget.group.groupId));
            final selected = messages
                .where((m) => _selectedIds.contains(m.messageId));
            if (selected.isEmpty) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ForwardScreen(messages: selected.toList()),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMessageBubble(RemoteMessage msg, ColorScheme colorScheme) {
    final isMe = msg.senderDeviceId == _myDeviceId;
    final isSelected = _selectedIds.contains(msg.messageId);

    // System messages
    final content = msg.messageContent ?? '';
    if (content.startsWith(AppConstants.grpInvPrefix) ||
        content.startsWith(AppConstants.grpLeavePrefix) ||
        content.startsWith(AppConstants.grpNamePrefix) ||
        content.startsWith(AppConstants.grpIconPrefix)) {
      return _buildSystemBubble(content, colorScheme);
    }

    return GestureDetector(
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            if (msg.messageId != null) _selectedIds.add(msg.messageId!);
          });
        }
        _showMessageContextMenu(context, msg);
      },
      onTap: () {
        if (_isSelectionMode && msg.messageId != null) {
          setState(() {
            if (_selectedIds.contains(msg.messageId)) {
              _selectedIds.remove(msg.messageId);
              if (_selectedIds.isEmpty) _isSelectionMode = false;
            } else {
              _selectedIds.add(msg.messageId!);
            }
          });
        }
      },
      child: Dismissible(
        key: ValueKey(msg.messageId ?? ''),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (_) async {
          setState(() => _replyTo = msg);
          return false;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 16),
          child: const Icon(Icons.reply),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: isSelected
              ? colorScheme.primaryContainer.withOpacity(0.4)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Sender name for group messages
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        child: Text(
                          _getSenderName(msg.senderDeviceId),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _colorForSender(
                                msg.senderDeviceId ?? '', colorScheme),
                          ),
                        ),
                      ),
                    if (msg.replyMessage != null)
                      _buildReplyInsideBubble(
                          msg.replyMessage!, isMe, colorScheme),
                    Container(
                      decoration: BoxDecoration(
                        color: isMe
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: isMe
                              ? const Radius.circular(16)
                              : const Radius.circular(4),
                          bottomRight: isMe
                              ? const Radius.circular(4)
                              : const Radius.circular(16),
                        ),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          _buildMessageContent(msg, colorScheme),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (msg.isPin == 1)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.push_pin,
                                      size: 12, color: Colors.orange),
                                ),
                              Text(
                                msg.createdAt != null
                                    ? _formatTime(msg.createdAt!)
                                    : '',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isMe) const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemBubble(String content, ColorScheme colorScheme) {
    String display = content;
    if (content.startsWith(AppConstants.grpInvPrefix)) {
      display = 'You were invited to the group';
    } else if (content.startsWith(AppConstants.grpLeavePrefix)) {
      display = 'A member left the group';
    } else if (content.startsWith(AppConstants.grpNamePrefix)) {
      display = 'Group name was changed';
    } else if (content.startsWith(AppConstants.grpIconPrefix)) {
      display = 'Group icon was updated';
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          display,
          style: TextStyle(
              fontSize: 12, color: colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }

  Widget _buildReplyInsideBubble(
      RemoteMessage reply, bool isMe, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? colorScheme.primary.withOpacity(0.2)
            : colorScheme.outline.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: colorScheme.primary, width: 3),
        ),
      ),
      child: Text(
        reply.messageContent ?? '',
        style: const TextStyle(fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildMessageContent(RemoteMessage msg, ColorScheme colorScheme) {
    switch (msg.typeMessage) {
      case AppConstants.typeImage:
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PhotoViewScreen(imageUrl: msg.messageContent ?? ''),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              msg.messageContent ?? '',
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
            ),
          ),
        );

      case AppConstants.typeVideo:
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  VideoPlayerScreen(videoUrl: msg.messageContent ?? ''),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 200,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const Icon(Icons.play_circle_filled,
                  size: 48, color: Colors.white),
            ],
          ),
        );

      case AppConstants.typeFile:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, size: 36),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                msg.messageContent?.split('/').last ?? 'File',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );

      default:
        return Text(msg.messageContent ?? '',
            style: const TextStyle(fontSize: 15));
    }
  }

  Widget _buildReplyPreview(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
              width: 3, height: 40, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reply',
                    style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600)),
                Text(
                  _replyTo?.messageContent ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _showEmoji
                    ? Icons.keyboard
                    : Icons.emoji_emotions_outlined,
                color: colorScheme.primary,
              ),
              onPressed: () => setState(() => _showEmoji = !_showEmoji),
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: 5,
                minLines: 1,
                onTap: () {
                  if (_showEmoji) setState(() => _showEmoji = false);
                },
                decoration: InputDecoration(
                  hintText: 'Message…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.attach_file, color: colorScheme.primary),
              onPressed: () => _showAttachMenu(context),
            ),
            const SizedBox(width: 4),
            FloatingActionButton.small(
              onPressed: _sendTextMessage,
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () async {
                Navigator.pop(context);
                final xFile = await _imagePicker.pickImage(
                    source: ImageSource.camera);
                if (xFile == null) return;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Uploading…')));
                }
                final url = await _uploadFile(xFile.path);
                if (url != null) {
                  _sendMessage('${AppConstants.serverUrl}/public/$url',
                      AppConstants.typeImage);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Image from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageContextMenu(BuildContext context, RemoteMessage msg) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyTo = msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ForwardScreen(messages: [msg]),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(msg.isPin == 1
                  ? Icons.push_pin
                  : Icons.push_pin_outlined),
              title: Text(msg.isPin == 1 ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(context);
                _togglePin(msg);
              },
            ),
            if (msg.messageContent != null && msg.typeMessage == 0)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(
                      ClipboardData(text: msg.messageContent!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(msg);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMemberList(BuildContext context, GroupData group) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Members (${group.memberIds.length})',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: group.memberIds.length,
              itemBuilder: (_, i) {
                final id = group.memberIds[i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(id.isNotEmpty
                        ? id[0].toUpperCase()
                        : '?'),
                  ),
                  title: Text(id),
                  trailing: id == group.adminId
                      ? const Chip(label: Text('Admin'))
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getSenderName(String? deviceId) {
    if (deviceId == null) return 'Unknown';
    final users = ref.read(usersProvider).users;
    final user = users.where((u) => u.deviceId == deviceId).firstOrNull;
    return user?.displayName ?? deviceId;
  }

  Color _colorForSender(String deviceId, ColorScheme colorScheme) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
    ];
    final index = deviceId.hashCode.abs() % colors.length;
    return colors[index];
  }

  String _formatTime(String createdAt) {
    try {
      final dt = DateTime.parse(createdAt);
      return DateFormat('HH:mm').format(dt.toLocal());
    } catch (_) {
      return createdAt;
    }
  }
}
