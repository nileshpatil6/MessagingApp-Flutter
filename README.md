# Pulse Chat

A full-stack, real-time messaging application built with Flutter and FastAPI. Supports private chats, group conversations, media sharing, self-destruct messages, WebRTC video/voice calls, and bilingual UI (English / Japanese).

---

## Features

### Messaging
- Real-time private and group messaging over Socket.IO
- Message delivery receipts: sent, delivered, read (single / double / blue ticks)
- Reply to specific messages with inline quote preview
- Forward messages to any contact or group
- Multi-select and bulk delete
- Copy message text to clipboard
- Message search within any conversation

### Groups
- Create groups with a custom name and icon
- Admin controls: rename group, change group icon, view members
- Invite members via QR code scan or manual selection
- Members can leave; admin can dissolve the group
- Real-time sync of name and icon changes to all members

### Media
- Send images, videos, and files from gallery, camera, or file picker
- Instant in-chat preview with upload progress spinner before the server URL resolves
- Full-screen image viewer with pinch-to-zoom
- In-app video player
- File download support

### Self-Destruct Messages
- Per-conversation configurable timers: 5 seconds, 30 seconds, 1 minute, 5 minutes, 30 minutes, 1 hour, 1 day, 1 week, 1 month, or a custom duration
- Countdown display on each message bubble
- Automatic deletion from both sender and recipient devices when the timer expires

### Calls
- WebRTC peer-to-peer video and voice calls
- TURN server relay for NAT traversal
- Incoming call notification with accept / decline

### Contacts
- QR code generation for your own profile (share your device ID)
- QR code scanner to add a contact instantly
- Rename a contact with a custom display name
- Change a contact's display avatar
- Hide contacts from the main list
- Block and unblock contacts

### Notifications
- Firebase Cloud Messaging (FCM) push notifications for new messages
- Mute notifications per conversation
- Foreground in-app banner when a message arrives in another chat

### Persistence and UX
- Offline message cache via SharedPreferences: history survives app restarts
- Pinned messages per conversation with a dismissible banner
- Pin any chat to the top of the list
- Emoji picker built into the message input bar
- Light and dark theme following system preference
- Bilingual UI: English and Japanese

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter 3, Dart 3 |
| State management | Riverpod 2 |
| Real-time transport | Socket.IO (socket_io_client) |
| HTTP client | Dio |
| Video / voice calls | flutter_webrtc + TURN server |
| Push notifications | Firebase Messaging + flutter_local_notifications |
| Media | image_picker, file_picker, photo_view, video_player |
| QR | qr_flutter, mobile_scanner |
| Local storage | SharedPreferences, sqflite |
| Backend framework | FastAPI + python-socketio |
| Backend database | SQLite (aiosqlite) |
| File serving | Static files via FastAPI FileResponse |
| Process manager | systemd + uvicorn |
| Deployment | VPS over SSH/SFTP (paramiko) |

---

## Project Structure

```
MessagingApp-Flutter/
├── flutter_app/                 # Flutter mobile application
│   ├── lib/
│   │   ├── core/
│   │   │   ├── constants.dart       # Server URLs, socket event names, type constants
│   │   │   ├── local_storage.dart   # SharedPreferences helpers
│   │   │   ├── notification_service.dart
│   │   │   └── socket_client.dart   # Singleton Socket.IO wrapper
│   │   ├── l10n/
│   │   │   └── app_strings.dart     # English / Japanese strings
│   │   ├── models/
│   │   │   ├── chat_user.dart
│   │   │   ├── group_data.dart
│   │   │   └── remote_message.dart
│   │   ├── providers/
│   │   │   ├── groups_provider.dart
│   │   │   ├── locale_provider.dart
│   │   │   ├── messages_provider.dart
│   │   │   └── users_provider.dart
│   │   ├── screens/
│   │   │   ├── main_screen.dart             # Contact list, group list, settings
│   │   │   ├── conversation_screen.dart     # Private chat
│   │   │   ├── group_conversation_screen.dart
│   │   │   ├── create_group_screen.dart
│   │   │   ├── call_screen.dart             # WebRTC call UI
│   │   │   ├── self_destruct_screen.dart    # Timer configuration
│   │   │   ├── pin_messages_screen.dart
│   │   │   ├── forward_screen.dart
│   │   │   ├── photo_view_screen.dart
│   │   │   └── video_player_screen.dart
│   │   └── main.dart
│   └── pubspec.yaml
├── backend/                     # FastAPI + Socket.IO backend
│   ├── app/
│   │   ├── database.py          # aiosqlite connection helpers
│   │   ├── routes.py            # REST endpoints (upload, auth, file serving)
│   │   ├── scheduler.py         # APScheduler jobs (cleanup, etc.)
│   │   └── sockets.py           # Socket.IO event handlers
│   ├── models/                  # Async DB model helpers
│   ├── main.py                  # FastAPI + Socket.IO app entry point
│   └── requirements.txt
└── deploy.py                    # One-command SSH deployment to VPS
```

---

## Getting Started

