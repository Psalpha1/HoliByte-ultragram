import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../api/apis.dart';
import '../helper/dialogs.dart';
import '../models/chat_user.dart';
import '../widgets/profile_image.dart';

// Constants for the screen
class SearchScreenConstants {
  static const int pageSize = 15;
  static const double appBarHeight = 80.0;
  static const double borderRadius = 30.0;
  static const double cardRadius = 15.0;
  static const Duration animationDuration = Duration(milliseconds: 300);
}

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ChatUser> _users = [];
  Set<String> _addedUserIds = {};
  
  DocumentSnapshot? _lastDoc;
  bool _isLoading = true;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _fetchAddedUsers();
    await _loadInitialUsers();
    _setupScrollListener();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent * 0.95) {
        _loadMoreUsers();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Fetch the list of users already added as friends
  Future<void> _fetchAddedUsers() async {
    try {
      log('Fetching already added users...');
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(APIs.auth.currentUser!.uid)
          .collection('my_users')
          .get();

      setState(() {
        _addedUserIds = snapshot.docs.map((doc) => doc.id).toSet();
      });

      log('Already added ${_addedUserIds.length} users');
    } catch (e) {
      log('Error fetching added users: $e');
    }
  }

  // Censor email address for privacy
  String _censorEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;

    final username = parts[0];
    final domain = parts[1];

    // Show first character followed by asterisks, then @ and domain
    if (username.length <= 1) return email;

    return '${username[0]}${'*' * (username.length - 1)}@$domain';
  }

  // Filter out already added users
  List<ChatUser> _filterAddedUsers(List<ChatUser> users) {
    return users.where((user) => !_addedUserIds.contains(user.id)).toList();
  }

  // Load initial batch of users
  Future<void> _loadInitialUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _lastDoc = null; // Reset pagination
    });

    try {
      log('Loading initial users...');

      // Get users from Firestore
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .orderBy('name')
              .limit(SearchScreenConstants.pageSize)
              .get();

      // Convert to ChatUser objects and filter out current user and already added users
      final users = snapshot.docs
          .map((doc) => ChatUser.fromJson(doc.data()))
          .where((user) => user.id != APIs.auth.currentUser!.uid)
          .toList();

      // Filter out already added users
      final filteredUsers = _filterAddedUsers(users);

      log('Loaded ${users.length} users, ${filteredUsers.length} after filtering');

      if (mounted) {
        setState(() {
          _users = filteredUsers;
          _isLoading = false;
          _hasMoreData = snapshot.docs.length >= SearchScreenConstants.pageSize;

          // Store last document for pagination
          if (snapshot.docs.isNotEmpty) {
            _lastDoc = snapshot.docs.last;
          }
        });
      }
    } catch (e) {
      log('Error loading users: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load users: ${e.toString()}';
        });
      }
    }
  }

  // Load more users when scrolling
  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore || !_hasMoreData || _lastDoc == null) return;

    setState(() => _isLoadingMore = true);

    try {
      log('Loading more users...');

      // Get next batch of users
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .orderBy('name')
              .startAfterDocument(_lastDoc!)
              .limit(SearchScreenConstants.pageSize)
              .get();

      // Convert to ChatUser objects and filter out current user
      final moreUsers = snapshot.docs
          .map((doc) => ChatUser.fromJson(doc.data()))
          .where((user) => user.id != APIs.auth.currentUser!.uid)
          .toList();

      // Filter out already added users
      final filteredMoreUsers = _filterAddedUsers(moreUsers);

      log('Loaded ${moreUsers.length} more users, ${filteredMoreUsers.length} after filtering');

      if (mounted) {
        setState(() {
          _users.addAll(filteredMoreUsers);
          _isLoadingMore = false;
          _hasMoreData = snapshot.docs.length >= SearchScreenConstants.pageSize;

          // Store last document for next pagination
          if (snapshot.docs.isNotEmpty) {
            _lastDoc = snapshot.docs.last;
          }
        });
      }
    } catch (e) {
      log('Error loading more users: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  // Search users by name or email
  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      _loadInitialUsers();
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      log('Searching for users with query: $query');
      final searchResults = await APIs.searchUsers(query);

      // Filter out already added users
      final filteredResults = _filterAddedUsers(searchResults);

      log('Found ${searchResults.length} users matching query, ${filteredResults.length} after filtering');

      if (mounted) {
        setState(() {
          _users = filteredResults;
          _isLoading = false;
          _hasMoreData = false; // No pagination for search results
        });
      }
    } catch (e) {
      log('Error searching users: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to search users: ${e.toString()}';
        });
      }
    }
  }

  // Add a user as friend
  Future<void> _addAsFriend(ChatUser user) async {
    try {
      bool added = await APIs.addChatUser(user.email);

      if (!mounted) return;

      if (added) {
        // Add to the set of added users
        setState(() {
          _addedUserIds.add(user.id);
          // Remove user from the current list
          _users.removeWhere((u) => u.id == user.id);
        });

        Dialogs.showSnackbar(context, '${user.name} added as a friend!');
      } else {
        Dialogs.showSnackbar(
            context, 'Failed to add ${user.name} as a friend.');
      }
    } catch (e) {
      log('Error adding friend: $e');
      if (mounted) {
        Dialogs.showSnackbar(context, 'An error occurred. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: _buildGradientDecoration(),
          child: SafeArea(
            child: Column(
              children: [
                _buildAppBar(theme),
                Expanded(
                  child: _buildContentContainer(theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildGradientDecoration() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.blue.shade400,
          Colors.purple.shade300,
          Colors.pink.shade200,
        ],
        transform: GradientRotation(DateTime.now().millisecondsSinceEpoch / 5000),
      ),
    );
  }

  Widget _buildContentContainer(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SearchScreenConstants.borderRadius),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SearchScreenConstants.borderRadius),
        ),
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme) {
    return Container(
      height: SearchScreenConstants.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildBackButton(),
          Expanded(child: _buildSearchField(theme)),
          _buildClearButton(),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: () => Navigator.pop(context),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search users...',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        prefixIcon: const Icon(CupertinoIcons.search, color: Colors.white),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      textInputAction: TextInputAction.search,
      onChanged: _handleSearchChange,
      onSubmitted: _searchUsers,
    );
  }

  void _handleSearchChange(String value) {
    if (value.trim().isEmpty) {
      _loadInitialUsers();
    }
  }

  Widget _buildClearButton() {
    return IconButton(
      icon: const Icon(CupertinoIcons.clear_circled_solid, color: Colors.white),
      onPressed: () {
        _searchController.clear();
        _loadInitialUsers();
      },
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading && _users.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading users...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadInitialUsers,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_search, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchController.text.trim().isNotEmpty
                  ? 'No users found matching "${_searchController.text}"'
                  : 'No users found. Be the first to invite your friends!',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            if (_searchController.text.trim().isEmpty)
              ElevatedButton(
                onPressed: _loadInitialUsers,
                child: const Text('Refresh'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _users.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading indicator at the bottom
        if (index == _users.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        // User card
        return _buildUserItem(_users[index], theme);
      },
    );
  }

  Widget _buildUserItem(ChatUser user, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // User image
            ProfileImage(
              url: user.image,
              size: 55,
            ),
            
            const SizedBox(width: 12),
            
            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User name
                  Text(
                    user.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // User about
                  Text(
                    user.about,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            
            // Add button
            LayoutBuilder(
              builder: (context, constraints) {
                return ElevatedButton(
                  onPressed: () => _addAsFriend(user),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onPrimary,
                    backgroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    minimumSize: const Size(60, 36),
                  ),
                  child: const Text('Add'),
                );
              }
            ),
          ],
        ),
      ),
    );
  }
}
