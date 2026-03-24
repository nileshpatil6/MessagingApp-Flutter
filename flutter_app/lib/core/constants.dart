class AppConstants {
  static const String serverUrl = 'http://153.127.16.117:3000';

  // Socket events — emit
  static const String pvAccess = 'pv_access';
  static const String pvGetUserList = 'pv_getUserList';
  static const String pvUpdateUserName = 'pv_updateUserName';
  static const String pvJoinRoom = 'pv_joinRoom';
  static const String pvAutoJoinRoomClient = 'pv_autoJoinRoomClient';
  static const String pvSendMessage = 'pv_sendMessage';
  static const String pvMessageRead = 'pv_messageRead';
  static const String pvMessageDelivered = 'pv_messageDelivered';
  static const String pvDeleteMessage = 'pv_deleteMessage';
  static const String pvDeleteMessages = 'pv_deleteMessages';
  static const String pvForwardMessage = 'pv_forwardMessage';
  static const String pvPinMessage = 'pv_pinMessage';
  static const String pvPong = 'pv_pong';
  static const String batteryChange = 'batteryChange';

  // Socket events — listen
  static const String pvListUser = 'pv_listUser';
  static const String pvRoomId = 'pv_roomId';
  static const String pvAutoJoinRoom = 'pv_autoJoinRoom';
  static const String pvListMessage = 'pv_listMessage';
  static const String pvMessageSended = 'pv_messageSended';
  static const String pvMessageDeleted = 'pv_messageDeleted';
  static const String pvMessagesDeleted = 'pv_messagesDeleted';
  static const String pvMessagePinList = 'pv_messagePinList';
  static const String pvUpdateUserNameStatus = 'pv_updateUserNameStatus';
  static const String pvErrorDuplicateName = 'pv_error_duplicate_name';
  static const String ping = 'ping';

  // REST
  static const String uploadFileChatUrl = '$serverUrl/upload_file_chat';

  // WebRTC
  static const String rtcMessage = 'message'; // relay event
  static const String createOrJoin = 'create or join';
  static const String created = 'created';
  static const String joined = 'joined';
  static const String join = 'join';
  static const String ready = 'ready';
  static const String bye = 'bye';
  static const String message = 'message';
  static const String switchCamera = 'switchCamera';

  static const String turnUri = 'turn:153.127.16.117:2222?transport=tcp';
  static const String turnUsername = 'sakura';
  static const String turnPassword = 'sakura123456';

  // Group message prefixes
  static const String grpPrefix = '[GRP:';
  static const String grpInvPrefix = '[GRP_INV:';
  static const String grpLeavePrefix = '[GRP_LEAVE:';
  static const String grpNamePrefix = '[GRP_NAME:';
  static const String grpIconPrefix = '[GRP_ICON:';

  // Message types
  static const int typeText = 0;
  static const int typeImage = 1;
  static const int typeVideo = 2;
  static const int typeFile = 3;

  // Message status
  static const int statusSending = 0;
  static const int statusSent = 1;
  static const int statusDelivered = 2;
  static const int statusRead = 3;
}
