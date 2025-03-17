import 'dart:developer';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_notification_channel/flutter_notification_channel.dart';
import 'package:flutter_notification_channel/notification_importance.dart';
import 'package:we_chat/screens/call_page.dart';
import 'package:we_chat/services/chat/background_service_initializer.dart';
import 'package:we_chat/services/notification/notification_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:we_chat/themes/dark_mode.dart';
import 'package:we_chat/themes/light_mode.dart';
import 'package:we_chat/themes/theme_provider.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'package:provider/provider.dart';

//global object for accessing device screen size
late Size mq;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //enter full-screen
  //enter full-screen
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Disable keyboard animation globally
  SystemChannels.textInput
      .invokeMethod('TextInput.setImeAnimation', {'enabled': false});

  // Add additional system settings
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
  ));

  await _initializeFirebase();

  // Initialize the notification service
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize notifications and background services in parallel
  try {
    await Future.wait([
      NotificationService().initializeNotifications(),
    ], eagerError: true);
  } catch (e) {
    print('Service initialization error: $e');
    // Allow app to continue even if some service initialization fails
  }

  //for setting orientation to portrait only
  SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown])
      .then((value) {
    runApp(
      ChangeNotifierProvider(
        create: (context) => ThemeProvider(),
        child: const MyApp(),
      ),
    );
  });

  // Initialize other services in the background
  _initializeServices();
}

Future<void> _initializeFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  var result = await FlutterNotificationChannel().registerNotificationChannel(
      description: 'For Showing Message Notification',
      id: 'chats',
      importance: NotificationImportance.IMPORTANCE_HIGH,
      name: 'Chats');

  log('\nNotification Channel Result: $result');
}

Future<void> _initializeServices() async {
  // Initialize FlutterTTS
  FlutterTts().awaitSpeakCompletion(true);

  // Initialize notifications and background services in parallel
  try {
    await Future.wait([
      BackgroundServiceInitializer().initialize(),
      NotificationService().initializeNotifications(),
    ], eagerError: true);
  } catch (e) {
    print('Service initialization error: $e');
    // Allow app to continue even if some service initialization fails
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  // Add this static method to access the state
  static _MyAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<_MyAppState>();
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _notificationService = NotificationService();
  bool _isRequestingPermissions = false;
  // ignore: unused_field
  ThemeMode _themeMode = ThemeMode.light;

  void updateThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  void initState() {
    super.initState();
    _setupNotificationNavigation();
    // Remove the direct call to _requestNotificationPermissions
    // and call it after a delay to avoid race conditions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermissions();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    NotificationService.setCurrentContext(context);
  }

  Future<void> _requestNotificationPermissions() async {
    // Prevent multiple simultaneous permission requests
    if (_isRequestingPermissions) return;

    try {
      _isRequestingPermissions = true;
      final granted =
          await _notificationService.requestNotificationPermissions();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Please enable notifications to receive message alerts'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('Error requesting permissions: $e');
    } finally {
      _isRequestingPermissions = false;
    }
  }

  void _setupNotificationNavigation() {
    // NotificationService.navigateToChat = (String senderId, String senderEmail) {
    //   _navigatorKey.currentState?.push(
    //     MaterialPageRoute(
    //       builder: (context) => ChatScreen(),
    //     ),
    //   );
    // };

    NotificationService.navigateToCall =
        (String senderId, String senderEmail, String roomId) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => CallPage(
            receiverUserId: senderId,
            receiverUserEmail: senderEmail,
            isIncoming: true,
            roomId: roomId,
          ),
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Unfocus any text field when tapping outside
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: _navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: lightTheme, // Use custom light theme
            darkTheme: darkTheme, // Use custom dark theme
            themeMode:
                themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            themeAnimationDuration: ThemeProvider.animationDuration,
            themeAnimationCurve: Curves.easeInOut,
            home: Builder(
              builder: (context) {
                NotificationService.setCurrentContext(context);
                return const SplashScreen();
              },
            ),
          );
        },
      ),
    );
  }
}
