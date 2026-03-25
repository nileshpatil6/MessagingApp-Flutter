import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Equivalent of Android SaveChatsData — stores deleted IDs, seen/delivered IDs,
/// user preferences, group data, and message cache per room.
class LocalStorage {
  static const _deletedIdsKey = 'deleted_message_ids';
  static const _seenIdsKey = 'seen_message_ids';
  static const _deliveredIdsKey = 'delivered_message_ids';
  static const _groupsKey = 'all_groups';
  static const _usersKey = 'saved_users';
  static const _selfDestructKey = 'self_destruct';

  // ── DELETED MESSAGE IDS ──────────────────────

  static String _deletedRoomKey(String roomKey) => '${_deletedIdsKey}_$roomKey';

  static Future<Set<String>> getDeletedIds(String? roomKey) async {
    final prefs = await SharedPreferences.getInstance();
    final global = prefs.getStringList(_deletedIdsKey)?.toSet() ?? {};
    if (roomKey != null && roomKey.isNotEmpty) {
      final roomSet = prefs.getStringList(_deletedRoomKey(roomKey))?.toSet() ?? {};
      return {...global, ...roomSet};
    }
    return global;
  }

  static Future<void> addDeletedId(String id, {String? roomKey}) async {
    final prefs = await SharedPreferences.getInstance();
    final global = prefs.getStringList(_deletedIdsKey)?.toSet() ?? {};
    global.add(id);
    await prefs.setStringList(_deletedIdsKey, global.toList());
    if (roomKey != null && roomKey.isNotEmpty) {
      final key = _deletedRoomKey(roomKey);
      final roomSet = prefs.getStringList(key)?.toSet() ?? {};
      roomSet.add(id);
      await prefs.setStringList(key, roomSet.toList());
    }
  }

  static Future<void> removeDeletedId(String id, {String? roomKey}) async {
    final prefs = await SharedPreferences.getInstance();
    final global = prefs.getStringList(_deletedIdsKey)?.toSet() ?? {};
    global.remove(id);
    await prefs.setStringList(_deletedIdsKey, global.toList());
    if (roomKey != null && roomKey.isNotEmpty) {
      final key = _deletedRoomKey(roomKey);
      final roomSet = prefs.getStringList(key)?.toSet() ?? {};
      roomSet.remove(id);
      await prefs.setStringList(key, roomSet.toList());
    }
  }

  static Future<bool> isDeleted(String id, {String? roomKey}) async {
    final ids = await getDeletedIds(roomKey);
    return ids.contains(id);
  }

  // ── SEEN / DELIVERED ─────────────────────────

  static Future<Set<String>> getSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_seenIdsKey)?.toSet() ?? {};
  }

  static Future<void> addSeenId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final set = prefs.getStringList(_seenIdsKey)?.toSet() ?? {};
    set.add(id);
    await prefs.setStringList(_seenIdsKey, set.toList());
  }

  static Future<Set<String>> getDeliveredIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_deliveredIdsKey)?.toSet() ?? {};
  }

  static Future<void> addDeliveredId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final set = prefs.getStringList(_deliveredIdsKey)?.toSet() ?? {};
    set.add(id);
    await prefs.setStringList(_deliveredIdsKey, set.toList());
  }

  // ── MESSAGE STATUS ───────────────────────────

  static String _statusKey(String roomId) => 'msg_status_$roomId';

  static Future<Map<String, int>> getMessageStatuses(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statusKey(roomId));
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  static Future<void> saveMessageStatus(
      String roomId, String msgId, int status) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _statusKey(roomId);
    final raw = prefs.getString(key);
    final map = raw != null
        ? Map<String, int>.from(
            (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())))
        : <String, int>{};
    // Only ever upgrade status, never downgrade
    if ((map[msgId] ?? 0) < status) {
      map[msgId] = status;
      await prefs.setString(key, jsonEncode(map));
    }
  }

  // ── GROUPS ───────────────────────────────────

  static Future<List<Map<String, dynamic>>> getGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_groupsKey);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(raw));
  }

  static Future<void> saveGroups(List<Map<String, dynamic>> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupsKey, jsonEncode(groups));
  }

  // ── USERS ────────────────────────────────────

  static const _knownUsersKey = 'known_user_ids';

  static Future<List<String>> getKnownUserIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_knownUsersKey) ?? [];
  }

  static Future<void> addKnownUserId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final set = prefs.getStringList(_knownUsersKey)?.toSet() ?? {};
    set.add(deviceId);
    await prefs.setStringList(_knownUsersKey, set.toList());
  }

  static Future<Map<String, dynamic>?> getUserPrefs(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_prefs_$deviceId');
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  static Future<void> saveUserPrefs(String deviceId, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_prefs_$deviceId', jsonEncode(data));
  }

  /// Update only lastMessage + lastMessageTime without overwriting other prefs.
  static Future<void> updateUserLastMessage(
      String deviceId, String message, DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'user_prefs_$deviceId';
    final raw = prefs.getString(key);
    final data = raw != null
        ? Map<String, dynamic>.from(jsonDecode(raw))
        : <String, dynamic>{};
    data['last_message'] = message;
    data['last_message_time'] = time.toIso8601String();
    await prefs.setString(key, jsonEncode(data));
  }

  // ── SELF DESTRUCT ────────────────────────────

  static Future<Map<String, dynamic>?> getSelfDestruct() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_selfDestructKey);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  static Future<void> saveSelfDestruct(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selfDestructKey, jsonEncode(data));
  }

  // ── DEVICE INFO ──────────────────────────────

  static Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id');
  }

  static Future<void> setDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_id', id);
  }

  static Future<String?> getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_name');
  }

  static Future<void> setDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', name);
  }

  // ── NOTIFICATIONS ─────────────────────────────────────────────────────────

  static Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_enabled') ?? true;
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);
  }

  // ── ROOM ID CACHE ─────────────────────────────

  static Future<void> saveRoomId(String partnerDeviceId, String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('room_id_$partnerDeviceId', roomId);
  }

  static Future<String?> loadRoomId(String partnerDeviceId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('room_id_$partnerDeviceId');
  }

  // ── MESSAGE CACHE ─────────────────────────────

  static Future<void> saveCachedMessages(
      String roomId, List<Map<String, dynamic>> messages) async {
    final prefs = await SharedPreferences.getInstance();
    // Keep last 100 messages to limit storage
    final limited = messages.length > 100
        ? messages.sublist(messages.length - 100)
        : messages;
    await prefs.setString('msg_cache_$roomId', jsonEncode(limited));
  }

  static Future<List<Map<String, dynamic>>> loadCachedMessages(
      String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('msg_cache_$roomId');
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── LANGUAGE ──────────────────────────────────

  /// Returns true if Japanese is selected (default).
  static Future<bool> getIsJapanese() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_japanese') ?? true;
  }

  static Future<void> setIsJapanese(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_japanese', value);
  }

  // ── RESET ─────────────────────────────────────

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
