import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/local_storage.dart';
import 'core/notification_service.dart';
import 'core/socket_client.dart';
import 'models/chat_user.dart';
import 'models/group_data.dart';
import 'models/remote_message.dart';
import 'screens/call_screen.dart';
import 'screens/conversation_screen.dart';
import 'screens/create_group_screen.dart';
import 'screens/forward_screen.dart';
import 'screens/group_conversation_screen.dart';
import 'screens/main_screen.dart';
import 'screens/photo_view_screen.dart';
import 'screens/pin_messages_screen.dart';
import 'screens/self_destruct_screen.dart';
import 'screens/video_player_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init (optional — wrap in try/catch so app runs without config)
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase not configured — continue without it
  }

  // Device ID setup
  await _setupDeviceId();

  // Init notifications
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermission();

  // Connect socket early
  SocketClient.instance.connect();

  // Global socket listener — shows notification for incoming messages
  _setupGlobalSocketListeners();

  runApp(
    const ProviderScope(
      child: MessagingApp(),
    ),
  );
}

Future<void> _setupDeviceId() async {
  var deviceId = await LocalStorage.getDeviceId();
  var deviceName = await LocalStorage.getDeviceName();

  if (deviceId == null || deviceId.isEmpty) {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        deviceId = android.id;
        deviceName ??=
            '${android.brand} ${android.model}'.trim();
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        deviceId = ios.identifierForVendor ?? _fallbackId();
        deviceName ??= ios.name;
      } else {
        deviceId = _fallbackId();
        deviceName ??= 'Flutter Device';
      }
    } catch (_) {
      deviceId = _fallbackId();
      deviceName ??= 'Flutter Device';
    }

    await LocalStorage.setDeviceId(deviceId);
    await LocalStorage.setDeviceName(deviceName);
    }
}

String _fallbackId() =>
    'device_${DateTime.now().millisecondsSinceEpoch}';

void _setupGlobalSocketListeners() {
  // Persist delivery/read status globally so it survives screen navigation
  SocketClient.instance.on(AppConstants.pvMessageDelivered, (data) async {
    if (data == null) return;
    dynamic parsed;
    try {
      parsed = data is String ? jsonDecode(data) : data;
    } catch (_) {
      return;
    }
    if (parsed is! Map) return;
    final msgId = parsed['message_id']?.toString();
    final roomId = parsed['room_id']?.toString();
    if (msgId != null && roomId != null && roomId.isNotEmpty) {
      await LocalStorage.saveMessageStatus(roomId, msgId, AppConstants.statusDelivered);
    }
  });

  SocketClient.instance.on(AppConstants.pvMessageRead, (data) async {
    if (data == null) return;
    dynamic parsed;
    try {
      parsed = data is String ? jsonDecode(data) : data;
    } catch (_) {
      return;
    }
    if (parsed is! Map) return;
    final msgId = parsed['message_id']?.toString();
    final roomId = parsed['room_id']?.toString();
    if (msgId != null && roomId != null && roomId.isNotEmpty) {
      await LocalStorage.saveMessageStatus(roomId, msgId, AppConstants.statusRead);
    }
  });

  SocketClient.instance.on(AppConstants.pvMessageSended, (data) async {
    if (data == null) return;
    dynamic parsed;
    try {
      parsed = data is String ? jsonDecode(data) : data;
    } catch (_) {
      return;
    }
    if (parsed is! Map) return;

    final myDeviceId = await LocalStorage.getDeviceId();
    final senderId = parsed['sender_device_id']?.toString();
    if (senderId == null || senderId == myDeviceId) return;

    // Look up sender name from saved users
    final content = parsed['message_content']?.toString() ?? '';
    final typeMessage = int.tryParse(parsed['type_message']?.toString() ?? '0') ?? 0;
    final body = typeMessage == 0
        ? (content.isNotEmpty ? content : 'New message')
        : typeMessage == 1
            ? 'Sent a photo'
            : typeMessage == 2
                ? 'Sent a video'
                : 'Sent a file';

    // Get display name from saved users
    final prefs = await LocalStorage.getUserPrefs(senderId);
    final senderName = prefs?['display_name']?.toString() ?? 'New message';

    await NotificationService.instance.showMessage(
      senderName: senderName,
      body: body,
      senderDeviceId: senderId,
    );
  });
}

// ── App ───────────────────────────────────────────────────────────────────────

class MessagingApp extends StatelessWidget {
  const MessagingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messaging',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      initialRoute: '/',
      onGenerateRoute: _generateRoute,
    );
  }

  ThemeData _lightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  ThemeData _darkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          builder: (_) => const MainScreen(),
          settings: settings,
        );

      case '/conversation':
        final user = settings.arguments as ChatUser;
        return MaterialPageRoute(
          builder: (_) => ConversationScreen(user: user),
          settings: settings,
        );

      case '/group_conversation':
        final group = settings.arguments as GroupData;
        return MaterialPageRoute(
          builder: (_) => GroupConversationScreen(group: group),
          settings: settings,
        );

      case '/create_group':
        return MaterialPageRoute(
          builder: (_) => const CreateGroupScreen(),
          settings: settings,
        );

      case '/forward':
        final messages = settings.arguments as List<RemoteMessage>;
        return MaterialPageRoute(
          builder: (_) => ForwardScreen(messages: messages),
          settings: settings,
        );

      case '/pin_messages':
        final roomId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => PinMessagesScreen(roomId: roomId),
          settings: settings,
        );

      case '/self_destruct':
        return MaterialPageRoute(
          builder: (_) => const SelfDestructScreen(),
          settings: settings,
        );

      case '/photo_view':
        final imageUrl = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => PhotoViewScreen(imageUrl: imageUrl),
          settings: settings,
        );

      case '/video_player':
        final videoUrl = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(videoUrl: videoUrl),
          settings: settings,
        );

      case '/call':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => CallScreen(
            user: args['user'] as ChatUser,
            isCaller: args['isCaller'] as bool,
          ),
          settings: settings,
        );

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Not found')),
            body: Center(
              child: Text(
                'No route defined for "${settings.name}"',
              ),
            ),
          ),
        );
    }
  }
}
