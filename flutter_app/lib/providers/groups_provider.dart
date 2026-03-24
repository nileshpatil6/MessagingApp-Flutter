import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group_data.dart';
import '../core/local_storage.dart';

class GroupsNotifier extends StateNotifier<List<GroupData>> {
  GroupsNotifier() : super([]);

  // ── Add ───────────────────────────────────────────────────────────────────

  Future<void> addGroup(GroupData group) async {
    final exists = state.any((g) => g.groupId == group.groupId);
    if (!exists) {
      state = [...state, group];
      await saveToStorage();
    }
  }

  // ── Remove ────────────────────────────────────────────────────────────────

  Future<void> removeGroup(String groupId) async {
    state = state.where((g) => g.groupId != groupId).toList();
    await saveToStorage();
  }

  // ── Update ────────────────────────────────────────────────────────────────

  Future<void> updateGroup(GroupData updated) async {
    state = state.map((g) {
      if (g.groupId == updated.groupId) return updated;
      return g;
    }).toList();
    await saveToStorage();
  }

  void updateGroupName(String groupId, String newName) {
    state = state.map((g) {
      if (g.groupId == groupId) {
        g.groupName = newName;
      }
      return g;
    }).toList();
    saveToStorage();
  }

  void updateGroupIcon(String groupId, String? iconUrl) {
    state = state.map((g) {
      if (g.groupId == groupId) {
        g.iconUrl = iconUrl;
      }
      return g;
    }).toList();
    saveToStorage();
  }

  void addMember(String groupId, String memberId) {
    state = state.map((g) {
      if (g.groupId == groupId && !g.memberIds.contains(memberId)) {
        g.memberIds = [...g.memberIds, memberId];
      }
      return g;
    }).toList();
    saveToStorage();
  }

  void removeMember(String groupId, String memberId) {
    state = state.map((g) {
      if (g.groupId == groupId) {
        g.memberIds = g.memberIds.where((id) => id != memberId).toList();
      }
      return g;
    }).toList();
    saveToStorage();
  }

  void incrementUnread(String groupId) {
    state = state.map((g) {
      if (g.groupId == groupId) {
        g.unreadCount = g.unreadCount + 1;
      }
      return g;
    }).toList();
  }

  void clearUnread(String groupId) {
    state = state.map((g) {
      if (g.groupId == groupId) {
        g.unreadCount = 0;
      }
      return g;
    }).toList();
  }

  void updateLastMessage(String groupId, String message, DateTime time) {
    state = state.map((g) {
      if (g.groupId == groupId) {
        g.lastMessage = message;
        g.lastMessageTime = time;
      }
      return g;
    }).toList();
  }

  void muteGroup(String groupId, {required bool muted}) {
    state = state.map((g) {
      if (g.groupId == groupId) {
        g.isMuted = muted;
      }
      return g;
    }).toList();
    saveToStorage();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> saveToStorage() async {
    final raw = state.map((g) => g.toJson()).toList();
    await LocalStorage.saveGroups(raw);
  }

  Future<void> loadFromStorage() async {
    final raw = await LocalStorage.getGroups();
    state = raw.map((json) => GroupData.fromJson(json)).toList();
  }
}

final groupsProvider =
    StateNotifierProvider<GroupsNotifier, List<GroupData>>(
  (ref) => GroupsNotifier(),
);
