import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/socket_client.dart';
import '../l10n/app_strings.dart';
import '../models/chat_user.dart';
import '../models/remote_message.dart';
import '../providers/locale_provider.dart';
import '../providers/users_provider.dart';

class ForwardScreen extends ConsumerStatefulWidget {
  final List<RemoteMessage> messages;

  const ForwardScreen({super.key, required this.messages});

  @override
  ConsumerState<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends ConsumerState<ForwardScreen> {
  AppStrings get _s => AppStrings(ref.read(localeProvider));

  final Set<String> _selectedDeviceIds = {};
  bool _isSending = false;

  void _toggleSelection(String deviceId) {
    setState(() {
      if (_selectedDeviceIds.contains(deviceId)) {
        _selectedDeviceIds.remove(deviceId);
      } else {
        _selectedDeviceIds.add(deviceId);
      }
    });
  }

  Future<void> _forward() async {
    if (_selectedDeviceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.selectAtLeastOneUser)),
      );
      return;
    }

    setState(() => _isSending = true);

    final myId = ref.read(usersProvider).myDeviceId;
    final users = ref.read(usersProvider).users;

    for (final deviceId in _selectedDeviceIds) {
      final user = users.firstWhere(
        (u) => u.deviceId == deviceId,
        orElse: () => ChatUser(
            deviceId: deviceId,
            name: deviceId,
            socketId: ''),
      );

      for (final msg in widget.messages) {
        SocketClient.instance.emit(AppConstants.pvForwardMessage, {
          'message_id': msg.messageId,
          'message_content': msg.messageContent,
          'type_message': msg.typeMessage,
          'sender_device_id': myId,
          'receiver_device_id': deviceId,
          'receiver_socket_id': user.socketId,
        });
      }
    }

    setState(() => _isSending = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.forwardedToN(_selectedDeviceIds.length))),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final s = _s;
    final users = ref.watch(usersProvider).users;
    final myId = ref.read(usersProvider).myDeviceId;
    final filteredUsers =
        users.where((u) => u.deviceId != myId && !u.isBlocked).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.forwardTo),
            if (_selectedDeviceIds.isNotEmpty)
              Text(
                s.nSelected(_selectedDeviceIds.length),
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          if (_selectedDeviceIds.isNotEmpty)
            _isSending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _forward,
                    tooltip: s.forward,
                  ),
        ],
      ),
      body: Column(
        children: [
          // Preview of messages being forwarded
          Container(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withOpacity(0.5),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.forward, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.forwardingNMessages(widget.messages.length),
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // User list
          Expanded(
            child: filteredUsers.isEmpty
                ? Center(child: Text(s.noUsersAvailable))
                : ListView.builder(
                    itemCount: filteredUsers.length,
                    itemBuilder: (_, i) =>
                        _buildUserTile(filteredUsers[i], context, s),
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectedDeviceIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isSending ? null : _forward,
              label: Text(s.sendToN(_selectedDeviceIds.length)),
              icon: const Icon(Icons.send),
            )
          : null,
    );
  }

  Widget _buildUserTile(ChatUser user, BuildContext context, AppStrings s) {
    final isSelected = _selectedDeviceIds.contains(user.deviceId);
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _toggleSelection(user.deviceId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? colorScheme.primaryContainer.withOpacity(0.3)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: user.displayIcon != null
                      ? NetworkImage(user.displayIcon!)
                      : null,
                  child: user.displayIcon == null
                      ? Text(
                          user.displayName.isNotEmpty
                              ? user.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 18),
                        )
                      : null,
                ),
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.primary.withOpacity(0.7),
                      ),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    user.connected ? s.online : s.offline,
                    style: TextStyle(
                      fontSize: 13,
                      color: user.connected
                          ? Colors.green
                          : colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleSelection(user.deviceId),
            ),
          ],
        ),
      ),
    );
  }
}
