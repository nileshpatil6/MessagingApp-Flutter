import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/remote_message.dart';
import '../core/local_storage.dart';

class MessagesNotifier extends StateNotifier<List<RemoteMessage>> {
  final String roomId;

  MessagesNotifier(this.roomId) : super([]);

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Load messages from server response, overlay saved statuses, then cache.
  Future<void> loadMessages(List<RemoteMessage> messages,
      {String myDeviceId = ''}) async {
    final deleted = await LocalStorage.getDeletedIds(roomId);
    final savedStatuses = await LocalStorage.getMessageStatuses(roomId);
    final filtered = messages
        .where((m) => !deleted.contains(m.messageId))
        .map((m) {
          int status = m.status;
          if (myDeviceId.isNotEmpty &&
              m.senderDeviceId == myDeviceId &&
              status == 1) {
            status = 2;
          }
          final saved = savedStatuses[m.messageId ?? ''];
          if (saved != null && saved > status) status = saved;
          return status != m.status ? m.copyWith(status: status) : m;
        })
        .toList();
    state = filtered;
    // Persist for offline use — also ensure any extra sent messages in state
    // (temp ids not yet confirmed) are not lost
    LocalStorage.saveCachedMessages(
        roomId, filtered.map((m) => m.toJson()).toList());
  }

  /// Show cached messages instantly before the server responds.
  Future<void> loadCached() async {
    if (state.isNotEmpty) return; // already have data, don't overwrite
    final raw = await LocalStorage.loadCachedMessages(roomId);
    if (raw.isEmpty) return;
    final savedStatuses = await LocalStorage.getMessageStatuses(roomId);
    final messages = raw.map((e) {
      final m = RemoteMessage.fromJson(e);
      final saved = savedStatuses[m.messageId ?? ''];
      if (saved != null && saved > m.status) return m.copyWith(status: saved);
      return m;
    }).toList();
    state = messages;
  }

  // ── Add ───────────────────────────────────────────────────────────────────

  Future<void> addMessage(RemoteMessage message) async {
    if (message.messageId == null) return;
    final deleted = await LocalStorage.getDeletedIds(roomId);
    if (deleted.contains(message.messageId)) return;
    // avoid duplicates
    final exists = state.any((m) => m.messageId == message.messageId);
    if (!exists) {
      state = [...state, message];
    }
  }

  // ── Remove single ─────────────────────────────────────────────────────────

  Future<void> removeMessage(String id) async {
    await LocalStorage.addDeletedId(id, roomKey: roomId);
    state = state.where((m) => m.messageId != id).toList();
  }

  // ── Remove batch ─────────────────────────────────────────────────────────

  Future<void> removeMessages(List<String> ids) async {
    for (final id in ids) {
      await LocalStorage.addDeletedId(id, roomKey: roomId);
    }
    final idSet = ids.toSet();
    state = state.where((m) => !idSet.contains(m.messageId)).toList();
  }

  // ── Replace temp message with server-confirmed one ────────────────────────

  void replaceTemp(String tempId, RemoteMessage real) {
    // 1. Try exact tempId match
    int idx = state.indexWhere((m) => m.messageId == tempId);

    // 2. Fallback: find any unsent (sending_*) bubble matching content+type+sender
    if (idx == -1) {
      idx = state.indexWhere((m) =>
          m.messageId?.startsWith('sending_') == true &&
          m.messageContent == real.messageContent &&
          m.senderDeviceId == real.senderDeviceId &&
          m.typeMessage == real.typeMessage);
    }

    if (idx == -1) {
      // No temp found — just add if the real message isn't already present
      final exists = state.any((m) => m.messageId == real.messageId);
      if (!exists) state = [...state, real];
      return;
    }
    final updated = List<RemoteMessage>.from(state);
    updated[idx] = real;
    state = updated;
    // Apply any delivery/read ack that arrived before replaceTemp ran
    _applyPendingStatus(real.messageId!);
  }

  void _applyPendingStatus(String msgId) async {
    final saved = await LocalStorage.getMessageStatuses(roomId);
    final status = saved[msgId];
    if (status != null) updateMessageStatus(msgId, status);
  }

  // ── Status update ─────────────────────────────────────────────────────────

  void updateMessageStatus(String id, int status) {
    bool changed = false;
    state = state.map((m) {
      if (m.messageId == id && m.status < status) {
        changed = true;
        return m.copyWith(status: status);
      }
      return m;
    }).toList();
    // Always persist — even if message wasn't in state yet (race with replaceTemp)
    LocalStorage.saveMessageStatus(roomId, id, status);
  }

  // ── Pin / unpin ───────────────────────────────────────────────────────────

  void pinMessage(String id, bool pinned) {
    state = state.map((m) {
      if (m.messageId == id) {
        return m.copyWith(
          isPin: pinned ? 1 : 0,
          pinTime: pinned ? DateTime.now().toIso8601String() : null,
        );
      }
      return m;
    }).toList();
  }

  // ── Update entire list from pin event ────────────────────────────────────

  void applyPinList(List<RemoteMessage> pinned) {
    final pinnedIds = {for (final m in pinned) m.messageId};
    state = state.map((m) {
      if (pinnedIds.contains(m.messageId)) {
        final p = pinned.firstWhere((x) => x.messageId == m.messageId);
        return m.copyWith(isPin: 1, pinTime: p.pinTime);
      } else {
        if (m.isPin == 1) return m.copyWith(isPin: 0, pinTime: null);
        return m;
      }
    }).toList();
  }

  List<RemoteMessage> get pinnedMessages =>
      state.where((m) => m.isPin == 1).toList();
}

/// Family provider: one notifier per room ID
final messagesProvider = StateNotifierProvider.family<MessagesNotifier,
    List<RemoteMessage>, String>(
  (ref, roomId) => MessagesNotifier(roomId),
);
