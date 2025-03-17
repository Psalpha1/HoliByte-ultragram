import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../notification/notification_service.dart';
import 'dart:convert';
import '../../api/apis.dart';

class BackgroundMessageService {
  static final BackgroundMessageService _instance = BackgroundMessageService._internal();
  factory BackgroundMessageService() => _instance;
  BackgroundMessageService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Map<String, StreamSubscription> _chatSubscriptions = {};
  final Map<String, Timestamp?> _lastNotificationTimestamps = {};
  final Map<String, Timestamp> _lastMessageTimestamps = {};

  bool _isInitialized = false;
  bool _isDisposed = false;

  StreamController<List<Map<String, dynamic>>> _usersController = StreamController<List<Map<String, dynamic>>>.broadcast();

  bool get isInitialized => _isInitialized;

  void updateLastMessageTimestamp(String userId, Timestamp timestamp) {
    _lastMessageTimestamps[userId] = timestamp;
    _updateUsersStream();
  }

  Stream<List<Map<String, dynamic>>> get sortedUsersStream => _usersController.stream;

  Future<void> refreshUsersStream() async {
    if (_auth.currentUser == null || _usersController.isClosed) return;

    if (!_isInitialized && !_isDisposed) {
      try {
        await initialize();
      } catch (e) {
        print('Failed to initialize during refreshUsersStream: $e');
      }
    }

    if (!_isInitialized && !_isDisposed) {
      print('Unable to refresh users stream: service not initialized');
      return;
    }

    bool updated = false;
    int retryCount = 0;
    const maxRetries = 2;

    while (!updated && retryCount < maxRetries) {
      try {
        await _updateUsersStream();
        updated = true;
      } catch (e) {
        print('Error refreshing users stream (attempt ${retryCount + 1}): $e');
        retryCount++;
        if (retryCount < maxRetries) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
  }

  Future<void> _updateUsersStream() async {
    if (_auth.currentUser == null || _usersController.isClosed) return;

    try {
      final usersSnapshot = await _firestore.collection('users').get();
      final currentUserId = _auth.currentUser!.uid;
      final List<Map<String, dynamic>> users = [];

      final List<String> chatRoomIds = [];
      final Map<String, Map<String, dynamic>> userDataMap = {};

      for (var userDoc in usersSnapshot.docs) {
        if (userDoc.id == currentUserId) continue;

        final userData = userDoc.data();
        userData['uid'] = userDoc.id;
        userDataMap[userDoc.id] = userData;

        chatRoomIds.add(APIs.getConversationID(userDoc.id));
      }

      final lastMessagesQueries = await Future.wait(
        chatRoomIds.map((chatRoomId) => _firestore
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get()),
      );

      final unreadCountQueries = await Future.wait(
        chatRoomIds.map((chatRoomId) => _firestore
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .where('receiverId', isEqualTo: currentUserId)
            .where('status', whereIn: [
              "MessageStatus.sent.name",
              "MessageStatus.delivered.name"
            ])
            .count()
            .get()),
      );

      for (var i = 0; i < chatRoomIds.length; i++) {
        final otherUserId = chatRoomIds[i].split('_').firstWhere((id) => id != currentUserId);
        final userData = userDataMap[otherUserId];

        if (userData == null) continue;

        final lastMessageDocs = lastMessagesQueries[i].docs;
        final unreadCount = unreadCountQueries[i].count;

        if (lastMessageDocs.isNotEmpty) {
          final data = lastMessageDocs.first.data();
          final List<dynamic> deletedFor = data['deletedFor'] ?? [];

          if (!deletedFor.contains(currentUserId)) {
            _lastMessageTimestamps[otherUserId] = data['timestamp'] as Timestamp;
            userData['lastMessageTimestamp'] = data['timestamp'];
            userData['lastMessage'] = data['message'];
            userData['read'] = data['senderId'] == currentUserId;

            if (data['senderId'] == otherUserId) {
              userData['lastSentMessageTimestamp'] = data['timestamp'];
            }
          } else {
            userData['lastMessageTimestamp'] = Timestamp.fromDate(DateTime(1970));
            userData['lastMessage'] = null;
            userData['read'] = true;
            userData['lastSentMessageTimestamp'] = Timestamp.fromDate(DateTime(1970));
          }
        } else {
          userData['lastMessageTimestamp'] = Timestamp.fromDate(DateTime(1970));
          userData['lastMessage'] = null;
          userData['read'] = true;
          userData['lastSentMessageTimestamp'] = Timestamp.fromDate(DateTime(1970));
        }

        userData['unreadCount'] = unreadCount;
        users.add(userData);
      }

      users.sort((a, b) {
        final Timestamp timestampA = a['lastMessageTimestamp'];
        final Timestamp timestampB = b['lastMessageTimestamp'];
        return timestampB.compareTo(timestampA);
      });

      if (!_usersController.isClosed) {
        _usersController.add(users);
      }
    } catch (e) {
      print('Error in _updateUsersStream: $e');
    }
  }

  Future<void> initialize() async {
    if (_isInitialized && !_isDisposed) return;

    if (_auth.currentUser == null) return;

    try {
      final initTimeout = Future.delayed(const Duration(seconds: 15))
          .then((_) => throw TimeoutException('Initialization timed out'));

      if (_isDisposed) {
        _isDisposed = false;
        _lastNotificationTimestamps.clear();
        _chatSubscriptions.clear();

        if (_usersController.isClosed) {
          _usersController = StreamController<List<Map<String, dynamic>>>.broadcast();
        }
      } else if (_isInitialized) {
        await _updateUsersStream();
        return;
      } else {
        _lastMessageTimestamps.clear();
        _lastNotificationTimestamps.clear();
        _chatSubscriptions.clear();

        if (_usersController.isClosed) {
          _usersController = StreamController<List<Map<String, dynamic>>>.broadcast();
        }
      }

      await Future.delayed(const Duration(milliseconds: 300));

      bool usersLoaded = false;
      int retryCount = 0;
      const maxRetries = 3;
      const retryDelay = Duration(milliseconds: 500);

      await Future.any([
        initTimeout,
        Future(() async {
          while (!usersLoaded && retryCount < maxRetries) {
            try {
              if (_auth.currentUser == null) {
                print('User no longer authenticated during initialization');
                return;
              }

              final usersSnapshot = await _firestore.collection('users').get();
              if (usersSnapshot.docs.isNotEmpty) {
                usersLoaded = true;
                await _updateUsersStream();
              } else {
                print('No users found, retry ${retryCount + 1}');
                await Future.delayed(retryDelay);
                retryCount++;
              }
            } catch (e) {
              print('Retry $retryCount failed: $e');
              if (e.toString().contains('permission-denied')) {
                await Future.delayed(const Duration(seconds: 1));
              } else {
                await Future.delayed(retryDelay);
              }
              retryCount++;
            }
          }

          if (!usersLoaded) {
            print('Failed to load users after $maxRetries retries');
            throw Exception('Failed to load users after $maxRetries retries');
          }
        })
      ]);

      _isInitialized = true;

      _firestore.collection('users').snapshots().listen(
        (usersSnapshot) async {
          if (!_usersController.isClosed && _auth.currentUser != null) {
            await _updateUsersStream();
          }
        },
        onError: (error) {
          print('Error in users collection listener: $error');
        },
      );

      final usersSnapshot = await _firestore.collection('users').get();
      for (var userDoc in usersSnapshot.docs) {
        if (userDoc.id != _auth.currentUser!.uid) {
          _listenToChatRoom(userDoc.id);
        }
      }
    } catch (e) {
      print('Error in initialize: $e');
      await dispose();
      rethrow;
    }
  }

  void _listenToChatRoom(String otherUserId) {
    final String currentUserId = _auth.currentUser!.uid;
    String chatRoomId = APIs.getConversationID(otherUserId);

    _chatSubscriptions[chatRoomId]?.cancel();

    _chatSubscriptions[chatRoomId] = _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen(
      (snapshot) async {
        if (snapshot.docs.isEmpty) return;

        final messageData = snapshot.docs.first.data();
        final messageTimestamp = messageData['timestamp'] as Timestamp;
        final lastNotificationTimestamp = _lastNotificationTimestamps[otherUserId];

        if (lastNotificationTimestamp == null || messageTimestamp.compareTo(lastNotificationTimestamp) > 0) {
          _lastNotificationTimestamps[otherUserId] = messageTimestamp;
        }

        updateLastMessageTimestamp(otherUserId, messageTimestamp);
      },
      onError: (error) {
        print('Error in chat room listener: $error');
      },
    );

    _chatSubscriptions['calls_$chatRoomId'] = _firestore
        .collection('Notifications')
        .where('userId', isEqualTo: currentUserId)
        .where('type', isEqualTo: 'call')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen(
      (snapshot) async {
        for (var doc in snapshot.docs) {
          final notificationData = doc.data();

          if (notificationData['userId'] == currentUserId) {
            final notificationService = NotificationService();
            final Map<String, dynamic> callPayload = {
              'type': 'call',
              'senderId': notificationData['senderId'],
              'senderEmail': notificationData['body'].replaceAll('Call from ', ''),
              'roomId': json.decode(notificationData['payload'])['roomId'],
            };

            final String encodedPayload = json.encode(callPayload);
            final String roomId = callPayload['roomId'] as String;

            final roomDoc = await _firestore.collection('rooms').doc(roomId).get();
            if (!roomDoc.exists || (roomDoc.data() as Map<String, dynamic>)['ended'] == true) {
              await doc.reference.update({'isRead': true});
              return;
            }

            _firestore.collection('rooms').doc(roomId).snapshots().listen((snapshot) {
              if (!snapshot.exists || (snapshot.data() as Map<String, dynamic>)['ended'] == true) {
                notificationService.cancelCallNotification(roomId);
              }
            });

            await notificationService.showIncomingCallNotification(
              callerName: callPayload['senderEmail'],
              payload: encodedPayload,
            );

            await doc.reference.update({'isRead': true});
          }
        }
      },
      onError: (error) {
        print('Error in call notifications listener: $error');
      },
    );
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    for (var subscription in _chatSubscriptions.values) {
      await subscription.cancel();
    }
    _chatSubscriptions.clear();

    _lastMessageTimestamps.clear();
    _lastNotificationTimestamps.clear();

    if (!_usersController.isClosed) {
      await _usersController.close();
    }
  }
}
