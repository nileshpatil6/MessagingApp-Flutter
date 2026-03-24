import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/socket_client.dart';
import '../models/chat_user.dart';
import '../models/group_data.dart';
import '../providers/groups_provider.dart';
import '../providers/users_provider.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() =>
      _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _groupNameController = TextEditingController();
  final _iconController = TextEditingController();

  int _step = 1; // 1 = select members, 2 = group details
  final Set<String> _selectedDeviceIds = {};

  @override
  void dispose() {
    _groupNameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  // ── Step 1: member selection ───────────────────────────────────────────────

  void _goToStep2() {
    if (_selectedDeviceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one member')),
      );
      return;
    }
    setState(() => _step = 2);
  }

  // ── Step 2: create group ───────────────────────────────────────────────────

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name is required')),
      );
      return;
    }

    final myId = ref.read(usersProvider).myDeviceId;
    final groupId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final memberIds = [myId, ..._selectedDeviceIds];

    final group = GroupData(
      groupId: groupId,
      groupName: name,
      adminId: myId,
      memberIds: memberIds,
      iconUrl: _iconController.text.trim().isEmpty
          ? null
          : _iconController.text.trim(),
      createdAt: now,
    );

    // Save locally
    await ref.read(groupsProvider.notifier).addGroup(group);

    // Send invite to each selected member.
    // Format: [GRP_INV:groupId:name:adminId:member1,member2,...]
    final memberList = memberIds.join(',');
    final inviteContent =
        '${AppConstants.grpInvPrefix}$groupId:$name:$myId:$memberList]';
    for (final memberId in _selectedDeviceIds) {
      SocketClient.instance.emit(AppConstants.pvSendMessage, {
        'room_id': groupId,
        'message_content': inviteContent,
        'type_message': AppConstants.typeText,
        'sender_device_id': myId,
        'receiver_device_id': memberId,
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Group "$name" created')),
      );
      Navigator.pop(context);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _step == 1 ? _buildStep1() : _buildStep2();
  }

  Widget _buildStep1() {
    final users = ref.watch(usersProvider).users;
    final myId = ref.read(usersProvider).myDeviceId;
    final filteredUsers =
        users.where((u) => u.deviceId != myId).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Group'),
            Text(
              'Select members',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _goToStep2,
            child: const Text('Next',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: filteredUsers.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64),
                  SizedBox(height: 16),
                  Text('No users online'),
                ],
              ),
            )
          : Column(
              children: [
                if (_selectedDeviceIds.isNotEmpty)
                  _buildSelectedChips(filteredUsers),
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredUsers.length,
                    itemBuilder: (_, i) =>
                        _buildUserCheckTile(filteredUsers[i]),
                  ),
                ),
              ],
            ),
      floatingActionButton: _selectedDeviceIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _goToStep2,
              label: Text('Next (${_selectedDeviceIds.length})'),
              icon: const Icon(Icons.arrow_forward),
            )
          : null,
    );
  }

  Widget _buildSelectedChips(List<ChatUser> allUsers) {
    final selected = allUsers
        .where((u) => _selectedDeviceIds.contains(u.deviceId))
        .toList();

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: selected.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final user = selected[i];
          return Column(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: user.displayIcon != null
                        ? NetworkImage(user.displayIcon!)
                        : null,
                    child: user.displayIcon == null
                        ? Text(user.displayName.isNotEmpty
                            ? user.displayName[0].toUpperCase()
                            : '?')
                        : null,
                  ),
                  Positioned(
                    right: -2,
                    top: -2,
                    child: GestureDetector(
                      onTap: () => setState(
                          () => _selectedDeviceIds.remove(user.deviceId)),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 10, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUserCheckTile(ChatUser user) {
    final isSelected = _selectedDeviceIds.contains(user.deviceId);

    return CheckboxListTile(
      value: isSelected,
      onChanged: (checked) {
        setState(() {
          if (checked == true) {
            _selectedDeviceIds.add(user.deviceId);
          } else {
            _selectedDeviceIds.remove(user.deviceId);
          }
        });
      },
      secondary: CircleAvatar(
        backgroundImage: user.displayIcon != null
            ? NetworkImage(user.displayIcon!)
            : null,
        child: user.displayIcon == null
            ? Text(user.displayName.isNotEmpty
                ? user.displayName[0].toUpperCase()
                : '?')
            : null,
      ),
      title: Text(user.displayName),
      subtitle: Text(user.connected ? 'Online' : 'Offline',
          style: TextStyle(
              color: user.connected ? Colors.green : Colors.grey)),
    );
  }

  Widget _buildStep2() {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _step = 1),
        ),
        title: const Text('Group Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundImage:
                    _iconController.text.trim().isNotEmpty
                        ? NetworkImage(_iconController.text.trim())
                        : null,
                child: _iconController.text.trim().isEmpty
                    ? const Icon(Icons.group, size: 48)
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _groupNameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Group name *',
                hintText: 'Enter group name',
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.group),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _iconController,
              decoration: InputDecoration(
                labelText: 'Icon URL (optional)',
                hintText: 'https://…',
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.image),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            // Member count summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedDeviceIds.length + 1} members will be added',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _createGroup,
              icon: const Icon(Icons.check),
              label: const Text('Create Group'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
