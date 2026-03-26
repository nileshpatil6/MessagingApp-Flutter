import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_user.dart';
import '../core/local_storage.dart';

class UsersState {
  final List<ChatUser> users;
  final String myDeviceId;
  final String myName;
  final String? myIcon;

  const UsersState({
    this.users = const [],
    this.myDeviceId = '',
    this.myName = '',
    this.myIcon,
  });

  UsersState copyWith({
    List<ChatUser>? users,
    String? myDeviceId,
    String? myName,
    String? myIcon,
  }) {
    return UsersState(
      users: users ?? this.users,
      myDeviceId: myDeviceId ?? this.myDeviceId,
      myName: myName ?? this.myName,
      myIcon: myIcon ?? this.myIcon,
    );
  }
}

class UsersNotifier extends StateNotifier<UsersState> {
  UsersNotifier() : super(const UsersState());

  // ── Core list management ──────────────────────────────────────────────────

  void updateUsers(List<ChatUser> incoming) {
    final currentMap = {for (final u in state.users) u.deviceId: u};
    final merged = incoming.map((fresh) {
      final existing = currentMap[fresh.deviceId];
      if (existing == null) return fresh;
      // Preserve local UI state
      fresh.isPinned = existing.isPinned;
      fresh.isHidden = existing.isHidden;
      fresh.isBlocked = existing.isBlocked;
      fresh.isMuted = existing.isMuted;
      fresh.unreadCount = existing.unreadCount;
      fresh.lastMessage = existing.lastMessage;
      fresh.lastMessageTime = existing.lastMessageTime;
      fresh.customName = existing.customName;
      fresh.customIcon = existing.customIcon;
      return fresh;
    }).toList();

    // Preserve users that were online before but not in fresh list (mark offline)
    final freshIds = {for (final u in incoming) u.deviceId};
    for (final old in state.users) {
      if (!freshIds.contains(old.deviceId)) {
        old.connected = false;
        merged.add(old);
      }
    }

    state = state.copyWith(users: merged);
    _persistUserPrefs(merged);
  }

  void setMyId(String id) {
    state = state.copyWith(myDeviceId: id);
  }

  void setMyName(String name) {
    state = state.copyWith(myName: name);
  }

  Future<void> setMyIcon(String url) async {
    state = state.copyWith(myIcon: url);
    await LocalStorage.setMyIcon(url);
  }

  Future<void> loadMyIcon() async {
    final url = await LocalStorage.getMyIcon();
    if (url != null && url.isNotEmpty) {
      state = state.copyWith(myIcon: url);
    }
  }

  // ── Per-user mutations ────────────────────────────────────────────────────

  void _mutateUser(String deviceId, ChatUser Function(ChatUser) mutator) {
    final updated = state.users.map((u) {
      if (u.deviceId == deviceId) return mutator(u);
      return u;
    }).toList();
    state = state.copyWith(users: updated);
    _persistUserPrefs(updated);
  }

  void pinUser(String deviceId, {required bool pinned}) {
    _mutateUser(deviceId, (u) {
      u.isPinned = pinned;
      return u;
    });
  }

  void hideUser(String deviceId, {required bool hidden}) {
    _mutateUser(deviceId, (u) {
      u.isHidden = hidden;
      return u;
    });
  }

  void blockUser(String deviceId, {required bool blocked}) {
    _mutateUser(deviceId, (u) {
      u.isBlocked = blocked;
      return u;
    });
  }

  void muteUser(String deviceId, {required bool muted}) {
    _mutateUser(deviceId, (u) {
      u.isMuted = muted;
      return u;
    });
  }

  void setCustomName(String deviceId, String? customName) {
    _mutateUser(deviceId, (u) {
      u.customName = customName;
      return u;
    });
  }

  void setCustomIcon(String deviceId, String? customIcon) {
    _mutateUser(deviceId, (u) {
      u.customIcon = customIcon;
      return u;
    });
  }

  /// Called when a remote user broadcasts a name/icon change
  void updateRemoteUser(String deviceId, {String? name, String? icon}) {
    _mutateUser(deviceId, (u) {
      if (name != null && name.isNotEmpty) u.name = name;
      if (icon != null && icon.isNotEmpty) u.icon = icon;
      return u;
    });
  }

