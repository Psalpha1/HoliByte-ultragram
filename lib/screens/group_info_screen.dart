import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/apis.dart';
import '../api/group_apis.dart';
import '../helper/dialogs.dart';
import '../main.dart';
import '../models/chat_user.dart';
import '../models/group.dart';
import '../widgets/profile_image.dart';
import '../screens/select_contacts_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  final Group group;

  const GroupInfoScreen({super.key, required this.group});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  List<ChatUser> _members = [];
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _checkAdminStatus();
  }

  // Check if current user is an admin
  void _checkAdminStatus() {
    _isAdmin = widget.group.admins.contains(APIs.user.uid);
  }

  // Load group members
  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    
    try {
      final membersSnapshot = await APIs.firestore
          .collection('users')
          .where('id', whereIn: widget.group.members)
          .get();
      
      _members = membersSnapshot.docs
          .map((doc) => ChatUser.fromJson(doc.data()))
          .toList();
      
      // Sort members: admins first, then alphabetically by name
      _members.sort((a, b) {
        final aIsAdmin = widget.group.admins.contains(a.id);
        final bIsAdmin = widget.group.admins.contains(b.id);
        
        if (aIsAdmin && !bIsAdmin) return -1;
        if (!aIsAdmin && bIsAdmin) return 1;
        
        return a.name.compareTo(b.name);
      });
    } catch (e) {
      if (mounted) {
        Dialogs.showSnackbar(context, 'Failed to load members');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Change group image
  Future<void> _changeGroupImage() async {
    final ImagePicker picker = ImagePicker();
    
    // Pick an image
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    
    if (image != null) {
      setState(() => _isLoading = true);
      
      try {
        // Update group image
        await GroupAPIs.updateGroupInfo(
          groupId: widget.group.id,
          imageFile: File(image.path),
        );
        
        if (mounted) {
          Dialogs.showSnackbar(context, 'Group image updated successfully');
        }
      } catch (e) {
        if (mounted) {
          Dialogs.showSnackbar(context, 'Failed to update group image');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  // Edit group name
  void _editGroupName() {
    final nameController = TextEditingController(text: widget.group.name);
    
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: 'Enter group name',
            border: OutlineInputBorder(),
          ),
          maxLength: 25,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              
              if (newName.isEmpty) {
                Dialogs.showSnackbar(context, 'Group name cannot be empty');
                return;
              }
              
              Navigator.pop(context);
              setState(() => _isLoading = true);
              
              try {
                // Update group name
                await GroupAPIs.updateGroupInfo(
                  groupId: widget.group.id,
                  name: newName,
                );
                
                if (mounted) {
                  Dialogs.showSnackbar(context, 'Group name updated successfully');
                }
              } catch (e) {
                if (mounted) {
                  Dialogs.showSnackbar(context, 'Failed to update group name');
                }
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  // Edit group description
  void _editGroupDescription() {
    final descriptionController = TextEditingController(text: widget.group.description);
    
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Group Description'),
        content: TextField(
          controller: descriptionController,
          decoration: const InputDecoration(
            hintText: 'Enter group description',
            border: OutlineInputBorder(),
          ),
          maxLength: 100,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newDescription = descriptionController.text.trim();
              
              Navigator.pop(context);
              setState(() => _isLoading = true);
              
              try {
                // Update group description
                await GroupAPIs.updateGroupInfo(
                  groupId: widget.group.id,
                  description: newDescription,
                );
                
                if (mounted) {
                  Dialogs.showSnackbar(context, 'Group description updated successfully');
                }
              } catch (e) {
                if (mounted) {
                  Dialogs.showSnackbar(context, 'Failed to update group description');
                }
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  // Add members to group
  void _addMembers() async {
    try {
      // Navigate to select contacts screen and wait for result
      final selectedIds = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (_) => SelectContactsScreen(
            existingMembers: widget.group.members,
            title: 'Add Members',
          ),
        ),
      );
      
      // If no contacts were selected, return
      if (selectedIds == null || selectedIds.isEmpty) return;
      
      // Show loading indicator
      setState(() => _isLoading = true);
      
      // Add members to group
      await GroupAPIs.addGroupMembers(widget.group.id, selectedIds);
      
      // Refresh members list
      await _loadMembers();
      
      if (mounted) {
        Dialogs.showSnackbar(
          context, 
          'Added ${selectedIds.length} ${selectedIds.length == 1 ? 'member' : 'members'} to the group'
        );
      }
    } catch (e) {
      if (mounted) {
        Dialogs.showSnackbar(context, 'Failed to add members to the group');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Make user an admin
  void _makeAdmin(ChatUser user) async {
    try {
      setState(() => _isLoading = true);
      
      // Make user an admin
      await GroupAPIs.makeGroupAdmin(widget.group.id, user.id);
      
      if (mounted) {
        Dialogs.showSnackbar(context, '${user.name} is now an admin');
      }
    } catch (e) {
      if (mounted) {
        Dialogs.showSnackbar(context, 'Failed to make user an admin');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Remove user from group
  void _removeMember(ChatUser user) async {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Are you sure you want to remove ${user.name} from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              
              try {
                // Remove user from group
                await GroupAPIs.removeGroupMember(widget.group.id, user.id);
                
                // Refresh members list
                await _loadMembers();
                
                if (mounted) {
                  Dialogs.showSnackbar(context, '${user.name} removed from the group');
                }
              } catch (e) {
                if (mounted) {
                  Dialogs.showSnackbar(context, 'Failed to remove member');
                }
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // Leave group
  void _leaveGroup() async {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              
              try {
                // Leave group
                await GroupAPIs.leaveGroup(widget.group.id);
                
                // Close all screens and go back to home
                if (mounted) {
                  Navigator.pop(context); // Close group info screen
                  Navigator.pop(context); // Close group chat screen
                }
              } catch (e) {
                if (mounted) {
                  Dialogs.showSnackbar(context, 'Failed to leave group');
                  setState(() => _isLoading = false);
                }
              }
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  // Toggle public/private setting
  void _togglePublicPrivate() async {
    try {
      setState(() => _isLoading = true);
      
      // Toggle the current setting
      final newIsPublic = !widget.group.isPublic;
      
      // Update group info
      await GroupAPIs.updateGroupInfo(
        groupId: widget.group.id,
        isPublic: newIsPublic,
      );
      
      if (mounted) {
        Dialogs.showSnackbar(
          context, 
          'Group is now ${newIsPublic ? 'public' : 'private'}'
        );
      }
    } catch (e) {
      if (mounted) {
        Dialogs.showSnackbar(context, 'Failed to update group settings');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // Group image and name
                _buildGroupHeader(),
                
                const Divider(thickness: 1),
                
                // Group description
                _buildGroupDescription(),
                
                const Divider(thickness: 1),
                
                // Public/Private setting (only for admins)
                if (_isAdmin) _buildPublicPrivateToggle(),
                
                if (_isAdmin) const Divider(thickness: 1),
                
                // Members section
                _buildMembersSection(),
                
                const SizedBox(height: 20),
                
                // Leave group button
                _buildLeaveGroupButton(),
                
                const SizedBox(height: 50),
              ],
            ),
          ),
          
          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  // Build group header with image and name
  Widget _buildGroupHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Group image
          Stack(
            children: [
              // Profile image
              GestureDetector(
                onTap: _isAdmin ? _changeGroupImage : null,
                child: ProfileImage(
                  url: widget.group.image,
                  size: 100,
                ),
              ),
              
              // Edit icon (only for admins)
              if (_isAdmin)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Group name
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  widget.group.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              // Edit name button (only for admins)
              if (_isAdmin)
                IconButton(
                  onPressed: _editGroupName,
                  icon: const Icon(Icons.edit),
                  iconSize: 20,
                ),
            ],
          ),
          
          // Created info
          Text(
            'Created on ${_getFormattedDate(widget.group.createdAt)}',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Build group description section
  Widget _buildGroupDescription() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description header
          Row(
            children: [
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              // Edit description button (only for admins)
              if (_isAdmin)
                IconButton(
                  onPressed: _editGroupDescription,
                  icon: const Icon(Icons.edit),
                  iconSize: 20,
                ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Description text
          Text(
            widget.group.description.isEmpty
                ? 'No description'
                : widget.group.description,
            style: TextStyle(
              color: widget.group.description.isEmpty
                  ? Colors.grey
                  : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // Build public/private toggle
  Widget _buildPublicPrivateToggle() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Privacy Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _isAdmin ? _togglePublicPrivate : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    widget.group.isPublic ? Icons.public : Icons.lock,
                    color: widget.group.isPublic 
                        ? Theme.of(context).primaryColor 
                        : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.group.isPublic ? 'Public Group' : 'Private Group',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          widget.group.isPublic 
                              ? 'Anyone can find and join this group'
                              : 'Only people you invite can join',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isAdmin)
                    Switch(
                      value: widget.group.isPublic,
                      onChanged: (value) => _togglePublicPrivate(),
                      activeColor: Theme.of(context).primaryColor,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build members section
  Widget _buildMembersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Members header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Text(
                '${widget.group.members.length} Members',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const Spacer(),
              
              // Add members button (only for admins)
              if (_isAdmin)
                TextButton.icon(
                  onPressed: _addMembers,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
            ],
          ),
        ),
        
        // Members list
        if (_isLoading && _members.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              final isAdmin = widget.group.admins.contains(member.id);
              final isCurrentUser = member.id == APIs.user.uid;
              
              return ListTile(
                leading: ProfileImage(
                  url: member.image,
                  size: 40,
                ),
                title: Text(
                  '${member.name}${isCurrentUser ? ' (You)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: isAdmin
                    ? const Text(
                        'Admin',
                        style: TextStyle(color: Colors.blue),
                      )
                    : null,
                trailing: _isAdmin && !isCurrentUser
                    ? PopupMenuButton(
                        itemBuilder: (context) => [
                          if (!isAdmin)
                            PopupMenuItem(
                              value: 'make_admin',
                              child: const Text('Make Admin'),
                            ),
                          PopupMenuItem(
                            value: 'remove',
                            child: const Text('Remove'),
                          ),
                        ],
                        onSelected: (value) {
                          if (value == 'make_admin') {
                            _makeAdmin(member);
                          } else if (value == 'remove') {
                            _removeMember(member);
                          }
                        },
                      )
                    : null,
              );
            },
          ),
      ],
    );
  }

  // Build leave group button
  Widget _buildLeaveGroupButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ElevatedButton.icon(
        onPressed: _leaveGroup,
        icon: const Icon(Icons.exit_to_app, color: Colors.red),
        label: const Text(
          'Leave Group',
          style: TextStyle(color: Colors.red),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.red,
          elevation: 0,
          side: const BorderSide(color: Colors.red),
          minimumSize: Size(mq.width, 50),
        ),
      ),
    );
  }

  // Helper method to format date
  String _getFormattedDate(String timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    return '${date.day}/${date.month}/${date.year}';
  }
} 