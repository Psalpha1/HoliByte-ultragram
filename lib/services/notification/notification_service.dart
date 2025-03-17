import 'dart:developer';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'dart:io'; // Add this import for Platform
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/material.dart';

class NotificationService {
  // Instance of FlutterLocalNotificationsPlugin
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  // Singleton pattern
  static final NotificationService _notificationService =
      NotificationService._internal();
  factory NotificationService() {
    return _notificationService;
  }
  NotificationService._internal() {
    _audioPlayer.setSource(AssetSource('sounds/call.mp3'));
    log('Notification service initialized');
  }

  // Add a map to track active call notifications
  final Map<String, int> _activeCallNotifications = {};

  // Add a map to track message notifications by sender
  final Map<String, Set<int>> _activeMessageNotifications = {};

  // Add a set to track active call dialogs
  final Set<String> _activeCallDialogs = {};

  // Static methods to store navigation functions
  static void Function(String, String)? navigateToChat;
  static void Function(String, String, String)? navigateToCall;

  // Add a static method to store the current context
  static BuildContext? _currentContext;
  static void setCurrentContext(BuildContext context) {
    _currentContext = context;
  }

  // Request notification permissions
  Future<bool> requestNotificationPermissions() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  // Start playing ringtone and vibration
  Future<void> _startRingtoneAndVibration() async {
    if (!_isPlaying) {
      try {
        _isPlaying = true;

        // Start vibration pattern
        if (await Vibration.hasVibrator()) {
          Vibration.vibrate(
              pattern: [500, 1000, 500, 1000],
              repeat: -1); // Continuous pattern
        }
        log('Vibration started'); // Debug log

        // Play ringtone in loop
        await _audioPlayer.setSource(AssetSource('sounds/call.mp3'));
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.resume();

        log('Ringtone started playing'); // Debug log
      } catch (e) {
        print('Error playing ringtone: $e');
        _isPlaying = false;
      }
    }
  }

  // Stop playing ringtone and vibration
  Future<void> _stopRingtoneAndVibration() async {
    if (_isPlaying) {
      _isPlaying = false;
      await _audioPlayer.stop();
      if (await Vibration.hasVibrator()) {
        Vibration.cancel();
      }
      log('Ringtone and vibration stopped'); // Debug log
    }
  }