  void incrementUnread(String deviceId) {
    _mutateUser(deviceId, (u) {
      u.unreadCount = u.unreadCount + 1;
      return u;
    });
  }

  void clearUnread(String deviceId) {
    _mutateUser(deviceId, (u) {
      u.unreadCount = 0;
      return u;
    });
  }

  void updateLastMessage(String deviceId, String message, DateTime time) {
    _mutateUser(deviceId, (u) {
      u.lastMessage = message;
      u.lastMessageTime = time;
      return u;
    });
    // Persist so time and preview survive app restart
    LocalStorage.updateUserLastMessage(deviceId, message, time);
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _persistUserPrefs(List<ChatUser> users) async {
    for (final user in users) {
      await LocalStorage.addKnownUserId(user.deviceId);
      await LocalStorage.saveUserPrefs(user.deviceId, {
        'display_name': user.name,
        'icon': user.icon,
        'is_pinned': user.isPinned,
        'is_hidden': user.isHidden,
        'is_blocked': user.isBlocked,
        'is_muted': user.isMuted,
        'custom_name': user.customName,
        'custom_icon': user.customIcon,
        'last_message': user.lastMessage,
        'last_message_time': user.lastMessageTime?.toIso8601String(),
        'unread_count': user.unreadCount,
      });
    }
  }

  Future<void> loadUserPrefs(String deviceId) async {
    final prefs = await LocalStorage.getUserPrefs(deviceId);
    if (prefs == null) return;
    _mutateUser(deviceId, (u) {
      u.isPinned = prefs['is_pinned'] ?? false;
      u.isHidden = prefs['is_hidden'] ?? false;
      u.isBlocked = prefs['is_blocked'] ?? false;
      u.isMuted = prefs['is_muted'] ?? false;
      u.customName = prefs['custom_name'];
      u.customIcon = prefs['custom_icon'];
      if (prefs['icon'] != null) u.icon = prefs['icon'];
      u.lastMessage = prefs['last_message'];
      final timeStr = prefs['last_message_time']?.toString();
      if (timeStr != null) u.lastMessageTime = DateTime.tryParse(timeStr);
      u.unreadCount = prefs['unread_count'] ?? 0;
      return u;
    });
  }

  /// Load all previously seen users from local storage so offline users
  /// remain visible in the list even before the socket connects.
  Future<void> loadPersistedUsers() async {
    final ids = await LocalStorage.getKnownUserIds();
    if (ids.isEmpty) return;
    final myId = state.myDeviceId;
    final persisted = <ChatUser>[];
    for (final id in ids) {
      if (id == myId) continue;
      final prefs = await LocalStorage.getUserPrefs(id);
      if (prefs == null) continue;
      final name = prefs['display_name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final user = ChatUser(
        deviceId: id,
        name: name,
        socketId: '',
        connected: false,
      );
      user.isPinned = prefs['is_pinned'] ?? false;
      user.isHidden = prefs['is_hidden'] ?? false;
      user.isBlocked = prefs['is_blocked'] ?? false;
      user.isMuted = prefs['is_muted'] ?? false;
      user.customName = prefs['custom_name'];
      user.customIcon = prefs['custom_icon'];
      user.icon = prefs['icon'];
      user.lastMessage = prefs['last_message'];
      final timeStr = prefs['last_message_time']?.toString();
      if (timeStr != null) user.lastMessageTime = DateTime.tryParse(timeStr);
      user.unreadCount = prefs['unread_count'] ?? 0;
      persisted.add(user);
    }
    if (persisted.isNotEmpty) {
      // Merge with any users already in state
      final existing = {for (final u in state.users) u.deviceId: u};
      final merged = [
        ...persisted.map((p) => existing[p.deviceId] ?? p),
        ...state.users.where((u) => !persisted.any((p) => p.deviceId == u.deviceId)),
      ];
      state = state.copyWith(users: merged);
    }
  }
}

final usersProvider =
    StateNotifierProvider<UsersNotifier, UsersState>((ref) => UsersNotifier());
