import 'dart:io';
import 'dart:async'; // Add dart:async for StreamSubscription

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/group_apis.dart';
import '../helper/dialogs.dart';
import '../models/group.dart';
import '../models/group_message.dart';
import '../models/message.dart'; // Import to access Type enum
import '../utils/constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/profile_image.dart';
import '../widgets/search_bar.dart';
import 'group_chat_screen.dart';
import 'select_contacts_screen.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen>
    with AutomaticKeepAliveClientMixin {
  // Add search controller
  final TextEditingController _searchController = TextEditingController();

  // Groups list
  List<Group> _groups = [];
  List<Group> _filteredGroups = [];
  List<Group> _publicGroups = [];
  bool _isLoading = true;
  bool _isSearchingPublic = false;

  // Create group states
  bool _isCreatingGroup = false;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupDescController = TextEditingController();
  File? _groupImageFile;
  List<String> _selectedMemberIds = [];
  bool _isPublicGroup = false;

  // Stream subscriptions
  StreamSubscription? _groupsSubscription;
  // Store all subscriptions for cleanup
  final List<StreamSubscription> _subscriptions = [];

  @override
  bool get wantKeepAlive => true; // Keep the state alive when switching tabs

  @override
  void initState() {
    super.initState();
    _loadGroups();

    // Add listener to search controller to detect '@' symbol
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text == '@' && !_isSearchingPublic) {
        // When user types just '@', show all public groups
        _searchPublicGroups('');
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This ensures we're properly keeping state when the tab is reactivated
    // but doesn't reload the data unnecessarily
  }

  @override
  void dispose() {
    // Dispose of any resources, controllers, or subscriptions
    _searchController.dispose();
    _groupNameController.dispose();
    _groupDescController.dispose();

    // Cancel all subscriptions
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }

    super.dispose();
  }

  // Load groups
  void _loadGroups() {
    setState(() => _isLoading = true);

    // Cancel any existing subscription before creating a new one
    _groupsSubscription?.cancel();

    final subscription = GroupAPIs.getAllGroups().listen((groups) {
      if (!mounted) return;

      // Setup group update listeners for each group
      for (var group in groups) {
        _setupGroupUpdateListener(group);
      }

      setState(() {
        _groups = groups;
        _filteredGroups = groups;
        _isLoading = false;
      });
    });

    _subscriptions.add(subscription);
  }

  // Setup listener for real-time group updates
  void _setupGroupUpdateListener(Group group) {
    // Listen for group document updates (name, image, etc.)
    final groupUpdateSubscription =
        GroupAPIs.getGroupUpdates(group.id).listen((snapshot) {
      if (!mounted || !snapshot.exists) return;

      final updatedGroup = Group.fromJson(snapshot.data()!);

      // Update the group in our lists
      _updateGroupInLists(updatedGroup);
    });

    // Listen for last message updates
    final lastMessageSubscription =
        GroupAPIs.getGroupLastMessage(group.id).listen((msgSnapshot) {
      if (!mounted) return;

      if (msgSnapshot.docs.isNotEmpty) {
        final lastMessage =
            GroupMessage.fromJson(msgSnapshot.docs.first.data());

        // Find the group and update its last message
        final updatedGroup = _findGroupById(group.id)?.copyWith(
          lastMessage: _formatLastMessage(lastMessage),
          lastMessageTime: lastMessage.sent,
        );

        if (updatedGroup != null) {
          _updateGroupInLists(updatedGroup);
        }
      }
    });

    _subscriptions.add(groupUpdateSubscription);
    _subscriptions.add(lastMessageSubscription);
  }

  // Helper to format last message preview
  String _formatLastMessage(GroupMessage message) {
    final senderName = message.senderName;
    String content = '';

    switch (message.type) {
      case Type.text:
        content = message.msg;
        break;
      case Type.image:
        content = '📷 Photo';
        break;
      case Type.file:
        content = '📁 File';
        break;
      case Type.audio:
        content = '🎵 Voice message';
        break;
      case Type.video:
        content = '📹 Video';
        break;
      
    }

    return '$senderName: $content';
  }

  // Find group by ID
  Group? _findGroupById(String groupId) {
    try {
      return _groups.firstWhere((g) => g.id == groupId);
    } catch (e) {
      return null;
    }
  }

  // Update group in lists and refresh UI
  void _updateGroupInLists(Group updatedGroup) {
    setState(() {
      // Update in main groups list
      final index = _groups.indexWhere((g) => g.id == updatedGroup.id);
      if (index != -1) {
        _groups[index] = updatedGroup;
        // Sort groups by last message time
        _groups.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      }

      // Update in filtered groups if present
      final filteredIndex =
          _filteredGroups.indexWhere((g) => g.id == updatedGroup.id);
      if (filteredIndex != -1) {
        _filteredGroups[filteredIndex] = updatedGroup;
        // Sort filtered groups by last message time
        _filteredGroups
            .sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      }
    });
  }

  // Add search handler method
  void _handleSearch(String searchText) {
    if (searchText.trim().isEmpty) {
      setState(() {
        _filteredGroups = _groups;
        _isSearchingPublic = false;
      });
      return;
    }

    // If search text starts with '@', search for public groups
    if (searchText.startsWith('@')) {
      _searchPublicGroups(searchText.substring(1));
      return;
    }

    // Otherwise, search user's groups
    final query = searchText.toLowerCase();
    setState(() {
      _isSearchingPublic = false;
      _filteredGroups = _groups.where((group) {
        return group.name.toLowerCase().contains(query) ||
            group.description.toLowerCase().contains(query);
      }).toList();
    });
  }

  // Search for public groups
  void _searchPublicGroups(String searchText) async {
    setState(() {
      _isLoading = true;
      _isSearchingPublic = true;
    });

    try {
      // Get all public groups from the server
      final publicGroups = await GroupAPIs.getPublicGroups();

      // Filter by search text
      final query = searchText.toLowerCase().trim();
      final filteredPublicGroups = query.isEmpty
          ? publicGroups
          : publicGroups.where((group) {
              return group.name.toLowerCase().contains(query) ||
                  group.description.toLowerCase().contains(query);
            }).toList();

      if (mounted) {
        setState(() {
          _publicGroups = filteredPublicGroups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        Dialogs.showSnackbar(
            context, 'Failed to search public groups: ${e.toString()}');
      }
    }
  }

  // Create new group
  Future<void> _createGroup() async {
    // Validate inputs
    final name = _groupNameController.text.trim();
    final description = _groupDescController.text.trim();

    if (name.isEmpty) {
      Dialogs.showSnackbar(context, 'Please enter a group name');
      return;
    }

    setState(() => _isCreatingGroup = true);

    try {
      // Create group
      final group = await GroupAPIs.createGroup(
        name: name,
        description: description,
        imageFile: _groupImageFile,
        members: _selectedMemberIds, // Pass selected members
        isPublic: _isPublicGroup,
      );

      if (group != null && mounted) {
        // Clear inputs
        _groupNameController.clear();
        _groupDescController.clear();
        _groupImageFile = null;
        _selectedMemberIds = [];

        // Navigate to group chat
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatScreen(group: group),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Dialogs.showSnackbar(context,
            'Failed to create group: ${e.toString().contains('Exception:') ? e.toString().split('Exception:')[1].trim() : 'Please try again'}');
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingGroup = false);
      }
    }
  }

  // Pick group image
  Future<void> _pickGroupImage() async {
    final ImagePicker picker = ImagePicker();

    // Pick an image
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image != null) {
      setState(() => _groupImageFile = File(image.path));
    }
  }

  // Select members for the group
  Future<void> _selectMembers(StateSetter setState) async {
    try {
      // Navigate to select contacts screen and wait for result
      final selectedIds = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (_) => SelectContactsScreen(
            existingMembers: _selectedMemberIds,
            title: 'Select Members',
          ),
        ),
      );

      // If contacts were selected, update the state
      if (selectedIds != null && selectedIds.isNotEmpty) {
        setState(() {
          _selectedMemberIds = selectedIds;
        });
      }
    } catch (e) {
      if (mounted) {
        Dialogs.showSnackbar(context, 'Failed to select members');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(
        context); // Important: call super.build for AutomaticKeepAliveClientMixin

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppConstants.groupGradient,
            transform:
                GradientRotation(DateTime.now().millisecondsSinceEpoch / 5000),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              CustomAppBar(
                title: 'Groups',
                onProfileUpdated: () {
                  if (mounted) setState(() {});
                },
                isTransparent: true,
                heroTag: AppConstants.groupHeroTag,
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                    child: _buildBody(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Add search bar at the top
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.searchBarPadding,
            AppConstants.searchBarPadding,
            AppConstants.searchBarPadding,
            8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomSearchBar(
                controller: _searchController,
                hintText: _isSearchingPublic
                    ? 'Search public groups...'
                    : 'Use @ to find public groups...',
                onChanged: _handleSearch,
                borderRadius: AppConstants.borderRadius,
              ),
              if (_isSearchingPublic)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.public,
                        size: 16,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Searching public groups',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isSearchingPublic = false;
                            _searchController.clear();
                            _filteredGroups = _groups;
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Back to my groups'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Groups list or loading indicator
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _groups.isEmpty && !_isSearchingPublic
                  ? _buildEmptyState()
                  : _buildGroupsList(),
        ),
      ],
    );
  }

  // Build empty state when no groups
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Icon(
                  Icons.groups_rounded,
                  size: 100,
                  color: Theme.of(context).primaryColor.withOpacity(0.7),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: const Text(
                    'No Groups Yet',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Create a new group to start chatting with multiple people at once.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Build groups list
  Widget _buildGroupsList() {
    // If searching for public groups
    if (_isSearchingPublic) {
      return _publicGroups.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.public_off,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No public groups found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _searchController.text.length > 1
                        ? 'Try a different search term'
                        : 'Create a public group to get started',
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_searchController.text.length > 1)
                    ElevatedButton.icon(
                      onPressed: () => _searchPublicGroups(''),
                      icon: const Icon(Icons.public),
                      label: const Text('Show all public groups'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Debug button
                  OutlinedButton(
                    onPressed: () {
                      // Force refresh public groups
                      _searchPublicGroups('');
                      Dialogs.showSnackbar(
                          context, 'Refreshing public groups...');
                    },
                    child: const Text('Refresh Public Groups'),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Public Groups (${_publicGroups.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      // Refresh public groups
                      _searchPublicGroups(_searchController.text.startsWith('@')
                          ? _searchController.text.substring(1)
                          : '');
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.only(top: 5),
                      itemCount: _publicGroups.length,
                      itemBuilder: (context, index) {
                        final group = _publicGroups[index];
                        return _buildPublicGroupItem(group);
                      },
                    ),
                  ),
                ),
              ],
            );
    }

    // Regular group search
    return _filteredGroups.isEmpty
        ? Center(
            child: Text(
              'No groups found matching "${_searchController.text}"',
              style: TextStyle(color: Colors.grey[600]),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.only(top: 5),
            itemCount: _filteredGroups.length,
            itemBuilder: (context, index) {
              final group = _filteredGroups[index];
              return _buildGroupItem(group);
            },
          );
  }

  // Build single group item
  Widget _buildGroupItem(Group group) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      // elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupChatScreen(group: group),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Group image
              ProfileImage(
                url: group.image,
                size: 55,
              ),

              const SizedBox(width: 12),

              // Group info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group name
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Last message or member count
                    Text(
                      group.lastMessage.isNotEmpty
                          ? group.lastMessage
                          : '${group.members.length} members',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Time or date
              if (group.lastMessageTime.isNotEmpty)
                Text(
                  _getFormattedTime(group.lastMessageTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, double value, child) {
        return Transform.scale(
          scale: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Opacity(
              opacity: value,
              child: FloatingActionButton(
                backgroundColor: Theme.of(context).primaryColor,
                heroTag: AppConstants.groupFabHeroTag,
                onPressed: () => _showCreateGroupDialog(),
                child: const Icon(Icons.group_add, color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
  }

  // Show create group dialog
  void _showCreateGroupDialog() {
    // Reset controllers and state
    _groupNameController.clear();
    _groupDescController.clear();
    _groupImageFile = null;
    _selectedMemberIds = [];
    _isPublicGroup = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(25),
                topRight: Radius.circular(25),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  height: 4,
                  width: 50,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Title
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Create New Group',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        // Group image picker
                        GestureDetector(
                          onTap: () async {
                            await _pickGroupImage();
                            setState(() {}); // Update dialog state
                          },
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              shape: BoxShape.circle,
                              image: _groupImageFile != null
                                  ? DecorationImage(
                                      image: FileImage(_groupImageFile!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: _groupImageFile == null
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_a_photo,
                                        size: 40,
                                        color: Theme.of(context)
                                            .primaryColor
                                            .withOpacity(0.7),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Add Photo',
                                        style: TextStyle(
                                          color: Theme.of(context).primaryColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Group name field
                        TextField(
                          controller: _groupNameController,
                          decoration: InputDecoration(
                            labelText: 'Group Name',
                            hintText: 'Enter a name for your group',
                            prefixIcon: const Icon(Icons.group),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor),
                            ),
                          ),
                          maxLength: 25,
                        ),

                        const SizedBox(height: 16),

                        // Group description field
                        TextField(
                          controller: _groupDescController,
                          decoration: InputDecoration(
                            labelText: 'Group Description (Optional)',
                            hintText: 'What\'s this group about?',
                            prefixIcon: const Icon(Icons.description),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor),
                            ),
                          ),
                          maxLength: 100,
                          maxLines: 3,
                        ),

                        const SizedBox(height: 16),

                        // Public/Private toggle
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                _isPublicGroup ? Icons.public : Icons.lock,
                                color: _isPublicGroup
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isPublicGroup
                                          ? 'Public Group'
                                          : 'Private Group',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      _isPublicGroup
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
                              Switch(
                                value: _isPublicGroup,
                                onChanged: (value) {
                                  setState(() {
                                    _isPublicGroup = value;
                                  });
                                },
                                activeColor: Theme.of(context).primaryColor,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Select members button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: () => _selectMembers(setState),
                            icon: const Icon(Icons.person_add),
                            label: Text(
                              _selectedMemberIds.isEmpty
                                  ? 'Select Members'
                                  : 'Members Selected (${_selectedMemberIds.length})',
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                  color: Theme.of(context).primaryColor),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Create button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isCreatingGroup
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    _createGroup();
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: _isCreatingGroup
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Create Group',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Cancel button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Build public group item with join button
  Widget _buildPublicGroupItem(Group group) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Group image
            ProfileImage(
              url: group.image,
              size: 55,
            ),

            const SizedBox(width: 12),

            // Group info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Group name
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.public,
                        size: 16,
                        color: Colors.blue,
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Description
                  Text(
                    group.description.isEmpty
                        ? 'No description'
                        : group.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 8),

                  // Member count and join button
                  LayoutBuilder(builder: (context, constraints) {
                    return constraints.maxWidth > 200
                        ? _buildWideLayout(group)
                        : _buildCompactLayout(group);
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Wide layout for larger screens
  Widget _buildWideLayout(Group group) {
    return Row(
      children: [
        Text(
          '${group.members.length} members',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: () => _joinGroup(group),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            minimumSize: const Size(80, 36),
          ),
          child: const Text('Join'),
        ),
      ],
    );
  }

  // Compact layout for smaller screens
  Widget _buildCompactLayout(Group group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${group.members.length} members',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _joinGroup(group),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: const Size(80, 36),
            ),
            child: const Text('Join'),
          ),
        ),
      ],
    );
  }

  // Helper method to format time
  String _getFormattedTime(String timestamp) {
    final now = DateTime.now();
    final messageTime =
        DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));

    // If same day, show time
    if (now.year == messageTime.year &&
        now.month == messageTime.month &&
        now.day == messageTime.day) {
      return '${messageTime.hour}:${messageTime.minute.toString().padLeft(2, '0')}';
    }

    // If within a week, show day name
    final difference = now.difference(messageTime).inDays;
    if (difference < 7) {
      final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[messageTime.weekday - 1];
    }

    // Otherwise show date
    return '${messageTime.day}/${messageTime.month}';
  }

  // Check if user is already a member of a group
  bool _isAlreadyMember(Group group) {
    return _groups.any((g) => g.id == group.id);
  }

  // Join a public group
  Future<void> _joinGroup(Group group) async {
    // Check if user is already a member
    if (_isAlreadyMember(group)) {
      Dialogs.showSnackbar(context, 'You are already a member of this group');

      // Navigate to the group chat
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
              group: _groups.firstWhere((g) => g.id == group.id)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Join the group
      await GroupAPIs.joinPublicGroup(group);

      // Remove the group from the public groups list
      setState(() {
        _publicGroups.removeWhere((g) => g.id == group.id);
      });

      // Show success message
      if (mounted) {
        Dialogs.showSnackbar(context, 'Successfully joined ${group.name}');

        // Navigate to the group chat
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatScreen(group: group),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Dialogs.showSnackbar(context,
            'Failed to join group: ${e.toString().contains('Exception:') ? e.toString().split('Exception:')[1].trim() : 'Please try again'}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
