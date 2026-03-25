import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../core/constants.dart';
import '../core/local_storage.dart';
import '../core/notification_service.dart';
import '../core/socket_client.dart';
import '../models/chat_user.dart';
import '../models/group_data.dart';
import '../models/remote_message.dart';
import '../providers/messages_provider.dart';
import '../providers/users_provider.dart';
import '../providers/groups_provider.dart';
import 'call_screen.dart';
import 'conversation_screen.dart';
import 'group_conversation_screen.dart';
import 'create_group_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;
  bool _notificationsEnabled = true;
  // Dedup: prevent double-count when server sends via room + direct delivery
  final _seenMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    // Load groups from storage
    await ref.read(groupsProvider.notifier).loadFromStorage();

    // Load notification setting
    final notifEnabled = await LocalStorage.getNotificationsEnabled();
    if (mounted) setState(() => _notificationsEnabled = notifEnabled);

    // Set my identity
    final deviceId = await LocalStorage.getDeviceId() ?? '';
    final deviceName = await LocalStorage.getDeviceName() ?? 'Unknown';
    ref.read(usersProvider.notifier).setMyId(deviceId);
    ref.read(usersProvider.notifier).setMyName(deviceName);

    // Pre-populate list with previously seen users so offline users stay visible
    await ref.read(usersProvider.notifier).loadPersistedUsers();

    _connectAndListen();
  }

  void _connectAndListen() {
    final socket = SocketClient.instance;
    socket.connect();

    socket.on('connect', (_) {
      final myId = ref.read(usersProvider).myDeviceId;
      final myName = ref.read(usersProvider).myName;
      socket.emit(AppConstants.pvAccess, {
        'device_id': myId,
        'name': myName,
      });
    });

    socket.on(AppConstants.pvListUser, (data) {
      if (data == null) return;
      // Backend uses json.dumps — may arrive as JSON string
      dynamic parsed = data;
      if (data is String) {
        try { parsed = jsonDecode(data); } catch (_) { return; }
      }
      if (parsed is! List) return;
      final users = parsed
          .map((e) => ChatUser.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final myId = ref.read(usersProvider).myDeviceId;
      final filtered = users.where((u) => u.deviceId != myId).toList();
      ref.read(usersProvider.notifier).updateUsers(filtered);
      for (final u in filtered) {
        ref.read(usersProvider.notifier).loadUserPrefs(u.deviceId);
      }
    });

    // Update user name/icon when remote user renames themselves
    // Backend sends plain dict (no json.dumps) for this event
    socket.on(AppConstants.pvUpdateUserNameStatus, (data) {
      if (data == null) return;
      dynamic parsed = data;
      if (data is String) {
        try { parsed = jsonDecode(data); } catch (_) { return; }
      }
      if (parsed is! Map) return;
      final deviceId = parsed['device_id']?.toString();
      final newName = parsed['name']?.toString();
      final newIcon = parsed['icon']?.toString();
      if (deviceId != null) {
        ref.read(usersProvider.notifier).updateRemoteUser(
              deviceId,
              name: newName,
              icon: newIcon,
            );
      }
    });

    socket.on(AppConstants.pvMessageSended, (data) {
      if (data == null) return;
      dynamic parsed = data;
      if (data is String) {
        try { parsed = jsonDecode(data); } catch (_) { return; }
      }
      if (parsed is! Map) return;
      final msg = RemoteMessage.fromJson(Map<String, dynamic>.from(parsed));
      final myId = ref.read(usersProvider).myDeviceId;
      if (msg.senderDeviceId == null || msg.senderDeviceId == myId) return;

      // Deduplicate: prevent double-count from any duplicate events
      final msgId = msg.messageId?.toString();
      final rawContent = msg.messageContent ?? '';
      // Use content hash for group msgs (they have null message_id)
      final dedupeKey = msgId ?? '${msg.senderDeviceId}_$rawContent';
      if (_seenMessageIds.contains(dedupeKey)) return;
      _seenMessageIds.add(dedupeKey);

      // ── Group invite: add group to this user's groups list ────────────────
      if (rawContent.startsWith(AppConstants.grpInvPrefix)) {
        _handleGroupInvite(rawContent);
        return; // do NOT show in DMs
      }

      // ── Group message: update group preview, not DMs ──────────────────────
      if (rawContent.startsWith(AppConstants.grpPrefix)) {
        _handleGroupMessage(rawContent, msg);
        return; // do NOT show in DMs
      }

      // ── Other group system messages (leave/name/icon) ─────────────────────
      if (rawContent.startsWith(AppConstants.grpLeavePrefix) ||
          rawContent.startsWith(AppConstants.grpNamePrefix) ||
          rawContent.startsWith(AppConstants.grpIconPrefix)) {
        return; // handled by group_conversation_screen only
      }

      // ── DM message ────────────────────────────────────────────────────────
      final content = _previewContent(msg);
      ref.read(usersProvider.notifier).updateLastMessage(
            msg.senderDeviceId!,
            content,
            DateTime.now(),
          );

      // Don't increment unread if that conversation is already open
      final activeId = NotificationService.instance.activeConversationDeviceId;
      if (activeId == msg.senderDeviceId) return;

      if (_notificationsEnabled) {
        final sender = ref
            .read(usersProvider)
            .users
            .where((u) => u.deviceId == msg.senderDeviceId)
            .firstOrNull;
        if (sender == null || !sender.isMuted) {
          ref.read(usersProvider.notifier).incrementUnread(msg.senderDeviceId!);
        }
      }
    });

    // Incoming video/audio call
    socket.on(AppConstants.rtcMessage, (data) {
      if (data == null) return;
      dynamic parsed = data;
      if (data is String) {
        try { parsed = jsonDecode(data); } catch (_) { return; }
      }
      if (parsed is! Map) return;
      final map = Map<String, dynamic>.from(parsed);
      if (map['type'] != 'offer') return;
      final fromId = map['from']?.toString();
      if (fromId == null || !mounted) return;

      final users = ref.read(usersProvider).users;
      final caller = users.where((u) => u.deviceId == fromId).firstOrNull;
      final callerName = caller?.displayName ?? fromId;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Incoming call'),
          content: Text('$callerName is calling you'),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(context);
                // Send reject
                SocketClient.instance.emit(AppConstants.rtcMessage, {
                  'to': fromId,
                  'type': 'bye',
                });
              },
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                if (caller != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallScreen(
                        user: caller,
                        isCaller: false,
                      ),
                    ),
                  );
                }
              },
              child: const Text('Answer'),
            ),
          ],
        ),
      );
    });

    socket.on(AppConstants.pvMessagesDeleted, (data) {
      // handled per-room in conversation screens
    });

    socket.on(AppConstants.ping, (_) {
      socket.emit(AppConstants.pvPong, {});
    });
  }

  /// Received [GRP_INV:groupId:name:adminId:member1,member2,...] — add group.
  void _handleGroupInvite(String content) {
    // Format: [GRP_INV:groupId:name:adminId:member1,member2,...]
    try {
      final inner = content.substring(
          AppConstants.grpInvPrefix.length, content.length - 1);
      final parts = inner.split(':');
      if (parts.length < 2) return;
      final groupId = parts[0];
      final name = parts[1];
      final adminId = parts.length > 2 ? parts[2] : '';
      final memberIds = parts.length > 3
          ? parts[3].split(',').where((s) => s.isNotEmpty).toList()
          : <String>[ref.read(usersProvider).myDeviceId];
      if (groupId.isEmpty || name.isEmpty) return;
      final group = GroupData(
        groupId: groupId,
        groupName: name,
        adminId: adminId,
        memberIds: memberIds,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      ref.read(groupsProvider.notifier).addGroup(group);
      ref.read(groupsProvider.notifier).incrementUnread(groupId);

      // Notification: "GroupName" / "AdminName added you to this group"
      if (_notificationsEnabled) {
        final admin = ref.read(usersProvider).users
            .where((u) => u.deviceId == adminId)
            .firstOrNull;
        final adminName = admin?.displayName ?? adminId;
        NotificationService.instance.showMessage(
          senderName: name,
          body: '$adminName added you to this group',
          senderDeviceId: groupId,
        );
      }
    } catch (_) {}
  }

  /// Received [GRP:groupId]:text — store message, update preview, show notification.
  Future<void> _handleGroupMessage(String rawContent, RemoteMessage msg) async {
    // Format: [GRP:groupId]:actual text
    try {
      final prefixEnd = rawContent.indexOf(']');
      if (prefixEnd < 0) return;
      final groupId = rawContent.substring(
          AppConstants.grpPrefix.length, prefixEnd);
      final text = prefixEnd + 1 < rawContent.length
          ? rawContent.substring(prefixEnd + 2) // skip ']:' separator
          : '';
      final displayText = text.isNotEmpty ? text : '📎 Media';

      // Generate stable local ID (same formula as group_conversation_screen)
      final localId = msg.messageId ??
          '${msg.senderDeviceId}_${msg.createdAt ?? DateTime.now().millisecondsSinceEpoch}';

      final displayMsg = RemoteMessage(
        messageId: localId,
        roomId: groupId,
        messageContent: displayText,
        senderDeviceId: msg.senderDeviceId,
        typeMessage: msg.typeMessage,
        createdAt: msg.createdAt ?? DateTime.now().toIso8601String(),
        replyMessageId: msg.replyMessageId,
        replyMessage: msg.replyMessage,
        isPin: 0,
        status: AppConstants.statusSent,
      );

      // Await addMessage so message is durably cached before notification fires
      await ref.read(messagesProvider(groupId).notifier).addMessage(displayMsg);

      ref.read(groupsProvider.notifier).updateLastMessage(
            groupId, displayText, DateTime.now());

      // Don't increment unread if the group screen is currently open
      final activeId = NotificationService.instance.activeConversationDeviceId;
      if (activeId != groupId) {
        ref.read(groupsProvider.notifier).incrementUnread(groupId);
      }

      // Notification: "GroupName" / "SenderName: message"
      if (_notificationsEnabled) {
        // Try Riverpod state first; fall back to SharedPreferences so we always
        // have the real group name even if state hasn't loaded yet on startup
        final groups = ref.read(groupsProvider);
        GroupData? group = groups.where((g) => g.groupId == groupId).firstOrNull;
        String groupName = group?.groupName ?? '';
        if (groupName.isEmpty) {
          final rawGroups = await LocalStorage.getGroups();
          final stored = rawGroups
              .map((j) => GroupData.fromJson(j))
              .where((g) => g.groupId == groupId)
              .firstOrNull;
          groupName = stored?.groupName ?? 'Group';
          group ??= stored;
        }

        final sender = ref.read(usersProvider).users
            .where((u) => u.deviceId == msg.senderDeviceId)
            .firstOrNull;
        final senderName = sender?.displayName ?? msg.senderDeviceId ?? 'Someone';
        if (group == null || !group.isMuted) {
          NotificationService.instance.showMessage(
            senderName: groupName,
            body: '$senderName: $displayText',
            senderDeviceId: groupId,
          );
        }
      }
    } catch (_) {}
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
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(usersProvider);
    final groups = ref.watch(groupsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final allUsers = usersState.users
        .where((u) => !u.isHidden && !u.isBlocked)
        .toList();

    final filteredUsers = _searchQuery.isEmpty
        ? allUsers
        : allUsers
            .where((u) =>
                u.displayName
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ||
                (u.lastMessage ?? '')
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()))
            .toList();

    final filteredGroups = _searchQuery.isEmpty
        ? groups
        : groups
            .where((g) => g.groupName
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
            .toList();

    final pinnedUsers =
        filteredUsers.where((u) => u.isPinned).toList();
    final regularUsers =
        filteredUsers.where((u) => !u.isPinned).toList();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: _buildDrawer(context, usersState),
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Messages',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showMainMenu(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Chats'),
            Tab(text: 'Groups'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(colorScheme),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Chats tab
                _buildChatList(
                    pinnedUsers, regularUsers, context, colorScheme),
                // Groups tab
                _buildGroupList(filteredGroups, context, colorScheme),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
        ),
        tooltip: 'Create group',
        child: const Icon(Icons.group_add),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search chats…',
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
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildChatList(
    List<ChatUser> pinned,
    List<ChatUser> regular,
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    if (pinned.isEmpty && regular.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 64, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text('No users online',
                style: TextStyle(color: colorScheme.outline)),
          ],
        ),
      );
    }

    return ListView(
      children: [
        if (pinned.isNotEmpty) ...[
          _sectionHeader('Pinned', colorScheme),
          ...pinned.map((u) => _buildUserTile(u, context, colorScheme)),
        ],
        if (regular.isNotEmpty) ...[
          if (pinned.isNotEmpty) _sectionHeader('Recent', colorScheme),
          ...regular.map((u) => _buildUserTile(u, context, colorScheme)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildUserTile(
      ChatUser user, BuildContext context, ColorScheme colorScheme) {
    return InkWell(
      onTap: () {
        ref.read(usersProvider.notifier).clearUnread(user.deviceId);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ConversationScreen(user: user)),
        );
      },
      onLongPress: () => _showUserContextMenu(context, user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                _buildAvatar(user.displayName, user.displayIcon),
                if (user.connected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: colorScheme.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (user.isPinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin,
                              size: 12, color: colorScheme.primary),
                        ),
                      Expanded(
                        child: Text(
                          user.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.lastMessageTime != null)
                        Text(
                          timeago.format(user.lastMessageTime!,
                              locale: 'en_short'),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.lastMessage ?? '',
                          style: TextStyle(
                            color: colorScheme.outline,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            user.unreadCount > 99
                                ? '99+'
                                : '${user.unreadCount}',
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (user.isMuted)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.volume_off,
                              size: 14, color: colorScheme.outline),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupList(
      List<GroupData> groups, BuildContext context, ColorScheme colorScheme) {
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined,
                size: 64, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text('No groups yet', style: TextStyle(color: colorScheme.outline)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Create Group'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (_, i) => _buildGroupTile(groups[i], context, colorScheme),
    );
  }

  Widget _buildGroupTile(
      GroupData group, BuildContext context, ColorScheme colorScheme) {
    return InkWell(
      onTap: () {
        ref.read(groupsProvider.notifier).clearUnread(group.groupId);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => GroupConversationScreen(group: group)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _buildGroupAvatar(group),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.groupName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (group.lastMessageTime != null)
                        Text(
                          timeago.format(group.lastMessageTime!,
                              locale: 'en_short'),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.lastMessage ??
                              '${group.memberIds.length} members',
                          style: TextStyle(
                            color: colorScheme.outline,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (group.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${group.unreadCount}',
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
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
      ),
    );
  }

  Widget _buildAvatar(String name, String? iconUrl) {
    return CircleAvatar(
      radius: 26,
      backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
      child: iconUrl == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            )
          : null,
    );
  }

  Widget _buildGroupAvatar(GroupData group) {
    return CircleAvatar(
      radius: 26,
      backgroundImage:
          group.iconUrl != null ? NetworkImage(group.iconUrl!) : null,
      child: group.iconUrl == null
          ? Text(
              group.groupName.isNotEmpty
                  ? group.groupName[0].toUpperCase()
                  : 'G',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            )
          : null,
    );
  }

  // ── Context menus ─────────────────────────────────────────────────────────

  void _showUserContextMenu(BuildContext context, ChatUser user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(user.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Change name'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, user);
              },
            ),
            ListTile(
              title: Text(user.isPinned ? 'Unpin from top' : 'Pin to top'),
              onTap: () {
                Navigator.pop(context);
                ref
                    .read(usersProvider.notifier)
                    .pinUser(user.deviceId, pinned: !user.isPinned);
              },
            ),
            ListTile(
              title: Text(
                  user.isMuted ? 'Turn notifications on' : 'Turn notifications off'),
              onTap: () {
                Navigator.pop(context);
                ref
                    .read(usersProvider.notifier)
                    .muteUser(user.deviceId, muted: !user.isMuted);
              },
            ),
            ListTile(
              title: const Text('Hide this friend'),
              onTap: () {
                Navigator.pop(context);
                ref
                    .read(usersProvider.notifier)
                    .hideUser(user.deviceId, hidden: true);
              },
            ),
            ListTile(
              title: const Text('Block this friend',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmBlock(context, user);
              },
            ),
            ListTile(
              title: const Text('Delete messages',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteChat(context, user);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmBlock(BuildContext context, ChatUser user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        content:
            Text('Block ${user.displayName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(usersProvider.notifier)
                  .blockUser(user.deviceId, blocked: true);
            },
            child: const Text('Block',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteChat(BuildContext context, ChatUser user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(
            'Delete messages from ${user.displayName}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(usersProvider.notifier)
                  .updateLastMessage(user.deviceId, '', DateTime.now());
              ref.read(usersProvider.notifier).clearUnread(user.deviceId);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ChatUser user) {
    final controller =
        TextEditingController(text: user.customName ?? user.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename contact'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Custom name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref.read(usersProvider.notifier).setCustomName(
                    user.deviceId,
                    controller.text.trim().isEmpty
                        ? null
                        : controller.text.trim(),
                  );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showMainMenu(BuildContext context) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(100, 56, 0, 0),
      items: [
        const PopupMenuItem(
          value: 'icon',
          child: Row(children: [
            Icon(Icons.account_circle_outlined, size: 20),
            SizedBox(width: 12),
            Text('Change icon'),
          ]),
        ),
        const PopupMenuItem(
          value: 'rename',
          child: Row(children: [
            Icon(Icons.drive_file_rename_outline, size: 20),
            SizedBox(width: 12),
            Text('Change name'),
          ]),
        ),
        PopupMenuItem(
          value: 'notif',
          child: Row(children: [
            Icon(_notificationsEnabled
                ? Icons.notifications_off_outlined
                : Icons.notifications_outlined,
                size: 20),
            const SizedBox(width: 12),
            Text(_notificationsEnabled
                ? 'Turn notifications off'
                : 'Turn notifications on'),
          ]),
        ),
        const PopupMenuItem(
          value: 'qr_show',
          child: Row(children: [
            Icon(Icons.qr_code, size: 20),
            SizedBox(width: 12),
            Text('Show QR code'),
          ]),
        ),
        const PopupMenuItem(
          value: 'qr_scan',
          child: Row(children: [
            Icon(Icons.qr_code_scanner, size: 20),
            SizedBox(width: 12),
            Text('Scan QR code'),
          ]),
        ),
        const PopupMenuItem(
          value: 'create_group',
          child: Row(children: [
            Icon(Icons.group_add_outlined, size: 20),
            SizedBox(width: 12),
            Text('Create group'),
          ]),
        ),
        const PopupMenuItem(
          value: 'hidden',
          child: Row(children: [
            Icon(Icons.visibility_outlined, size: 20),
            SizedBox(width: 12),
            Text('Show hidden users'),
          ]),
        ),
        const PopupMenuItem(
          value: 'blocked',
          child: Row(children: [
            Icon(Icons.block_outlined, size: 20),
            SizedBox(width: 12),
            Text('Block list'),
          ]),
        ),
      ],
    ).then((val) {
      if (val == 'icon') _showChangeIconDialog(context);
      if (val == 'rename') _showProfileDialog(context);
      if (val == 'notif') _toggleNotifications();
      if (val == 'qr_show') _showQrCode(context);
      if (val == 'qr_scan') _scanQrCode(context);
      if (val == 'create_group') {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
      }
      if (val == 'hidden') _showHiddenUsers(context);
      if (val == 'blocked') _showBlockedUsers(context);
    });
  }

  void _toggleNotifications() async {
    final newVal = !_notificationsEnabled;
    await LocalStorage.setNotificationsEnabled(newVal);
    setState(() => _notificationsEnabled = newVal);
  }

  void _showChangeIconDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change icon'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter image URL',
            labelText: 'Icon URL',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await LocalStorage.setDeviceName(
                    ref.read(usersProvider).myName);
                // Broadcast icon change via socket
                SocketClient.instance.emit(
                  AppConstants.pvUpdateUserName,
                  {
                    'name': ref.read(usersProvider).myName,
                    'icon': url,
                  },
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showQrCode(BuildContext context) {
    final myId = ref.read(usersProvider).myDeviceId;
    final myName = ref.read(usersProvider).myName;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(myName),
        content: SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: QrImageView(
                  data: myId,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
              const SizedBox(height: 8),
              Text(myId,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _scanQrCode(BuildContext context) {
    Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    ).then((scannedId) {
      if (scannedId == null || scannedId.isEmpty || !mounted) return;
      // Find the user in the online list
      final users = ref.read(usersProvider).users;
      final found =
          users.where((u) => u.deviceId == scannedId).firstOrNull;
      if (found != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ConversationScreen(user: found)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'User "$scannedId" is not online right now.')),
        );
      }
    });
  }

  void _showHiddenUsers(BuildContext context) {
    final hidden = ref
        .read(usersProvider)
        .users
        .where((u) => u.isHidden)
        .toList();
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Hidden users',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (hidden.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hidden users'),
              )
            else
              ...hidden.map(
                (u) => ListTile(
                  leading: _buildAvatar(u.displayName, u.displayIcon),
                  title: Text(u.displayName),
                  trailing: TextButton(
                    child: const Text('Unhide'),
                    onPressed: () {
                      ref
                          .read(usersProvider.notifier)
                          .hideUser(u.deviceId, hidden: false);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBlockedUsers(BuildContext context) {
    final blocked = ref
        .read(usersProvider)
        .users
        .where((u) => u.isBlocked)
        .toList();
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Blocked users',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (blocked.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No blocked users'),
              )
            else
              ...blocked.map(
                (u) => ListTile(
                  leading: _buildAvatar(u.displayName, u.displayIcon),
                  title: Text(u.displayName),
                  trailing: TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.red),
                    child: const Text('Unblock'),
                    onPressed: () {
                      ref
                          .read(usersProvider.notifier)
                          .blockUser(u.deviceId, blocked: false);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showProfileDialog(BuildContext context) {
    final myName = ref.read(usersProvider).myName;
    final controller = TextEditingController(text: myName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('My Profile'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await LocalStorage.setDeviceName(newName);
                ref.read(usersProvider.notifier).setMyName(newName);
                SocketClient.instance.emit(
                  AppConstants.pvUpdateUserName,
                  {'name': newName},
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, UsersState state) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 32,
                    child: Text(
                      state.myName.isNotEmpty
                          ? state.myName[0].toUpperCase()
                          : 'M',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(state.myName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(state.myDeviceId,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Edit Profile'),
              onTap: () {
                Navigator.pop(context);
                _showProfileDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Create Group'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CreateGroupScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── QR Scanner Screen ─────────────────────────────────────────────────────────

class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_scanned) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                _scanned = true;
                Navigator.pop(context, barcode!.rawValue!);
              }
            },
          ),
          // Targeting overlay
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Point camera at QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
