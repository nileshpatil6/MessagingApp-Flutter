import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/socket_client.dart';
import '../l10n/app_strings.dart';
import '../models/chat_user.dart';
import '../models/group_data.dart';
import '../providers/groups_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/users_provider.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() =>
      _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  AppStrings get _s => AppStrings(ref.read(localeProvider));

  final _groupNameController = TextEditingController();
  String? _iconUrl;
  bool _isUploadingIcon = false;

  int _step = 1; // 1 = select members, 2 = group details
  final Set<String> _selectedDeviceIds = {};

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _pickGroupIcon() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (xFile == null) return;
    setState(() => _isUploadingIcon = true);
    try {
      final dio = Dio();
      final formData = FormData.fromMap({
        'files': await MultipartFile.fromFile(
          xFile.path,
          filename: xFile.path.split(Platform.pathSeparator).last,
        ),
      });
      final response = await dio.post(
        AppConstants.uploadFileChatUrl,
        data: formData,
      );
      if (response.statusCode == 200) {
        final data = response.data;
        String? iconUrl;
        if (data is Map) {
          final files = data['files'];
          if (files is List && files.isNotEmpty && files[0] is Map) {
            final relUrl = (files[0] as Map)['url']?.toString();
            if (relUrl != null && relUrl.isNotEmpty) {
              iconUrl = '${AppConstants.serverUrl}$relUrl';
            }
          }
        }
        if (iconUrl != null) {
          setState(() {
            _iconUrl = iconUrl;
            _isUploadingIcon = false;
          });
          return;
        }
      }
    } catch (_) {}
    setState(() => _isUploadingIcon = false);
  }

  // ── Step 1: member selection ───────────────────────────────────────────────

  void _goToStep2() {
    if (_selectedDeviceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.selectAtLeastOneMember)),
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
        SnackBar(content: Text(_s.groupNameRequired)),
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
      iconUrl: _iconUrl,
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
        SnackBar(content: Text(_s.groupCreated(name))),
      );
      Navigator.pop(context);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final s = _s;
    return _step == 1 ? _buildStep1(s) : _buildStep2(s);
  }

  Widget _buildStep1(AppStrings s) {
    final users = ref.watch(usersProvider).users;
    final myId = ref.read(usersProvider).myDeviceId;
    final filteredUsers =
        users.where((u) => u.deviceId != myId).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.newGroup),
            Text(
              s.selectMembers,
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
            child: Text(s.next,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: filteredUsers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_outline, size: 64),
                  const SizedBox(height: 16),
                  Text(s.noUsersOnlineGroup),
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
                        _buildUserCheckTile(filteredUsers[i], s),
                  ),
                ),
              ],
            ),
      floatingActionButton: _selectedDeviceIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _goToStep2,
              label: Text(s.nextWithCount(_selectedDeviceIds.length)),
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

  Widget _buildUserCheckTile(ChatUser user, AppStrings s) {
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
      subtitle: Text(user.connected ? s.online : s.offline,
          style: TextStyle(
              color: user.connected ? Colors.green : Colors.grey)),
    );
  }

  Widget _buildStep2(AppStrings s) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _step = 1),
        ),
        title: Text(s.groupDetails),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickGroupIcon,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: _iconUrl != null
                          ? NetworkImage(_iconUrl!)
                          : null,
                      child: _isUploadingIcon
                          ? const CircularProgressIndicator()
                          : _iconUrl == null
                              ? const Icon(Icons.group, size: 48)
                              : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _groupNameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: s.groupNameLabel,
                hintText: s.groupNameHint,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.group),
              ),
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
                    s.membersWillBeAdded(_selectedDeviceIds.length + 1),
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _createGroup,
              icon: const Icon(Icons.check),
              label: Text(s.createGroupAction),
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
