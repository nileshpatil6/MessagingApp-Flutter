// status: 0=sending, 1=sent, 2=delivered, 3=read
class RemoteMessage {
  final String? messageId;
  final dynamic roomId;
  final String? messageContent;
  final String? deadTime;
  final String? senderDeviceId;
  final String? receiverDeviceId;
  final int typeMessage;
  final String? createdAt;
  final int? replyMessageId;
  final RemoteMessage? replyMessage;
  final int isPin;
  final String? pinTime;
  final int status; // 0=sending,1=sent,2=delivered,3=read

  RemoteMessage({
    this.messageId,
    this.roomId,
    this.messageContent,
    this.deadTime,
    this.senderDeviceId,
    this.receiverDeviceId,
    this.typeMessage = 0,
    this.createdAt,
    this.replyMessageId,
    this.replyMessage,
    this.isPin = 0,
    this.pinTime,
    this.status = 1,
  });

  factory RemoteMessage.fromJson(Map<String, dynamic> json) {
    return RemoteMessage(
      messageId: json['message_id']?.toString(),
      roomId: json['room_id'],
      messageContent: json['message_content'],
      deadTime: json['dead_time'],
      senderDeviceId: json['sender_device_id'],
      receiverDeviceId: json['receiver_device_id'],
      typeMessage: int.tryParse(json['type_message']?.toString() ?? '0') ?? 0,
      createdAt: json['created_at']?.toString(),
      replyMessageId: json['reply_message_id'],
      replyMessage: json['reply_message'] != null
          ? RemoteMessage.fromJson(json['reply_message'])
          : null,
      isPin: json['is_pin'] ?? 0,
      pinTime: json['pin_time']?.toString(),
      status: int.tryParse(json['status']?.toString() ?? '1') ?? 1,
    );
  }

  RemoteMessage copyWith({
    String? messageId,
    String? messageContent,
    int? status,
    int? isPin,
    String? pinTime,
    String? deadTime,
  }) {
    return RemoteMessage(
      messageId: messageId ?? this.messageId,
      roomId: roomId,
      messageContent: messageContent ?? this.messageContent,
      deadTime: deadTime ?? this.deadTime,
      senderDeviceId: senderDeviceId,
      receiverDeviceId: receiverDeviceId,
      typeMessage: typeMessage,
      createdAt: createdAt,
      replyMessageId: replyMessageId,
      replyMessage: replyMessage,
      isPin: isPin ?? this.isPin,
      pinTime: pinTime ?? this.pinTime,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'room_id': roomId,
        'message_content': messageContent,
        'dead_time': deadTime,
        'sender_device_id': senderDeviceId,
        'receiver_device_id': receiverDeviceId,
        'type_message': typeMessage,
        'created_at': createdAt,
        'reply_message_id': replyMessageId,
        'is_pin': isPin,
        'pin_time': pinTime,
        'status': status,
      };
}
