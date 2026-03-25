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
import '../core/local_storage.dart';
import '../core/notification_service.dart';
import '../core/socket_client.dart';
import '../models/chat_user.dart';
import '../models/remote_message.dart';
import '../providers/messages_provider.dart';
import '../providers/users_provider.dart';
import 'forward_screen.dart';
import 'photo_view_screen.dart';
import 'pin_messages_screen.dart';
import 'self_destruct_screen.dart';
import 'video_player_screen.dart';
import '../l10n/app_strings.dart';
import '../providers/locale_provider.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final ChatUser user;
  const ConversationScreen({super.key, required this.user});

  @override
  ConsumerState<ConversationScreen> createState() =>
      _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();

  String _roomId = '';
  String _myDeviceId = '';
  bool _showEmoji = false;
  bool _isSelectionMode = false;
  bool _isSearching = false;
  bool _showScrollFab = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  RemoteMessage? _replyTo;
  String? _deadTime;

  AppStrings get _s => AppStrings(ref.read(localeProvider));

  // Keep handler references so dispose() removes only this screen's listeners
  late final void Function(dynamic) _onListMessage;
  late final void Function(dynamic) _onMessageSended;
  late final void Function(dynamic) _onMessageDeleted;
  late final void Function(dynamic) _onMessagesDeleted;
  late final void Function(dynamic) _onMessagePinList;
  late final void Function(dynamic) _onRoomId;
  late final void Function(dynamic) _onAutoJoinRoom;
  late final void Function(dynamic) _onMessageRead;
  late final void Function(dynamic) _onMessageDelivered;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    _myDeviceId = ref.read(usersProvider).myDeviceId;
    // Suppress notifications while this conversation is open
    NotificationService.instance.activeConversationDeviceId =
        widget.user.deviceId;
    // Load self destruct settings
    final sdPrefs = await LocalStorage.getSelfDestruct();
    if (sdPrefs != null && mounted) {
      setState(() => _deadTime = sdPrefs['dead_time']);
    }

    _scrollController.addListener(() {
      final atBottom = _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 100;
      if (!atBottom && !_showScrollFab) {
        setState(() => _showScrollFab = true);
      } else if (atBottom && _showScrollFab) {
        setState(() => _showScrollFab = false);
      }
    });

    // Load cached room ID + messages instantly so UI is not blank while waiting
    // for the socket to respond (also works fully offline)
    final cachedRoomId =
        await LocalStorage.loadRoomId(widget.user.deviceId);
    if (cachedRoomId != null && cachedRoomId.isNotEmpty && mounted) {
      setState(() => _roomId = cachedRoomId);
      await ref
          .read(messagesProvider(cachedRoomId).notifier)
          .loadCached();
      _scrollToBottom();
    }

    _joinRoom();
    _listenToSocket();
  }

  void _joinRoom() {
    // Server expects {current_user: {device_id}, partner: {device_id}}
    SocketClient.instance.emit(AppConstants.pvJoinRoom, {
      'current_user': {'device_id': _myDeviceId},
      'partner': {'device_id': widget.user.deviceId},
    });
  }

  /// All backend socket events use json.dumps — parse string→Map/List if needed
  static dynamic _d(dynamic raw) {
    if (raw is String) {
      try { return jsonDecode(raw); } catch (_) { return raw; }
    }
    return raw;
  }

  void _listenToSocket() {
    final socket = SocketClient.instance;

    _onRoomId = (data) {
      if (data == null) return;
      final roomId = data.toString();
      if (roomId.isNotEmpty) {
        LocalStorage.saveRoomId(widget.user.deviceId, roomId);
        if (mounted) setState(() => _roomId = roomId);
        // Retry any messages that were stuck in "sending" state (e.g. sent offline)
        _retryPendingMessages(roomId);
      }
    };
    socket.on(AppConstants.pvRoomId, _onRoomId);

    _onAutoJoinRoom = (data) {
      if (data == null) return;
      // Server sends str(room_id) — raw string
      final roomId = data.toString();
      if (roomId.isNotEmpty) {
        // Emit ack so server enters this socket into the socket.io room
        SocketClient.instance.emit(AppConstants.pvAutoJoinRoomClient, roomId);
        if (mounted && _roomId.isEmpty) {
          setState(() => _roomId = roomId);
        }
      }
    };
    socket.on(AppConstants.pvAutoJoinRoom, _onAutoJoinRoom);

    _onListMessage = (data) {
      if (data == null) return;
      final parsed = _d(data);
      List<dynamic> rawList;
      if (parsed is Map) {
        rawList = (parsed['messages'] as List?) ?? [];
      } else if (parsed is List) {
        rawList = parsed;
      } else {
        return;
      }
      if (_roomId.isEmpty) return;
      final messages = rawList
          .map((e) => RemoteMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      ref.read(messagesProvider(_roomId).notifier)
          .loadMessages(messages, myDeviceId: _myDeviceId);
      _scrollToBottom();
      // Emit delivered+read for any peer messages in history we haven't acked yet
      for (final msg in messages) {
        if (msg.senderDeviceId != _myDeviceId && msg.messageId != null) {
          _emitDelivered(msg.messageId!);
          _emitRead(msg.messageId!);
        }
      }
    };
    socket.on(AppConstants.pvListMessage, _onListMessage);

    _onMessageSended = (data) {
      if (data == null || _roomId.isEmpty) return;
      final parsed = _d(data);
      if (parsed is! Map) return;
      final raw = Map<String, dynamic>.from(parsed);
      final tempId = raw['_tempId']?.toString();
      // Status 1 = sent (server confirmed); history will promote to delivered
      final msg = RemoteMessage.fromJson(raw).copyWith(status: AppConstants.statusSent);

      // Only process messages for this room
      final msgRoomId = msg.roomId?.toString() ?? '';
      if (msgRoomId != _roomId) return;

      if (msg.senderDeviceId == _myDeviceId) {
        // Replace the local sending bubble (by tempId or content fallback)
        ref.read(messagesProvider(_roomId).notifier)
            .replaceTemp(tempId ?? '', msg);
      } else {
        ref.read(messagesProvider(_roomId).notifier).addMessage(msg);
      }
      _scrollToBottom();

      // Deliver and read if from peer
      if (msg.senderDeviceId != _myDeviceId && msg.messageId != null) {
        _emitDelivered(msg.messageId!);
        _emitRead(msg.messageId!);
      }

      // Update last message in users list
      if (msg.senderDeviceId != null) {
        final content = _previewContent(msg);
        ref.read(usersProvider.notifier).updateLastMessage(
              msg.senderDeviceId!,
              content,
              DateTime.now(),
            );
      }
    };
    socket.on(AppConstants.pvMessageSended, _onMessageSended);

    _onMessageDeleted = (data) {
      if (data == null || _roomId.isEmpty) return;
      final parsed = _d(data);
      if (parsed is! Map) return;
      final id = parsed['message_id']?.toString();
      if (id != null) {
        ref.read(messagesProvider(_roomId).notifier).removeMessage(id);
      }
    };
    socket.on(AppConstants.pvMessageDeleted, _onMessageDeleted);

    _onMessagesDeleted = (data) {
      if (data == null || _roomId.isEmpty) return;
      final parsed = _d(data);
      if (parsed is! Map) return;
      final ids = (parsed['message_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      if (ids.isNotEmpty) {
        ref.read(messagesProvider(_roomId).notifier).removeMessages(ids);
      }
    };
    socket.on(AppConstants.pvMessagesDeleted, _onMessagesDeleted);

    _onMessagePinList = (data) {
      if (data == null) return;
      final parsed = _d(data);
      List<dynamic> rawList;
      if (parsed is Map) {
        rawList = (parsed['messages'] as List?) ?? [];
      } else if (parsed is List) {
        rawList = parsed;
      } else {
        return;
      }
      if (_roomId.isEmpty) return;
      final pinned = rawList
          .map((e) => RemoteMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      ref.read(messagesProvider(_roomId).notifier).applyPinList(pinned);
    };
    socket.on(AppConstants.pvMessagePinList, _onMessagePinList);

    _onMessageRead = (data) {
      if (data == null) return;
      final parsed = _d(data);
      if (parsed is! Map) return;
      final id = parsed['message_id']?.toString();
      final roomId = parsed['room_id']?.toString() ?? _roomId;
      if (id != null && roomId.isNotEmpty) {
        ref
            .read(messagesProvider(roomId).notifier)
            .updateMessageStatus(id, AppConstants.statusRead);
      }
    };
    socket.on(AppConstants.pvMessageRead, _onMessageRead);

    _onMessageDelivered = (data) {
      if (data == null) return;
      final parsed = _d(data);
      if (parsed is! Map) return;
      final id = parsed['message_id']?.toString();
      final roomId = parsed['room_id']?.toString() ?? _roomId;
      if (id != null && roomId.isNotEmpty) {
        ref
            .read(messagesProvider(roomId).notifier)
            .updateMessageStatus(id, AppConstants.statusDelivered);
      }
    };
    socket.on(AppConstants.pvMessageDelivered, _onMessageDelivered);
  }

  /// Re-emit any messages still stuck in "sending_" state (sent while offline).
  void _retryPendingMessages(String roomId) {
    final messages = ref.read(messagesProvider(roomId));
    for (final msg in messages) {
      if (msg.messageId?.startsWith('sending_') == true) {
        SocketClient.instance.emit(AppConstants.pvSendMessage, {
          'room_id': roomId,
          'message_content': msg.messageContent,
          'type_message': msg.typeMessage,
          'sender_device_id': _myDeviceId,
          'receiver_device_id': widget.user.deviceId,
          '_tempId': msg.messageId,
          if (msg.replyMessageId != null) 'reply_message_id': msg.replyMessageId,
          if (msg.deadTime != null) 'dead_time': _mapDeadTime(msg.deadTime),
        });
      }
    }
  }

  void _emitDelivered(String messageId) async {
    final delivered = await LocalStorage.getDeliveredIds();
    if (!delivered.contains(messageId)) {
      await LocalStorage.addDeliveredId(messageId);
      // sender_device_id needed so server can relay the ack back to original sender
      SocketClient.instance.emit(AppConstants.pvMessageDelivered, {
        'message_id': messageId,
        'room_id': _roomId,
        'sender_device_id': widget.user.deviceId,
      });
    }
  }

  void _emitRead(String messageId) async {
    final seen = await LocalStorage.getSeenIds();
    if (!seen.contains(messageId)) {
      await LocalStorage.addSeenId(messageId);
      // sender_device_id needed so server can relay the ack back to original sender
      SocketClient.instance.emit(AppConstants.pvMessageRead, {
        'message_id': messageId,
        'room_id': _roomId,
        'sender_device_id': widget.user.deviceId,
      });
    }
  }

  /// Maps Flutter shorthand dead_time values to backend constants
  String? _mapDeadTime(String? dt) {
    if (dt == null || dt == 'off') return null;
    const map = {
      '5s': 'FIVE_SECONDS',
      '30s': 'THIRTY_SECONDS',
      '1m': 'ONE_MINUTE',
      '5m': 'FIVE_MINUTES',
      '30m': 'THIRTY_MINUTES',
      '1h': 'ONE_HOUR',
      '1d': 'ONE_DAY_LATER',
      '7d': 'ONE_WEEK_LATER',
      '30d': 'ONE_MONTH_LATER',
    };
    if (map.containsKey(dt)) return map[dt];
    // Custom hours: e.g. '48h'
    if (dt.endsWith('h')) {
      final hours = int.tryParse(dt.substring(0, dt.length - 1));
      if (hours != null) return 'CUSTOM:${hours * 3600}';
    }
    // ISO date string — compute seconds from now
    final date = DateTime.tryParse(dt);
    if (date != null) {
      final secs = date.difference(DateTime.now()).inSeconds;
      if (secs > 0) return 'CUSTOM:$secs';
    }
    return null;
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty || _roomId.isEmpty) return;

    final mappedDeadTime = _mapDeadTime(_deadTime);
    final tempId = 'sending_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = RemoteMessage(
      messageId: tempId,
      roomId: _roomId,
      messageContent: text,
      typeMessage: AppConstants.typeText,
      senderDeviceId: _myDeviceId,
      receiverDeviceId: widget.user.deviceId,
      createdAt: DateTime.now().toIso8601String(),
      status: AppConstants.statusSending,
    );
    ref.read(messagesProvider(_roomId).notifier).addMessage(tempMsg);

    final payload = {
      'room_id': _roomId,
      'message_content': text,
      'type_message': AppConstants.typeText,
      'sender_device_id': _myDeviceId,
      'receiver_device_id': widget.user.deviceId,
      '_tempId': tempId,
      if (_replyTo?.messageId != null)
        'reply_message_id': _replyTo!.messageId,
      if (mappedDeadTime != null) 'dead_time': mappedDeadTime,
    };

    SocketClient.instance.emit(AppConstants.pvSendMessage, payload);
    _textController.clear();
    setState(() => _replyTo = null);
    _scrollToBottom();
  }

  void _sendMediaMessage(String url, int type) {
    if (_roomId.isEmpty) return;
    final mappedDeadTime = _mapDeadTime(_deadTime);
    final tempId = 'sending_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = RemoteMessage(
      messageId: tempId,
      roomId: _roomId,
      messageContent: url,
      typeMessage: type,
      senderDeviceId: _myDeviceId,
      receiverDeviceId: widget.user.deviceId,
      createdAt: DateTime.now().toIso8601String(),
      status: AppConstants.statusSending,
    );
    ref.read(messagesProvider(_roomId).notifier).addMessage(tempMsg);

    final payload = {
      'room_id': _roomId,
      'message_content': url,
      'type_message': type,
      'sender_device_id': _myDeviceId,
      'receiver_device_id': widget.user.deviceId,
      '_tempId': tempId,
      if (_replyTo?.messageId != null)
        'reply_message_id': _replyTo!.messageId,
      if (mappedDeadTime != null) 'dead_time': mappedDeadTime,
    };
    SocketClient.instance.emit(AppConstants.pvSendMessage, payload);
    setState(() => _replyTo = null);
    _scrollToBottom();
  }

  Future<String?> _uploadFile(String filePath) async {
    try {
      final dio = Dio();
      final formData = FormData.fromMap({
        'files': await MultipartFile.fromFile(filePath,
            filename: filePath.split(Platform.pathSeparator).last),
      });
      final response = await dio.post(
        AppConstants.uploadFileChatUrl,
        data: formData,
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map) {
          final files = data['files'];
          if (files is List && files.isNotEmpty) {
            // Return just the filename; callers build the full URL themselves
            return files[0]['filename']?.toString();
          }
        }
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    }
    return null;
  }

  Future<void> _pickImage() async {
    final xFile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_s.uploadingImage)));
    }
    final url = await _uploadFile(xFile.path);
    if (url != null) {
      _sendMediaMessage('${AppConstants.serverUrl}/public/$url',
          AppConstants.typeImage);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_s.uploadFailed)));
      }
    }
  }

  Future<void> _pickVideo() async {
    final xFile = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (xFile == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_s.uploadingVideo)));
    }
    final url = await _uploadFile(xFile.path);
    if (url != null) {
      _sendMediaMessage('${AppConstants.serverUrl}/public/$url',
          AppConstants.typeVideo);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_s.uploadFailed)));
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_s.uploadingFile)));
    }
    final url = await _uploadFile(result.files.single.path!);
    if (url != null) {
      _sendMediaMessage('${AppConstants.serverUrl}/public/$url',
          AppConstants.typeFile);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_s.uploadFailed)));
      }
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  void _deleteMessage(RemoteMessage msg) {
    if (_roomId.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_s.deleteMessage),
        content: Text(_s.deleteForEveryone),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_s.cancel)),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              SocketClient.instance.emit(AppConstants.pvDeleteMessage, {
                'message_id': msg.messageId,
                'room_id': _roomId,
              });
              ref
                  .read(messagesProvider(_roomId).notifier)
                  .removeMessage(msg.messageId!);
            },
            child: Text(_s.delete,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteSelected() {
    if (_selectedIds.isEmpty || _roomId.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_s.deleteNMessages(_selectedIds.length)),
        content: Text(_s.deleteForEveryone),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_s.cancel)),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final ids = _selectedIds.toList();
              SocketClient.instance.emit(AppConstants.pvDeleteMessages, {
                'message_ids': ids,
                'room_id': _roomId,
              });
              ref
                  .read(messagesProvider(_roomId).notifier)
                  .removeMessages(ids);
              setState(() {
                _selectedIds.clear();
                _isSelectionMode = false;
              });
            },
            child: Text(_s.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Pin ───────────────────────────────────────────────────────────────────

  void _togglePin(RemoteMessage msg) {
    if (_roomId.isEmpty || msg.messageId == null) return;
    final newPin = msg.isPin == 0;
    SocketClient.instance.emit(AppConstants.pvPinMessage, {
      'message_id': msg.messageId,
      'room_id': _roomId,
      'is_pin': newPin ? 1 : 0,
    });
    ref
        .read(messagesProvider(_roomId).notifier)
        .pinMessage(msg.messageId!, newPin);
  }

  // ── Scroll ────────────────────────────────────────────────────────────────

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

  String _previewContent(RemoteMessage msg) {
    switch (msg.typeMessage) {
      case AppConstants.typeImage:
        return '📷 Image';
      case AppConstants.typeVideo:
        return '🎥 Video';
      case AppConstants.typeFile:
        return '📄 File';
      default:
        return msg.messageContent ?? '';
    }
  }

  @override
  void dispose() {
    // Re-enable notifications when leaving this conversation
    NotificationService.instance.activeConversationDeviceId = null;
    // Remove only this screen's handlers — global listeners (main.dart) are preserved
    SocketClient.instance.off(AppConstants.pvListMessage, _onListMessage);
    SocketClient.instance.off(AppConstants.pvMessageSended, _onMessageSended);
    SocketClient.instance.off(AppConstants.pvMessageDeleted, _onMessageDeleted);
    SocketClient.instance.off(AppConstants.pvMessagesDeleted, _onMessagesDeleted);
    SocketClient.instance.off(AppConstants.pvMessagePinList, _onMessagePinList);
    SocketClient.instance.off(AppConstants.pvRoomId, _onRoomId);
    SocketClient.instance.off(AppConstants.pvAutoJoinRoom, _onAutoJoinRoom);
    SocketClient.instance.off(AppConstants.pvMessageRead, _onMessageRead);
    SocketClient.instance.off(AppConstants.pvMessageDelivered, _onMessageDelivered);
    _textController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    // ignore: unused_local_variable
    final s = _s;
    final allMessages = _roomId.isNotEmpty
        ? ref.watch(messagesProvider(_roomId))
        : <RemoteMessage>[];

    final messages = _searchQuery.isEmpty
        ? allMessages
        : allMessages
            .where((m) =>
                m.messageContent
                    ?.toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ??
                false)
            .toList();

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _isSelectionMode
          ? _buildSelectionAppBar(colorScheme, allMessages)
          : _buildNormalAppBar(colorScheme),
      body: GestureDetector(
        onTap: () {
          if (_showEmoji) setState(() => _showEmoji = false);
        },
        child: Column(
          children: [
            // Search bar
            if (_isSearching) _buildSearchBar(colorScheme),
            // Self-destruct badge
            if (_deadTime != null && _deadTime != 'off')
              _buildDestructBadge(colorScheme),
            // Messages
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (_, i) =>
                        _buildMessageBubble(messages[i], colorScheme),
                  ),
                  // Scroll to bottom FAB
                  if (_showScrollFab)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: FloatingActionButton.small(
                        heroTag: 'scroll_bottom',
                        onPressed: _scrollToBottom,
                        child: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                ],
              ),
            ),
            // Reply preview
            if (_replyTo != null) _buildReplyPreview(colorScheme),
            // Input
            _buildInputBar(colorScheme),
            // Emoji picker
            if (_showEmoji)
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  textEditingController: _textController,
                  config: const Config(
                    height: 250,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: _s.searchMessagesHint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(ColorScheme colorScheme) {
    return AppBar(
      backgroundColor: colorScheme.surface,
      leadingWidth: 40,
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: widget.user.displayIcon != null
                ? NetworkImage(widget.user.displayIcon!)
                : null,
            child: widget.user.displayIcon == null
                ? Text(
                    widget.user.displayName.isNotEmpty
                        ? widget.user.displayName[0].toUpperCase()
                        : '?',
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.user.displayName,
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis),
                Text(
                  widget.user.connected ? _s.online : _s.offline,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.user.connected
                        ? Colors.green
                        : colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(_isSearching ? Icons.search_off : Icons.search),
          tooltip: _s.searchMessages,
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                _searchQuery = '';
              }
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.push_pin_outlined),
          tooltip: _s.pinnedMessages,
          onPressed: () {
            if (_roomId.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PinMessagesScreen(roomId: _roomId),
                ),
              );
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.timer_outlined),
          tooltip: _s.selfDestruct,
          onPressed: () async {
            final result = await Navigator.push<String?>(
              context,
              MaterialPageRoute(
                  builder: (_) => const SelfDestructScreen()),
            );
            if (result != null && mounted) {
              setState(() => _deadTime = result == 'off' ? null : result);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showConversationMenu(context),
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
      title: Text(_s.nSelected(_selectedIds.length)),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: _s.selectAll,
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
            final messages = ref.read(messagesProvider(_roomId));
            final selected =
                messages.where((m) => _selectedIds.contains(m.messageId));
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
        IconButton(
          icon: const Icon(Icons.push_pin_outlined),
          onPressed: () {
            final messages = ref.read(messagesProvider(_roomId));
            for (final m in messages) {
              if (_selectedIds.contains(m.messageId)) {
                _togglePin(m);
              }
            }
            setState(() {
              _isSelectionMode = false;
              _selectedIds.clear();
            });
          },
        ),
      ],
    );
  }

  Widget _buildDestructBadge(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.timer, size: 16),
          const SizedBox(width: 4),
          Text(_s.selfDestructBadge(_deadTime!),
              style: const TextStyle(fontSize: 13)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _deadTime = null),
            child: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(RemoteMessage msg, ColorScheme colorScheme) {
    final isMe = msg.senderDeviceId == _myDeviceId;
    final isSelected = _selectedIds.contains(msg.messageId);

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
                    // Reply preview inside bubble
                    if (msg.replyMessage != null)
                      _buildReplyInsideBubble(
                          msg.replyMessage!, isMe, colorScheme),
                    // Main bubble
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
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                _buildStatusTick(msg, colorScheme),
                              ],
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
              Positioned(
                bottom: 8,
                left: 8,
                child: Text(
                  _s.video,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.messageContent?.split('/').last ?? 'File',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(_s.tapToDownload,
                      style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        );

      default:
        return Text(
          msg.messageContent ?? '',
          style: const TextStyle(fontSize: 15),
        );
    }
  }

  Widget _buildStatusTick(RemoteMessage msg, ColorScheme colorScheme) {
    switch (msg.status) {
      case AppConstants.statusSending:
        return Icon(Icons.access_time, size: 13, color: colorScheme.outline);
      case AppConstants.statusSent:
        return Icon(Icons.done, size: 14, color: colorScheme.outline);
      case AppConstants.statusDelivered:
        return Icon(Icons.done_all, size: 14, color: colorScheme.outline);
      case AppConstants.statusRead:
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
      default:
        return Icon(Icons.done, size: 14, color: colorScheme.outline);
    }
  }

  Widget _buildReplyPreview(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_s.reply,
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
                _showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
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
                  hintText: _s.messageHint,
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
              title: Text(_s.camera),
              onTap: () async {
                Navigator.pop(context);
                final xFile = await _imagePicker.pickImage(
                    source: ImageSource.camera);
                if (xFile == null) return;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_s.uploading)));
                }
                final url = await _uploadFile(xFile.path);
                if (url != null) {
                  _sendMediaMessage(
                      '${AppConstants.serverUrl}/public/$url',
                      AppConstants.typeImage);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: Text(_s.imageFromGallery),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: Text(_s.video),
              onTap: () {
                Navigator.pop(context);
                _pickVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(_s.file),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(_s.setSelfDestructTimer),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push<String?>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SelfDestructScreen()),
                );
                if (result != null && mounted) {
                  setState(
                      () => _deadTime = result == 'off' ? null : result);
                }
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(_s.reply),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyTo = msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: Text(_s.forward),
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
              leading: Icon(
                  msg.isPin == 1 ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(msg.isPin == 1 ? _s.unpin : _s.pin),
              onTap: () {
                Navigator.pop(context);
                _togglePin(msg);
              },
            ),
            if (msg.messageContent != null && msg.typeMessage == 0)
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(_s.copy),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(
                      ClipboardData(text: msg.messageContent!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_s.copied)),
                  );
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(_s.delete,
                  style: const TextStyle(color: Colors.red)),
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

  void _showConversationMenu(BuildContext context) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(100, 80, 0, 0),
      items: [
        PopupMenuItem(value: 'pin', child: Text(_s.pinnedMessages)),
        PopupMenuItem(value: 'destruct', child: Text(_s.selfDestructTimer)),
      ],
    ).then((val) {
      if (val == 'pin' && _roomId.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PinMessagesScreen(roomId: _roomId)),
        );
      } else if (val == 'destruct') {
        Navigator.push<String?>(
          context,
          MaterialPageRoute(builder: (_) => const SelfDestructScreen()),
        ).then((result) {
          if (result != null && mounted) {
            setState(() => _deadTime = result == 'off' ? null : result);
          }
        });
      }
    });
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
