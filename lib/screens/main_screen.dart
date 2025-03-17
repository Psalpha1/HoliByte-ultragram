import 'package:flutter/material.dart';
import '../screens/group_screen.dart';
import '../screens/home_screen.dart';
import '../utils/constants.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late PageController _pageController;
  int _selectedIndex = 0;

  // Animation controller for gradient transition
  late AnimationController _gradientAnimController;
  late Animation<double> _gradientAnimation;

  // Cache the screens to prevent recreation
  final List<Widget> _screens = const [
    HomeScreen(key: PageStorageKey('home_screen')),
    GroupScreen(key: PageStorageKey('group_screen')),
  ];

  // Add PageStorage to persist scroll positions and other state
  final PageStorageBucket _bucket = PageStorageBucket();

  // Current gradient colors
  final List<Color> _currentGradient = AppConstants.homeGradient;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _selectedIndex,
      keepPage: true, // Keep page state when switching
      viewportFraction: 1.0,
    );

    // Initialize gradient animation controller
    _gradientAnimController = AnimationController(
      vsync: this,
      duration: AppConstants.pageTransitionDuration,
    );

    _gradientAnimation = CurvedAnimation(
      parent: _gradientAnimController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _gradientAnimController.dispose();
    super.dispose();
  }

  // Handle bottom navigation tap
  void _onItemTapped(int index) {
    // If we're already on this tab, don't animate again
    if (_selectedIndex == index) return;

    // Start gradient animation
    _animateGradient(_selectedIndex, index);

    setState(() {
      _selectedIndex = index;
      // Animate to the selected page
      _pageController.animateToPage(
        index,
        duration: AppConstants.pageTransitionDuration,
        curve: Curves.easeInOut,
      );
    });
  }

  // Handle page change from swipe
  void _onPageChanged(int index) {
    if (_selectedIndex != index) {
      // Start gradient animation
      _animateGradient(_selectedIndex, index);

      setState(() {
        _selectedIndex = index;
      });
    }
  }

  // Animate gradient between tabs
  void _animateGradient(int fromIndex, int toIndex) {
    // Reset animation
    _gradientAnimController.reset();

    // Start animation
    _gradientAnimController.forward();
  }

  // Get interpolated gradient colors
  List<Color> _getAnimatedGradient() {
    final fromGradient = _selectedIndex == 0
        ? AppConstants.homeGradient
        : AppConstants.groupGradient;

    final toGradient = _selectedIndex == 0
        ? AppConstants.homeGradient
        : AppConstants.groupGradient;

    if (_gradientAnimation.value == 0) {
      return fromGradient;
    } else if (_gradientAnimation.value == 1) {
      return toGradient;
    }

    List<Color> animatedColors = [];

    for (int i = 0; i < fromGradient.length; i++) {
      final fromColor = fromGradient[i];
      final toColor = toGradient[i];

      final r = _lerpInt(fromColor.red, toColor.red, _gradientAnimation.value);
      final g =
          _lerpInt(fromColor.green, toColor.green, _gradientAnimation.value);
      final b =
          _lerpInt(fromColor.blue, toColor.blue, _gradientAnimation.value);
      final a =
          _lerpInt(fromColor.alpha, toColor.alpha, _gradientAnimation.value);

      animatedColors.add(Color.fromARGB(a, r, g, b));
    }

    return animatedColors;
  }

  // Linear interpolation for integer values
  int _lerpInt(int start, int end, double t) {
    return (start + (end - start) * t).round();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _gradientAnimation,
        builder: (context, child) {
          final gradientColors = _selectedIndex == 0
              ? AppConstants.homeGradient
              : AppConstants.groupGradient;

          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                  transform: GradientRotation(
                      DateTime.now().millisecondsSinceEpoch / 5000),
                ),
              ),
              child: PageStorage(
                bucket: _bucket,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: const BouncingScrollPhysics(),
                  children: _screens,
                ),
              ),
            ),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                elevation: 0,
                currentIndex: _selectedIndex,
                onTap: _onItemTapped,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                type: BottomNavigationBarType.fixed,
                unselectedItemColor: Colors.grey.shade600,
                showUnselectedLabels: true,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                unselectedLabelStyle: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
                items: [
                  _buildNavItem(0, 'Single Chat', Icons.chat_bubble_outline,
                      Icons.chat_bubble),
                  _buildNavItem(
                      1, 'Group Chat', Icons.group_outlined, Icons.group),
                ],
              ),
            ),
          );
        });
  }

  // Build custom navigation item with gradient for selected state
  BottomNavigationBarItem _buildNavItem(
      int index, String label, IconData icon, IconData activeIcon) {
    final isSelected = _selectedIndex == index;
    final gradient =
        index == 0 ? AppConstants.homeGradient : AppConstants.groupGradient;

    return BottomNavigationBarItem(
      icon: Icon(
        isSelected ? activeIcon : icon,
        color: isSelected ? gradient[0] : Colors.grey.shade600,
      ),
      label: label,
      activeIcon: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
        child: Icon(activeIcon),
      ),
    );
  }
}
