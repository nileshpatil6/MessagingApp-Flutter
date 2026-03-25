/// Localisation strings for the messaging app.
/// [ja] = true → Japanese (primary), false → English.
class AppStrings {
  final bool ja;
  const AppStrings(this.ja);

  // ── Common ────────────────────────────────────────────────────────────────
  String get cancel => ja ? 'キャンセル' : 'Cancel';
  String get save => ja ? '保存' : 'Save';
  String get delete => ja ? '削除' : 'Delete';
  String get close => ja ? '閉じる' : 'Close';
  String get yes => ja ? 'はい' : 'Yes';
  String get no => ja ? 'いいえ' : 'No';
  String get ok => ja ? 'OK' : 'OK';
  String get online => ja ? 'オンライン' : 'Online';
  String get offline => ja ? 'オフライン' : 'Offline';
  String get copy => ja ? 'コピー' : 'Copy';
  String get reply => ja ? '返信' : 'Reply';
  String get forward => ja ? '転送' : 'Forward';
  String get pin => ja ? 'ピン留め' : 'Pin';
  String get unpin => ja ? 'ピンを外す' : 'Unpin';
  String get search => ja ? '検索' : 'Search';
  String get uploading => ja ? 'アップロード中…' : 'Uploading…';
  String get uploadFailed => ja ? 'アップロード失敗' : 'Upload failed';
  String get copied => ja ? 'コピーしました' : 'Copied';
  String get send => ja ? '送信' : 'Send';
  String get next => ja ? '次へ' : 'Next';
  String get camera => ja ? 'カメラ' : 'Camera';
  String get video => ja ? '動画' : 'Video';
  String get file => ja ? 'ファイル' : 'File';
  String get imageFromGallery => ja ? 'ギャラリーから画像' : 'Image from gallery';
  String get download => ja ? 'ダウンロード' : 'Download';
  String get downloadStarted => ja ? 'ダウンロードを開始しました' : 'Download started';
  String get share => ja ? 'シェア' : 'Share';

  // ── Main Screen ───────────────────────────────────────────────────────────
  String get messages => ja ? 'メッセージ' : 'Messages';
  String get chats => ja ? 'チャット' : 'Chats';
  String get groups => ja ? 'グループ' : 'Groups';
  String get searchChats => ja ? 'チャットを検索…' : 'Search chats…';
  String get createGroup => ja ? 'グループ作成' : 'Create group';
  String get noUsersOnline => ja ? 'オンラインユーザーなし' : 'No users online';
  String get pinnedSection => ja ? 'ピン留め' : 'Pinned';
  String get recentSection => ja ? '最近' : 'Recent';
  String get noGroupsYet => ja ? 'グループがありません' : 'No groups yet';
  String get createGroupButton => ja ? 'グループ作成' : 'Create Group';
  String get incomingCall => ja ? '着信' : 'Incoming call';
  String get decline => ja ? '拒否' : 'Decline';
  String get answer => ja ? '応答' : 'Answer';
  String get changeName => ja ? '名前を変更' : 'Change name';
  String get unpinFromTop => ja ? 'トップから外す' : 'Unpin from top';
  String get pinToTop => ja ? 'トップにピン留め' : 'Pin to top';
  String get turnNotificationsOff =>
      ja ? '通知をオフ' : 'Turn notifications off';
  String get turnNotificationsOn => ja ? '通知をオン' : 'Turn notifications on';
  String get hideFriend => ja ? 'この連絡先を非表示' : 'Hide this friend';
  String get blockFriend => ja ? 'この連絡先をブロック' : 'Block this friend';
  String get deleteMessages => ja ? 'メッセージを削除' : 'Delete messages';
  String get block => ja ? 'ブロック' : 'Block';
  String get renameContact => ja ? '連絡先名を変更' : 'Rename contact';
  String get customName => ja ? 'カスタム名' : 'Custom name';
  String get changeIcon => ja ? 'アイコンを変更' : 'Change icon';
  String get showQrCode => ja ? 'QRコードを表示' : 'Show QR code';
  String get scanQrCode => ja ? 'QRコードをスキャン' : 'Scan QR code';
  String get showHiddenUsers => ja ? '非表示ユーザーを表示' : 'Show hidden users';
  String get blockList => ja ? 'ブロックリスト' : 'Block list';
  String get myProfile => ja ? 'プロフィール' : 'My Profile';
  String get displayName => ja ? '表示名' : 'Display name';
  String get hiddenUsers => ja ? '非表示ユーザー' : 'Hidden users';
  String get noHiddenUsers => ja ? '非表示ユーザーなし' : 'No hidden users';
  String get unhide => ja ? '表示に戻す' : 'Unhide';
  String get blockedUsers => ja ? 'ブロック済みユーザー' : 'Blocked users';
  String get noBlockedUsers => ja ? 'ブロック済みユーザーなし' : 'No blocked users';
  String get unblock => ja ? 'ブロック解除' : 'Unblock';
  String get editProfile => ja ? 'プロフィール編集' : 'Edit Profile';
  String get pointCameraAtQr =>
      ja ? 'QRコードにカメラを向けてください' : 'Point camera at QR code';
  String get iconUpdated =>
      ja ? 'アイコンを更新しました' : 'Icon updated successfully';
  String get uploadIconFailed =>
      ja ? 'アップロードに失敗しました' : 'Upload failed';
  String get language => ja ? '言語' : 'Language';
  String get switchToEnglish => ja ? 'English に切り替え' : 'Switch to 日本語';

