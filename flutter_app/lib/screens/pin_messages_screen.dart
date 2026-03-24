import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../core/socket_client.dart';
import '../models/remote_message.dart';
import '../providers/messages_provider.dart';
import 'photo_view_screen.dart';
import 'video_player_screen.dart';

class PinMessagesScreen extends ConsumerWidget {
  final String roomId;

  const PinMessagesScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(messagesProvider(roomId));
    final pinned = messages.where((m) => m.isPin == 1).toList()
      ..sort((a, b) {
        final ta = a.pinTime ?? '';
        final tb = b.pinTime ?? '';
        return tb.compareTo(ta); // newest pin first
      });

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pinned.isEmpty
              ? 'Pinned Messages'
              : 'Pinned Messages (${pinned.length})',
        ),
      ),
      body: pinned.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.push_pin_outlined,
                      size: 64, color: colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('No pinned messages'),
                  const SizedBox(height: 8),
                  Text(
                    'Long-press a message and tap Pin\nto add it here',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: pinned.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) =>
                  _buildPinnedCard(context, ref, pinned[i], colorScheme),
            ),
    );
  }

  Widget _buildPinnedCard(
    BuildContext context,
    WidgetRef ref,
    RemoteMessage msg,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.orange.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                const Icon(Icons.push_pin, size: 16, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                  'Pinned',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (msg.pinTime != null)
                  Text(
                    _formatDateTime(msg.pinTime!),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.outline,
                    ),
                  ),
                const SizedBox(width: 8),
                // Unpin button
                InkWell(
                  onTap: () => _unpinMessage(context, ref, msg),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.push_pin_outlined,
                      size: 18,
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            // Message content
            _buildContent(context, msg, colorScheme),
            // Timestamp
            const SizedBox(height: 6),
            Text(
              msg.createdAt != null ? _formatDateTime(msg.createdAt!) : '',
              style: TextStyle(fontSize: 11, color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, RemoteMessage msg, ColorScheme colorScheme) {
    switch (msg.typeMessage) {
      case AppConstants.typeImage:
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PhotoViewScreen(imageUrl: msg.messageContent ?? ''),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              msg.messageContent ?? '',
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 48),
            ),
          ),
        );

      case AppConstants.typeVideo:
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  VideoPlayerScreen(videoUrl: msg.messageContent ?? ''),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const Icon(Icons.play_circle_filled,
                  size: 48, color: Colors.white),
              const Positioned(
                bottom: 8,
                left: 8,
                child: Text('Video',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        );

      case AppConstants.typeFile:
        return Row(
          children: [
            Icon(Icons.insert_drive_file,
                size: 36, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg.messageContent?.split('/').last ?? 'File',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        );

      default:
        return Text(
          msg.messageContent ?? '',
          style: const TextStyle(fontSize: 15),
        );
    }
  }

  void _unpinMessage(
      BuildContext context, WidgetRef ref, RemoteMessage msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unpin message'),
        content: const Text('Remove this message from pinned?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              SocketClient.instance.emit(AppConstants.pvPinMessage, {
                'message_id': msg.messageId,
                'room_id': roomId,
                'is_pin': 0,
              });
              ref
                  .read(messagesProvider(roomId).notifier)
                  .pinMessage(msg.messageId!, false);
            },
            child: const Text('Unpin'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('MMM d, HH:mm').format(dt.toLocal());
    } catch (_) {
      return raw;
    }
  }
}
