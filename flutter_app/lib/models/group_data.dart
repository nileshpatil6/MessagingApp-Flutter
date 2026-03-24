class GroupData {
  final String groupId;
  String groupName;
  String adminId;
  List<String> memberIds;
  String? iconUrl;
  final int createdAt;
  // Local state
  bool isMuted;
  int unreadCount;
  String? lastMessage;
  DateTime? lastMessageTime;

  GroupData({
    required this.groupId,
    required this.groupName,
    required this.adminId,
    required this.memberIds,
    this.iconUrl,
    required this.createdAt,
    this.isMuted = false,
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageTime,
  });

  factory GroupData.fromJson(Map<String, dynamic> json) {
    return GroupData(
      groupId: json['group_id'] ?? '',
      groupName: json['group_name'] ?? '',
      adminId: json['admin_id'] ?? '',
      memberIds: List<String>.from(json['member_ids'] ?? []),
      iconUrl: json['icon_url'],
      createdAt: json['created_at'] ?? 0,
      isMuted: json['is_muted'] ?? false,
      unreadCount: json['unread_count'] ?? 0,
      lastMessage: json['last_message'],
    );
  }

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'group_name': groupName,
        'admin_id': adminId,
        'member_ids': memberIds,
        'icon_url': iconUrl,
        'created_at': createdAt,
        'is_muted': isMuted,
        'unread_count': unreadCount,
        'last_message': lastMessage,
      };
}