  // ── Dynamic main screen ───────────────────────────────────────────────────
  String callingYou(String name) =>
      ja ? '$name が電話しています' : '$name is calling you';
  String blockUserPrompt(String name) =>
      ja ? '$name をブロックしますか？' : 'Block $name?';
  String deleteMessagesFrom(String name) => ja
      ? '$name のメッセージをすべて削除しますか？この操作は取り消せません。'
      : 'Delete messages from $name? This cannot be undone.';
  String userNotOnline(String id) =>
      ja ? 'ユーザー「$id」は現在オンラインではありません。' : 'User "$id" is not online right now.';

  // ── Conversation Screen ───────────────────────────────────────────────────
  String get uploadingImage => ja ? '画像をアップロード中…' : 'Uploading image…';
  String get uploadingVideo => ja ? '動画をアップロード中…' : 'Uploading video…';
  String get uploadingFile => ja ? 'ファイルをアップロード中…' : 'Uploading file…';
  String get deleteMessage => ja ? 'メッセージを削除' : 'Delete message';
  String get deleteForEveryone =>
      ja ? '全員のメッセージを削除しますか？この操作は取り消せません。' : 'Delete for everyone? This cannot be undone.';
  String get searchMessages => ja ? 'メッセージを検索' : 'Search messages';
  String get searchMessagesHint => ja ? 'メッセージを検索…' : 'Search messages…';
  String get pinnedMessages => ja ? 'ピン留めメッセージ' : 'Pinned messages';
  String get selfDestruct => ja ? '自動削除' : 'Self-destruct';
  String get selectAll => ja ? 'すべて選択' : 'Select all';
  String get tapToDownload => ja ? 'タップしてダウンロード' : 'Tap to download';
  String get messageHint => ja ? 'メッセージ…' : 'Message…';
  String get setSelfDestructTimer =>
      ja ? '自動削除タイマーを設定' : 'Set self-destruct timer';
  String get selfDestructTimer => ja ? '自動削除タイマー' : 'Self-destruct timer';
  String get shareNotImplemented =>
      ja ? 'シェア機能は未実装です' : 'Share not yet implemented';

  String nSelected(int n) => ja ? '$n 件選択中' : '$n selected';
  String selfDestructBadge(String time) =>
      ja ? '自動削除: $time' : 'Self-destruct: $time';
  String deleteNMessages(int n) =>
      ja ? '$n 件のメッセージを削除' : 'Delete $n message(s)';

  // ── Group Conversation Screen ─────────────────────────────────────────────
  String get invitedToGroup => ja ? 'グループに招待されました' : 'You were invited to the group';
  String get memberLeftGroup =>
      ja ? 'メンバーがグループを退出しました' : 'A member left the group';
  String get groupNameChanged =>
      ja ? 'グループ名が変更されました' : 'Group name was changed';
  String get groupIconUpdated =>
      ja ? 'グループアイコンが更新されました' : 'Group icon was updated';
  String get renameGroup => ja ? 'グループ名を変更' : 'Rename group';
  String get newGroupName => ja ? '新しいグループ名' : 'New group name';
  String get deleteGroup => ja ? 'グループを削除' : 'Delete group';
  String get deleteGroupConfirm => ja
      ? 'このグループを全員から削除しますか？この操作は取り消せません。'
      : 'Delete this group for everyone? This cannot be undone.';
  String get leaveGroup => ja ? 'グループを退出' : 'Leave group';
  String get leaveGroupConfirm =>
      ja ? 'このグループを退出しますか？' : 'Are you sure you want to leave this group?';
  String get leave => ja ? '退出' : 'Leave';
  String get viewMembers => ja ? 'メンバーを表示' : 'View members';
  String get admin => ja ? '管理者' : 'Admin';
  String get deleteForEveryoneGroup =>
      ja ? '全員のメッセージを削除しますか？' : 'Delete for everyone?';

  String nMembers(int n) => ja ? '$n 人のメンバー' : '$n members';
  String membersSection(int n) => ja ? 'メンバー（$n）' : 'Members ($n)';

