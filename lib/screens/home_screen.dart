import 'dart:developer';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/apis.dart';
import '../models/chat_user.dart';
import '../models/message.dart';
import '../utils/constants.dart';
import '../widgets/chat_user_card.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/search_bar.dart';
import 'ai_screen.dart';
import 'search_users_screen.dart';

//home screen -- where all available contacts are shown
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // for storing all users
  List<ChatUser> _list = [];
  // for storing searched items
  final List<ChatUser> _searchList = [];
  // for storing search status
  bool _isSearching = false;
  // for tracking initial load
  bool _isFirstLoad = true;
  // for storing user IDs
  List<String> _userIds = [];
  // for storing last messages
  final Map<String, Message?> _lastMessages = {};
  // for search controller
  final TextEditingController _searchController = TextEditingController();

  // Add these new controllers
  late AnimationController _refreshAnimationController;
  final ValueNotifier<double> _pullDistance = ValueNotifier<double>(0.0);
  bool _isRefreshing = false;

  // Add AI chat user
  final ChatUser _aiUser = ChatUser(
    id: 'ai_assistant',
    name: 'AI Chat',
    email: 'ai@assistant.com',
    about: 'Your personal AI assistant',
    image: 'https://img.icons8.com/color/96/000000/artificial-intelligence.png',
    createdAt: '',
    isOnline: true,
    lastActive: '',
    pushToken: '',
  );

  // Store subscriptions for cleanup
  final List<StreamSubscription> _subscriptions = [];

  @override
  bool get wantKeepAlive => true; // Keep the state alive

  @override
  void initState() {
    super.initState();
    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    _initializeData();

    // Lifecycle event handler
    SystemChannels.lifecycle.setMessageHandler(_handleLifecycleEvent);

    _refreshAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    // Cancel all subscriptions
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _searchController.dispose();
    _refreshAnimationController.dispose();
    _pullDistance.dispose();

    // Remove lifecycle handler
    SystemChannels.lifecycle.setMessageHandler(null);

    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      await APIs.getSelfInfo();
      if (!mounted) return;
      setState(() => _isFirstLoad = true); // Set loading state
      _setupUserSubscription();
    } catch (e) {
      log('Error initializing data: $e');
      if (!mounted) return;
      setState(() => _isFirstLoad = false); // End loading state on error
    }
  }

  Future<String?> _handleLifecycleEvent(String? message) async {
    log('Lifecycle Message: $message');

    if (APIs.auth.currentUser != null) {
      if (message?.contains('resume') == true) {
        await APIs.updateActiveStatus(true);
      }
      if (message?.contains('pause') == true) {
        await APIs.updateActiveStatus(false);
      }
    }

    return message;
  }

  void _setupUserSubscription() {
    final subscription = APIs.getMyUsersId().listen((snapshot) {
      if (!mounted) return;

      final newUserIds = snapshot.docs.map((e) => e.id).toList();
      if (!_compareUserIds(_userIds, newUserIds)) {
        _userIds = newUserIds;
        _loadUserData();
      } else if (_isFirstLoad) {
        // Force load data on first load even if IDs haven't changed
        _loadUserData();
      }
    }, onError: (e) {
      log('Error in user ID subscription: $e');
      if (!mounted) return;
      setState(() => _isFirstLoad = false);
    });

    _subscriptions.add(subscription);
  }

  bool _compareUserIds(List<String> oldIds, List<String> newIds) {
    if (oldIds.length != newIds.length) return false;
    return oldIds.every((id) => newIds.contains(id));
  }

  void _loadUserData() {
    if (_userIds.isEmpty) {
      setState(() {
        _list = [];
        _isFirstLoad = false;
      });
      return;
    }

    final subscription = APIs.getAllUsers(_userIds).listen((snapshot) {
      if (!mounted) return;

      final users =
          snapshot.docs.map((e) => ChatUser.fromJson(e.data())).toList();

      // Setup listeners for last messages for each user
      for (var user in users) {
        final msgSubscription = APIs.getLastMessage(user).listen((msgSnapshot) {
          if (!mounted) return;
          if (msgSnapshot.docs.isNotEmpty) {
            setState(() {
              _lastMessages[user.id] =
                  Message.fromJson(msgSnapshot.docs.first.data());
              _list = APIs.sortUsersByLastMessage(users, _lastMessages);
            });
          } else {
            setState(() {
              _lastMessages[user.id] = null;
              _list = APIs.sortUsersByLastMessage(users, _lastMessages);
            });
          }
        });

        _subscriptions.add(msgSubscription);
      }

      setState(() {
        _list = APIs.sortUsersByLastMessage(users, _lastMessages);
        _isFirstLoad = false;
      });
    }, onError: (e) {
      log('Error loading user data: $e');
      if (!mounted) return;
      setState(() => _isFirstLoad = false);
    });

    _subscriptions.add(subscription);
  }

  // Modified search method to maintain sorting
  void _handleSearch(String searchText) {
    if (searchText.isEmpty) {
      setState(() => _searchList.clear());
      return;
    }

    final lowercaseQuery = searchText.toLowerCase();
    final filtered = _list.where((user) {
      return user.name.toLowerCase().contains(lowercaseQuery) ||
          user.email.toLowerCase().contains(lowercaseQuery);
    }).toList();

    setState(() => _searchList
      ..clear()
      ..addAll(filtered));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PopScope(
        canPop: false,
        onPopInvoked: _handlePopScope,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppConstants.homeGradient,
                // Add animated gradient effect
                transform: GradientRotation(
                    DateTime.now().millisecondsSinceEpoch / 5000),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  CustomAppBar(
                    title: 'Ultragram',
                    onProfileUpdated: () {
                      if (mounted) setState(() {});
                    },
                    isTransparent: true,
                    heroTag: AppConstants.homeHeroTag,
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
          floatingActionButton: _buildAnimatedFAB(),
        ),
      ),
    );
  }

  // Add this new method for animated FAB
  Widget _buildAnimatedFAB() {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1200),
      builder: (context, double value, child) {
        return Transform.scale(
          scale: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Opacity(
              opacity: value,
              child: _buildFloatingActionButton(),
            ),
          ),
        );
      },
    );
  }

  // Modify the _buildBody method to include the search bar
  Widget _buildBody() {
    return Column(
      children: [
        // Persistent search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.searchBarPadding,
            AppConstants.searchBarPadding,
            AppConstants.searchBarPadding,
            8,
          ),
          child: CustomSearchBar(
            controller: _searchController,
            hintText: 'Search chats...',
            onChanged: _handleSearch,
            borderRadius: AppConstants.borderRadius,
          ),
        ),

        // Chat list
        Expanded(
          child: _buildChatList(),
        ),
      ],
    );
  }

  // Add this new method for the chat list
  Widget _buildChatList() {
    if (_isFirstLoad) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
        ),
      );
    }

    final displayList = _searchController.text.isNotEmpty ? _searchList : _list;
    final allChats = [_aiUser, ...displayList]; // Add AI user at the top

    if (displayList.isEmpty && _searchController.text.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Always show AI chat card
          AnimatedScale(
            duration: AppConstants.animationDuration,
            scale: 1,
            child: ChatUserCard(
              user: _aiUser,
              lastMessage: Message(
                toId: _aiUser.id,
                msg: 'Ask me anything!',
                read: '',
                type: Type.text,
                fromId: _aiUser.id,
                sent: '',
              ),
            ),
          ),
          // Empty state message
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Icon(Icons.people_outline,
                    size: 80, color: Theme.of(context).disabledColor),
                const SizedBox(height: 16),
                Text(
                  'Start a conversation!',
                  style: TextStyle(
                    fontSize: 20,
                    color: Theme.of(context).disabledColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) {
            if (!_isRefreshing && notification.metrics.extentBefore == 0) {
              _pullDistance.value =
                  _pullDistance.value - notification.scrollDelta!;
              if (_pullDistance.value >=
                      AppConstants.refreshTriggerPullDistance &&
                  notification.dragDetails == null) {
                _handleRefresh();
              }
            }
            return false;
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            itemCount: allChats.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemBuilder: (context, index) {
              final user = allChats[index];
              return AnimatedScale(
                duration: AppConstants.animationDuration,
                scale: 1,
                child: ChatUserCard(
                  user: user,
                  lastMessage: user.id == _aiUser.id
                      ? Message(
                          toId: user.id,
                          msg: 'Ask me anything!',
                          read: '',
                          type: Type.text,
                          fromId: user.id,
                          sent: '',
                        )
                      : _lastMessages[user.id],
                  onTap: user.id == _aiUser.id
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AiScreen(),
                            ),
                          );
                        }
                      : null,
                  heroTag: AppConstants.chatCardHeroTag,
                ),
              );
            },
          ),
        ),
        _buildRefreshIndicator(),
      ],
    );
  }

  // Replace the _buildFloatingActionButton method
  FloatingActionButton _buildFloatingActionButton() {
    return FloatingActionButton(
      backgroundColor: Theme.of(context).primaryColor,
      heroTag: AppConstants.homeFabHeroTag,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SearchUsersScreen()),
        );
      },
      child: const Icon(
        Icons.person_add,
        color: Colors.white,
      ),
    );
  }

  Future<bool> _handlePopScope(bool shouldPop) async {
    if (_isSearching) {
      setState(() => _isSearching = false);
      return false;
    }

    // Show confirmation dialog
    final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Are you sure you want to exit?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldExit) {
      // Update status before exiting
      if (APIs.auth.currentUser != null) {
        await APIs.updateActiveStatus(false);
      }
      return true;
    }
    return false;
  }

  // Add this new method for the refresh indicator painter
  Widget _buildRefreshIndicator() {
    return ValueListenableBuilder<double>(
      valueListenable: _pullDistance,
      builder: (context, distance, _) {
        final progress = (distance / AppConstants.refreshTriggerPullDistance)
            .clamp(0.0, 1.0);
        return Positioned(
          top: distance - AppConstants.refreshIndicatorSize,
          left: MediaQuery.of(context).size.width / 2 -
              AppConstants.refreshIndicatorSize / 2,
          child: AnimatedBuilder(
            animation: _refreshAnimationController,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(AppConstants.refreshIndicatorSize,
                    AppConstants.refreshIndicatorSize),
                painter: _RefreshIndicatorPainter(
                  progress: progress,
                  refreshing: _isRefreshing,
                  rotationValue: _refreshAnimationController.value,
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Add this method for handling refresh
  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    _refreshAnimationController.repeat();

    try {
      await _initializeData();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
        _refreshAnimationController.stop();
        _refreshAnimationController.reset();
        _pullDistance.value = 0.0;
      }
    }
  }
}

// Add this new painter class at the end of the file
class _RefreshIndicatorPainter extends CustomPainter {
  final double progress;
  final bool refreshing;
  final double rotationValue;

  _RefreshIndicatorPainter({
    required this.progress,
    required this.refreshing,
    required this.rotationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - paint.strokeWidth;

    if (refreshing) {
      // Draw rotating arc when refreshing
      final startAngle = 2 * math.pi * rotationValue;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        2 * math.pi * 0.75,
        false,
        paint,
      );
    } else {
      // Draw progress arc when pulling
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RefreshIndicatorPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.refreshing != refreshing ||
        oldDelegate.rotationValue != rotationValue;
  }
}
