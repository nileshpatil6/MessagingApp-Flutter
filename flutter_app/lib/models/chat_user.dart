class ChatUser {
  final String deviceId;
  String name;
  final String socketId;
  bool connected;
  String? icon;
  // Local UI state
  bool isPinned;
  bool isHidden;
  bool isBlocked;
  bool isMuted;
  int unreadCount;
  String? lastMessage;
  DateTime? lastMessageTime;
  String? customName;
  String? customIcon;

  ChatUser({
    required this.deviceId,
    required this.name,
    required this.socketId,
    this.connected = true,
    this.icon,
    this.isPinned = false,
    this.isHidden = false,
    this.isBlocked = false,
    this.isMuted = false,
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageTime,
    this.customName,
    this.customIcon,
  });

  String get displayName => customName?.isNotEmpty == true ? customName! : name;
  String? get displayIcon => customIcon?.isNotEmpty == true ? customIcon : icon;

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      deviceId: json['device_id'] ?? '',
      name: json['name'] ?? '',
      socketId: json['socket_id'] ?? '',
      connected: json['connected'] ?? false,
      icon: json['icon'],
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'name': name,
        'socket_id': socketId,
        'connected': connected,
        'icon': icon,
      };
}