### Prerequisites

- Flutter SDK 3.x ([install](https://docs.flutter.dev/get-started/install))
- Dart SDK 3.x (included with Flutter)
- Python 3.9+ for the backend
- An Android or iOS device / emulator

---

### Backend Setup

#### Option A: Deploy to a VPS (recommended)

Edit `deploy.py` with your server credentials:

```python
HOST = "your.server.ip"
PORT = 22
USER = "root"
PASSWORD = "yourpassword"
```

Then run:

```bash
pip install paramiko
python deploy.py
```

The script compiles Python 3.9 if needed, uploads the backend, installs dependencies, creates a systemd service, and starts it on port 3000.

#### Option B: Run locally

```bash
cd backend
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:socket_app --host 0.0.0.0 --port 3000 --reload
```

---

### Flutter Setup

**1. Update the server URL**

Open `flutter_app/lib/core/constants.dart` and set your backend address:

```dart
static const String serverUrl = 'http://YOUR_SERVER_IP:3000';
```

**2. Firebase (optional, for push notifications)**

- Create a Firebase project and add an Android / iOS app
- Download `google-services.json` (Android) or `GoogleService-Info.plist` (iOS) and place them in the standard Flutter locations
- If you skip this step, the app works without push notifications (the Firebase init is wrapped in a try/catch)

**3. Install dependencies and run**

```bash
cd flutter_app
flutter pub get
flutter run
```

---

### TURN Server (for WebRTC calls across different networks)

If you want video/voice calls to work across NAT, set up a TURN server (e.g. coturn) and update these constants in `constants.dart`:

```dart
static const String turnUri      = 'turn:your.server.ip:3478?transport=tcp';
static const String turnUsername = 'yourusername';
static const String turnPassword = 'yourpassword';
```

---

## Configuration

### Self-Destruct Timers

Available options (configurable per conversation from the settings screen):

| Label | Duration |
|---|---|
| Off | No expiry |
| 5 seconds | 5 s |
| 30 seconds | 30 s |
| 1 minute | 60 s |
| 5 minutes | 300 s |
| 30 minutes | 1800 s |
| 1 hour | 3600 s |
| 1 day | 86400 s |
| 1 week | 604800 s |
| 1 month | 2592000 s |
| Custom | Any number of seconds |

### Language

The UI language switches between English and Japanese. The setting is stored locally and can be toggled from the profile screen.

---

## How It Works

### Identity

Each device gets a unique device ID generated from the platform hardware ID (Android ID / iOS identifierForVendor). This ID is used as the socket identity. No account registration is required.

### Message Delivery

1. Sender emits `pv_sendMessage` with the recipient's device ID.
2. The backend delivers it directly to the recipient's socket if they are online.
3. If the recipient is offline, the message is stored in SQLite and replayed on reconnect (private chats only).
4. Group messages are not stored server-side; they are delivered in real time to each member individually.
5. Delivery and read receipts flow back through dedicated socket events.

### Group Protocol

All group messages travel over private message sockets using a wire format prefix:

```
[GRP:groupId]:actual message content
```

System events (name change, icon change, member leave) use nested prefixes inside the group envelope:

```
[GRP:groupId]:[GRP_NAME:groupId:new name]
[GRP:groupId]:[GRP_ICON:groupId:https://...]
[GRP:groupId]:[GRP_LEAVE:groupId]
```

### File Uploads

Files are uploaded to the `/upload_file_chat` REST endpoint before the socket message is sent. The server stores them under `uploads/public/` with a timestamp suffix to avoid collisions and returns a public URL. The Flutter app shows the local file immediately with a spinner overlay while the upload is in progress, then replaces it with the server URL once the upload completes.

---

## Socket Events Reference

| Event | Direction | Description |
|---|---|---|
| `pv_access` | Client to Server | Register device ID and display name |
| `pv_getUserList` | Client to Server | Request online user list |
| `pv_joinRoom` | Client to Server | Open a private chat room |
| `pv_sendMessage` | Client to Server | Send a message (private or group) |
| `pv_messageRead` | Client to Server | Mark a message as read |
| `pv_deleteMessage` | Client to Server | Delete a single message |
| `pv_deleteMessages` | Client to Server | Bulk delete messages |
| `pv_pinMessage` | Client to Server | Pin or unpin a message |
| `pv_listUser` | Server to Client | Broadcast updated online user list |
| `pv_messageSended` | Server to Client | Deliver an incoming message |
| `pv_messageDelivered` | Server to Client | Delivery receipt |
| `pv_messageRead` | Server to Client | Read receipt |
| `pv_messagePinList` | Server to Client | Current pinned messages for a room |

---

## REST Endpoints

| Method | Path | Description |
|---|---|---|
| POST | `/upload_file_chat` | Upload a single file; returns `{files: [{filename, url}]}` |
| GET | `/public/{name}` | Serve an uploaded file |
| POST | `/upload_file` | Upload multiple files (non-chat) |
| GET | `/download_file/{id}` | Download a file by ID |

---

## License

MIT