  // ── Create Group Screen ───────────────────────────────────────────────────
  String get newGroup => ja ? '新しいグループ' : 'New Group';
  String get selectMembers => ja ? 'メンバーを選択' : 'Select members';
  String get noUsersOnlineGroup => ja ? 'オンラインユーザーなし' : 'No users online';
  String get groupDetails => ja ? 'グループ詳細' : 'Group Details';
  String get groupNameLabel => ja ? 'グループ名 *' : 'Group name *';
  String get groupNameHint => ja ? 'グループ名を入力' : 'Enter group name';
  String get createGroupAction => ja ? 'グループ作成' : 'Create Group';
  String get selectAtLeastOneMember =>
      ja ? 'メンバーを1人以上選択してください' : 'Select at least one member';
  String get groupNameRequired =>
      ja ? 'グループ名を入力してください' : 'Group name is required';

  String nextWithCount(int n) => ja ? '次へ（$n）' : 'Next ($n)';
  String membersWillBeAdded(int n) =>
      ja ? '$n 人のメンバーを追加します' : '$n members will be added';
  String groupCreated(String name) =>
      ja ? 'グループ「$name」を作成しました' : 'Group "$name" created';

  // ── Forward Screen ────────────────────────────────────────────────────────
  String get forwardTo => ja ? '転送先' : 'Forward to';
  String get noUsersAvailable => ja ? '利用可能なユーザーなし' : 'No users available';
  String get selectAtLeastOneUser =>
      ja ? 'ユーザーを1人以上選択してください' : 'Select at least one user';

  String forwardingNMessages(int n) =>
      ja ? '$n 件のメッセージを転送' : 'Forwarding $n message(s)';
  String sendToN(int n) => ja ? '$n 人に送信' : 'Send to $n';
  String forwardedToN(int n) =>
      ja ? '$n 件の連絡先に転送しました' : 'Forwarded to $n contact(s)';

  // ── Pin Messages Screen ───────────────────────────────────────────────────
  String get pinnedMessagesTitle => ja ? 'ピン留めメッセージ' : 'Pinned Messages';
  String pinnedMessagesCount(int n) =>
      ja ? 'ピン留めメッセージ（$n）' : 'Pinned Messages ($n)';
  String get noPinnedMessages =>
      ja ? 'ピン留めメッセージなし' : 'No pinned messages';
  String get pinnedInstructions => ja
      ? 'メッセージを長押しして「ピン留め」を\nタップすると追加されます'
      : 'Long-press a message and tap Pin\nto add it here';
  String get pinnedLabel => ja ? 'ピン留め' : 'Pinned';
  String get unpinMessage => ja ? 'ピンを外す' : 'Unpin message';
  String get removeFromPinned =>
      ja ? 'このメッセージのピン留めを解除しますか？' : 'Remove this message from pinned?';

  // ── Self-Destruct Screen ──────────────────────────────────────────────────
  String get selfDestructTimerTitle => ja ? '自動削除タイマー' : 'Self-Destruct Timer';
  String get selfDestructDescription => ja
      ? 'この時間後、両側のメッセージが自動的に削除されます。'
      : 'Messages will automatically be deleted after this time for both sides.';
  String get off => ja ? 'オフ' : 'Off';
  String get fiveSeconds => ja ? '5秒' : '5 seconds';
  String get thirtySeconds => ja ? '30秒' : '30 seconds';
  String get oneMinute => ja ? '1分' : '1 minute';
  String get fiveMinutes => ja ? '5分' : '5 minutes';
  String get thirtyMinutes => ja ? '30分' : '30 minutes';
  String get oneHour => ja ? '1時間' : '1 hour';
  String get oneDay => ja ? '1日' : '1 day';
  String get oneWeek => ja ? '1週間' : '1 week';
  String get oneMonth => ja ? '1ヶ月' : '1 month';
  String get customHours => ja ? 'カスタム（時間）' : 'Custom (hours)';
  String get customHoursHint => ja ? '例：48' : 'e.g. 48';
  String get set => ja ? '設定' : 'Set';
  String get customDateTime => ja ? 'カスタム日時' : 'Custom date & time';
  String get pickDateTime => ja ? '特定の日時を選択' : 'Pick a specific date and time';
  String get enterValidHours =>
      ja ? '有効な時間数を入力してください' : 'Enter a valid number of hours';

  String currentlySet(String val) =>
      ja ? '現在の設定: $val' : 'Currently set: $val';

  // ── Photo View Screen ─────────────────────────────────────────────────────
  String get failedToLoadImage =>
      ja ? '画像の読み込みに失敗しました' : 'Failed to load image';

  // ── Video Player Screen ───────────────────────────────────────────────────
  String get failedToLoadVideo =>
      ja ? '動画の読み込みに失敗しました' : 'Failed to load video';
}