  // Initialize notification settings
  Future<void> initializeNotifications() async {
    // Request permissions first
    final permissionGranted = await requestNotificationPermissions();
    if (!permissionGranted) {
      print('Notification permissions not granted');
      return;
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          'call_category',
          options: {
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
          actions: [
            DarwinNotificationAction.plain(
              'accept_call',
              'Accept',
              options: {
                DarwinNotificationActionOption.foreground,
                DarwinNotificationActionOption.authenticationRequired,
              },
            ),
            DarwinNotificationAction.plain(
              'decline_call',
              'Decline',
              options: {
                DarwinNotificationActionOption.destructive,
              },
            ),
          ],
        ),
      ],
    );

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // Set up notification action handler
    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        try {
          log('Notification action received: ${response.actionId}');
          final payload = response.payload;
          final actionId = response.actionId;
          // print('Notification action received: $actionId');

          if (payload != null) {
            final data = json.decode(payload);
            print('Payload data: $data');

            if (data['type'] == 'call') {
              final roomId = data['roomId'];
              final notificationId = data['notificationId'];

              // Stop ringtone and vibration immediately
              // await _stopRingtoneAndVibration();
              // log("This is a call notification for [Call] after stopping ringtone and vibration");

              if (actionId == 'accept_call' && navigateToCall != null) {
                log("Call Accepted");
                // Handle accept action
                navigateToCall!(
                  data['senderId'],
                  data['senderEmail'],
                  roomId,
                );
              } else if (actionId == 'decline_call') {
                log("decline_call Button has pressed");
                // Handle decline action
                print('Decline action triggered for room: $roomId');
                try {
                  // Cancel notification first
                  await _notifications.cancel(notificationId);
                  await cancelCallNotification(roomId);

                  // Update room status
                  await FirebaseFirestore.instance
                      .collection('rooms')
                      .doc(roomId)
                      .update({
                    'ended': true,
                    'endReason': 'declined',
                    'endedAt': FieldValue.serverTimestamp(),
                  });
                } catch (e) {
                  print('Error handling decline action: $e');
                }
              } else {
                // Default tap action - show the in-app dialog instead of accepting
                if (_currentContext != null) {
                  showInAppCallDialog(
                    callerName: data['senderEmail'],
                    senderId: data['senderId'],
                    senderEmail: data['senderEmail'],
                    roomId: roomId,
                  );
                }
              }
            } else if (data['type'] == 'message' && navigateToChat != null) {
              log("This is a message notification for [Message TEXT]");
              // Handle message notification tap
              navigateToChat!(
                data['senderId'],
                data['senderEmail'],
              );
            }
          }
        } catch (e) {
          print('Error handling notification response: $e');
        }
      },
    );

    // Set up platform-specific notification channels
    if (Platform.isAndroid) {
      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Remove any existing channels to ensure clean configuration
        await androidPlugin.deleteNotificationChannel('calls_channel');
        await androidPlugin.deleteNotificationChannel('messages_channel');

        // Create the calls channel with full-screen intent and high priority
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'calls_channel',
            'Calls',
            description: 'Notifications for incoming calls',
            importance: Importance.max,
            enableVibration: true,
            playSound: false,
            showBadge: true,
            enableLights: true,
          ),
        );

        // Create the messages channel with high priority
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'messages_channel',
            'Messages',
            description: 'Notifications for new messages',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
            showBadge: true,
            enableLights: true,
            sound: RawResourceAndroidNotificationSound('notification'),
          ),
        );
      }
    }
  }

  // Show message notification
  Future<void> showMessageNotification({
    required String title,
    required String body,
    required String senderId,
    required String senderEmail,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'messages_channel',
      'Messages',
      channelDescription: 'Notifications for new messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.message,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = json.encode({
      'type': 'message',
      'senderId': senderId,
      'senderEmail': senderEmail,
    });

    // Generate a unique notification ID within 32-bit integer range
    final notificationId = DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;

    // Track the notification
    _activeMessageNotifications
        .putIfAbsent(senderId, () => {})
        .add(notificationId);

    await _notifications.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  // Show call notification
  Future<void> sendCallNotification({
    required String receiverUserId,
    required String callerName,
    required String roomId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Only store the notification in Firestore for the receiver
    await _firestore.collection('Notifications').add({
      'userId': receiverUserId,
      'senderId': currentUser.uid,
      'title': 'Incoming Call',
      'body': 'Call from $callerName',
      'type': 'call',
      'payload': json.encode({
        'type': 'call',
        'senderId': currentUser.uid,
        'senderEmail': callerName,
        'roomId': roomId,
      }),
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  // Show consolidated notification
  Future<void> showConsolidatedNotification({
    required String title,
    required String body,
    required String senderId,
    required String senderEmail,
    required String type,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'consolidated_channel',
      'Consolidated Notifications',
      channelDescription: 'Consolidated notifications for messages and calls',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.message,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = json.encode({
      'type': type,
      'senderId': senderId,
      'senderEmail': senderEmail,
    });

    // Generate a unique notification ID within 32-bit integer range
    final notificationId = DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;

    // Track the notification
    _activeMessageNotifications
        .putIfAbsent(senderId, () => {})
        .add(notificationId);

    await _notifications.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  // Show in-app call dialog
  Future<void> showInAppCallDialog({
    required String callerName,
    required String senderId,
    required String senderEmail,
    required String roomId,
  }) async {
    if (_currentContext == null) return;

    if (_activeCallDialogs.contains(roomId)) {
      print('Dialog for call $roomId is already being shown');
      return;
    }

    _activeCallDialogs.add(roomId);
    bool isDialogActive = true; // Set this to true initially
    StreamSubscription? roomListener;
    final context = _currentContext!;

    await _startRingtoneAndVibration();

    void cleanupCall() {
      _activeCallDialogs.remove(roomId);
      isDialogActive = false;
      roomListener?.cancel();
      _stopRingtoneAndVibration();
    }

    // Set up room listener
    roomListener = _firestore
        .collection('rooms')
        .doc(roomId)
        .snapshots()
        .listen((snapshot) async {
      if (!isDialogActive) return;

      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data['ended'] == true && isDialogActive) {
          try {
            Navigator.of(context).pop();
            cleanupCall();
            await cancelCallNotification(roomId);
          } catch (e) {
            print('Error handling external cancellation: $e');
          }
        }
      }
    });

    try {
      if (!context.mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: const Text('Incoming Call'),
            content: Text('$callerName is calling...'),
            actions: [
              TextButton(
                onPressed: () async {
                  log("The Decline Button has Presses");
                  if (!isDialogActive) return;

                  try {
                    // Set isDialogActive to false first
                    isDialogActive = false;

                    // Handle the decline operations
                    await _handleDeclineCall(roomId);

                    // Clean up and close dialog
                    cleanupCall();
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  } catch (e) {
                    print('Error in decline button: $e');
                    cleanupCall();
                  }
                },
                child: const Text(
                  'Decline',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              TextButton(
                onPressed: () async {
                  if (!isDialogActive) return;

                  try {
                    isDialogActive = false;
                    cleanupCall();

                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }

                    if (navigateToCall != null) {
                      navigateToCall!(senderId, senderEmail, roomId);
                    }
                  } catch (e) {
                    print('Error in accept button: $e');
                    cleanupCall();
                  }
                },
                child: const Text(
                  'Accept',
                  style: TextStyle(color: Colors.green),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('Error showing dialog: $e');
      cleanupCall();
    }
  }

  // Handle decline call operations
  Future<void> _handleDeclineCall(String roomId) async {
    try {
      // Cancel notification first to stop ringtone
      await cancelCallNotification(roomId);

      // Update room status
      await _firestore.collection('rooms').doc(roomId).update({
        'ended': true,
        'endReason': 'declined',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error handling decline call: $e');
      // Make sure to still try to cancel notification even if room update fails
      await cancelCallNotification(roomId);
    }
  }

  // Modify showIncomingCallNotification method
  Future<void> showIncomingCallNotification({
    required String callerName,
    required String payload,
  }) async {
    final payloadData = json.decode(payload);
    final String roomId = payloadData['roomId'];
    final String senderId = payloadData['senderId'];
    final String senderEmail = payloadData['senderEmail'];

    // Check if there's already a notification or dialog for this call
    if (_activeCallNotifications.containsKey(roomId) ||
        _activeCallDialogs.contains(roomId)) {
      print('Call $roomId is already being handled');
      return;
    }

    // Create a unique notification ID based on roomId
    final notificationId = roomId.hashCode;
    _activeCallNotifications[roomId] = notificationId;

    bool showingInAppDialog = _currentContext != null;

    // Start ringtone and vibration
    log("This is a call notification for [Call] before starting ringtone and vibration");
    await _startRingtoneAndVibration();

    // Only start ringtone for in-app dialog, system notification will be silent
    if (showingInAppDialog) {
      // Show in-app dialog without awaiting to allow system notification to show as well
      unawaited(showInAppCallDialog(
        callerName: callerName,
        senderId: senderId,
        senderEmail: senderEmail,
        roomId: roomId,
      ));
    }

    // Define action buttons for Android
    final List<AndroidNotificationAction> androidActions = [
      const AndroidNotificationAction(
        'accept_call',
        'Accept',
        titleColor: Color.fromARGB(255, 0, 255, 0),
        showsUserInterface: true,
      ),
      const AndroidNotificationAction(
        'decline_call',
        'Decline',
        titleColor: Color.fromARGB(255, 255, 0, 0),
        showsUserInterface: true,
        // cancelNotification: true,
      ),
    ];

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'calls_channel',
      'Calls',
      channelDescription: 'Notifications for incoming calls',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      ongoing: true,
      autoCancel: false,
      enableVibration: !showingInAppDialog,
      playSound: false, // Always disable sound for notifications
      visibility: NotificationVisibility.public,
      timeoutAfter: 45000, // Timeout after 45 seconds
      actions: androidActions,
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false, // Disable sound for iOS notifications
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'call_category',
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Add additional payload data
    final enrichedPayload = json.encode({
      ...payloadData,
      'notificationId': notificationId,
    });

    // Show the notification
    await _notifications.show(
      notificationId,
      'Incoming Call',
      'Call from $callerName',
      notificationDetails,
      payload: enrichedPayload,
    );

    // Set up a timer to auto-cancel the call after 45 seconds
    Timer(const Duration(milliseconds: 45000), () async {
      if (_activeCallNotifications.containsKey(roomId)) {
        await cancelCallNotification(roomId);
        await FirebaseFirestore.instance
            .collection('rooms')
            .doc(roomId)
            .update({
          'ended': true,
          'endReason': 'timeout',
          'endedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // Cancel call notification and cleanup resources
  Future<void> cancelCallNotification(String roomId) async {
    final notificationId = _activeCallNotifications[roomId];
    if (notificationId != null) {
      try {
        // Stop ringtone and vibration first
        log("_stopRingtoneAndVibration for cancel button");
        await _stopRingtoneAndVibration();

        // Cancel the notification
        await _notifications.cancel(notificationId);

        // Remove from active notifications map
        _activeCallNotifications.remove(roomId);

        // Remove from Firestore if it exists
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await FirebaseFirestore.instance
              .collection('Notifications')
              .where('type', isEqualTo: 'call')
              .where('payload', isGreaterThanOrEqualTo: '{"roomId":"$roomId"}')
              .where('payload', isLessThan: '{"roomId":"$roomId\uf8ff"}')
              .get()
              .then((snapshot) {
            for (var doc in snapshot.docs) {
              doc.reference.delete();
            }
          });
        }
      } catch (e) {
        print('Error cancelling call notification: $e');
      }
    }
  }

  // Cancel all message notifications for a specific sender
  Future<void> cancelMessageNotifications(String senderId) async {
    final notificationIds = _activeMessageNotifications[senderId];
    if (notificationIds != null) {
      for (final id in notificationIds) {
        await _notifications.cancel(id);
      }
      _activeMessageNotifications.remove(senderId);
    }
  }

  // Dispose method to clean up resources
  void dispose() {
    log("_stopRingtoneAndVibration for dispose");
    _stopRingtoneAndVibration();
    _audioPlayer.dispose();
  }
}
