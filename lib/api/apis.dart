import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart';
import 'package:path/path.dart';
import '../models/chat_user.dart';
import '../models/message.dart';
import 'notification_access_token.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class APIs {
  String botToken = "YOUR_TELEGRAM_BOT_TOKEN";
  String storageId = "YOUR_STORAGE_ID";
  // Enpoint for uploading images
  static final String uploadUrl = 'http://YOUR_UPLOAD_URL/upload.php';

  // for authentication
  static FirebaseAuth get auth => FirebaseAuth.instance;

  // for accessing cloud firestore database
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  // for accessing firebase storage
  static FirebaseStorage storage = FirebaseStorage.instance;

  // for storing self information
  static ChatUser me = ChatUser(
      id: user.uid,
      name: user.displayName.toString(),
      email: user.email.toString(),
      about: "hi I'm using ultra gram",
      image: user.photoURL.toString(),
      createdAt: '',
      isOnline: false,
      lastActive: '',
      pushToken: '');

  // to return current user
  static User get user => auth.currentUser!;

  // for accessing firebase messaging (Push Notification)
  static FirebaseMessaging fMessaging = FirebaseMessaging.instance;

  // for getting firebase messaging token
  static Future<void> getFirebaseMessagingToken() async {
    await fMessaging.requestPermission();

    await fMessaging.getToken().then((t) {
      if (t != null) {
        me.pushToken = t;
        log('Push Token: $t');
      }
    });

    // for handling foreground messages
    // FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    //   log('Got a message whilst in the foreground!');
    //   log('Message data: ${message.data}');

    //   if (message.notification != null) {
    //     log('Message also contained a notification: ${message.notification}');
    //   }
    // });
  }

  // for sending push notification (Updated Codes)
  static Future<void> sendPushNotification(ChatUser chatUser, String msg,
      {Type? messageType}) async {
    try {
      // Determine notification text based on message type
      String notificationText = msg;
      if (messageType == Type.audio) {
        notificationText = '🎤 Voice message';
      } else if (messageType == Type.image) {
        notificationText = '📷 Photo';
      } else if (messageType == Type.file) {
        notificationText = '📁 File';
      }

      final body = {
        "message": {
          "token": chatUser.pushToken,
          "notification": {
            "title": me.name, //our name should be send
            "body": notificationText,
          },
        }
      };

      // Firebase Project > Project Settings > General Tab > Project ID
      const projectID = 'credible-acre-336514';

      // get firebase admin token
      final bearerToken = await NotificationAccessToken.getToken;

      log('bearerToken: $bearerToken');

      // handle null token
      if (bearerToken == null) return;

      var res = await post(
        Uri.parse(
            'https://fcm.googleapis.com/v1/projects/$projectID/messages:send'),
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $bearerToken'
        },
        body: jsonEncode(body),
      );

      log('Response status: ${res.statusCode}');
      log('Response body: ${res.body}');
    } catch (e) {
      log('\nsendPushNotificationE: $e');
    }
  }

  // for checking if user exists or not?
  static Future<bool> userExists() async {
    return (await firestore.collection('users').doc(user.uid).get()).exists;
  }

  // for adding an chat user for our conversation
  static Future<bool> addChatUser(String email) async {
    final data = await firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .get();

    log('data: ${data.docs}');

    if (data.docs.isNotEmpty && data.docs.first.id != user.uid) {
      //user exists

      log('user exists: ${data.docs.first.data()}');

      firestore
          .collection('users')
          .doc(user.uid)
          .collection('my_users')
          .doc(data.docs.first.id)
          .set({});

      return true;
    } else {
      //user doesn't exists

      return false;
    }
  }

  // for getting current user info
  static Future<void> getSelfInfo() async {
    await firestore.collection('users').doc(user.uid).get().then((user) async {
      if (user.exists) {
        me = ChatUser.fromJson(user.data()!);
        await getFirebaseMessagingToken();

        //for setting user status to active
        APIs.updateActiveStatus(true);
        log('My Data: ${user.data()}');
      } else {
        await createUser().then((value) => getSelfInfo());
      }
    });
  }

  // for creating a new user
  static Future<void> createUser() async {
    final time = DateTime.now().millisecondsSinceEpoch.toString();

    final chatUser = ChatUser(
        id: user.uid,
        name: user.email.toString().split('@').first,
        email: user.email.toString(),
        about: "hi I'm using ultra gram",
        image: user.photoURL.toString(),
        createdAt: time,
        isOnline: false,
        lastActive: time,
        pushToken: '');

    return await firestore
        .collection('users')
        .doc(user.uid)
        .set(chatUser.toJson());
  }

  // for getting id's of known users from firestore database
  static Stream<QuerySnapshot<Map<String, dynamic>>> getMyUsersId() {
    return firestore
        .collection('users')
        .doc(user.uid)
        .collection('my_users')
        .snapshots();
  }

  // for getting all users from firestore database
  static Stream<QuerySnapshot<Map<String, dynamic>>> getAllUsers(
      List<String> userIds) {
    log('\nUserIds: $userIds');

    return firestore
        .collection('users')
        .where('id',
            whereIn: userIds.isEmpty
                ? ['']
                : userIds) //because empty list throws an error
        // .where('id', isNotEqualTo: user.uid)
        .snapshots();
  }

  // Sort users by their last message timestamp
  static List<ChatUser> sortUsersByLastMessage(
      List<ChatUser> users, Map<String, Message?> lastMessages) {
    return List<ChatUser>.from(users)
      ..sort((a, b) {
        final aMessage = lastMessages[a.id];
        final bMessage = lastMessages[b.id];

        if (aMessage == null && bMessage == null) return 0;
        if (aMessage == null) return 1;
        if (bMessage == null) return -1;

        return int.parse(bMessage.sent).compareTo(int.parse(aMessage.sent));
      });
  }

  // for sending message
  static Future<void> sendMessage(
    ChatUser chatUser,
    String msg,
    Type type, {
    String? localImgPath,
    String? fileName,
    int? fileSize,
    String? fileType,
    String? replyTo,
    bool forwarded = false,
  }) async {
    try {
      // Generate message timestamp (used as message ID)
      final String time = DateTime.now().millisecondsSinceEpoch.toString();

      // Construct message object with replyTo support
      final Message message = Message(
        toId: chatUser.id,
        fromId: user.uid,
        msg: msg,
        type: type,
        sent: time,
        read: '',
        localImgPath: localImgPath,
        fileName: fileName,
        fileSize: fileSize,
        fileType: fileType,
        replyTo: replyTo,
        forwarded: forwarded,
      );

      // Reference to Firestore chat messages
      final ref = firestore
          .collection('chats/${getConversationID(chatUser.id)}/messages/');

      // Save message to Firestore
      await ref.doc(time).set(message.toJson());

      // Send notification if user is not online
      if (!chatUser.isOnline) {
        await sendPushNotification(chatUser, msg, messageType: type);
      }
    } catch (e) {
      log('\nSendMessageError: $e');
    }
  }

  // for adding an user to my user when first message is send
  static Future<void> sendFirstMessage(ChatUser chatUser, String msg, Type type,
      {String? replyTo}) async {
    await firestore
        .collection('users')
        .doc(chatUser.id)
        .collection('my_users')
        .doc(user.uid)
        .set({}).then(
            (value) => sendMessage(chatUser, msg, type, replyTo: replyTo));
  }

  // for updating user information
  static Future<void> updateUserInfo() async {
    await firestore.collection('users').doc(user.uid).update({
      'name': me.name,
      'image': me.image,
      'about': me.about,
    });
  }

  // Method to update profile picture
  static Future<String?> updateProfilePicture(File file) async {
    try {
      // Check if file exists
      if (!file.existsSync()) {
        log("File not found");
        return null;
      }

      // Read image bytes and detect format
      final List<int> imageBytes = await file.readAsBytes();
      final fileExtension = extension(file.path).toLowerCase();
      String fileType = '';

      if (fileExtension == '.jpg' || fileExtension == '.jpeg') {
        fileType = 'image/jpeg';
      } else if (fileExtension == '.png') {
        fileType = 'image/png';
      } else if (fileExtension == '.gif') {
        fileType = 'image/gif';
      } else {
        log('Unsupported file type.');
        return null;
      }

      // Check if compression is needed (100KB = 102400 bytes)
      List<int> compressedBytes = imageBytes;
      if (imageBytes.length > 102400) {
        final img.Image? originalImage =
            img.decodeImage(Uint8List.fromList(imageBytes));
        if (originalImage == null) {
          log('Failed to decode image');
          return null;
        }

        // Calculate new dimensions while maintaining aspect ratio
        int targetWidth = originalImage.width;
        int targetHeight = originalImage.height;
        double quality = 85; // Initial quality

        while (compressedBytes.length > 102400 && quality > 5) {
          // Reduce dimensions if still too large
          if (quality <= 30) {
            targetWidth = (targetWidth * 0.8).round();
            targetHeight = (targetHeight * 0.8).round();
          }

          final img.Image resized = img.copyResize(
            originalImage,
            width: targetWidth,
            height: targetHeight,
          );

          compressedBytes = fileExtension == '.png'
              ? img.encodePng(resized)
              : img.encodeJpg(resized, quality: quality.round());

          quality -= 10;
        }
      }

      final uri = Uri.parse('https://Your_Upload_URL.com/upload.php');
      final request = http.MultipartRequest('POST', uri);

      // Upload compressed image
      final fileStream = http.MultipartFile.fromBytes(
        'file',
        compressedBytes,
        filename: basename(file.path),
        contentType: MediaType.parse(fileType),
      );

      request.files.add(fileStream);

      // Send the request
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        log('Response: $responseBody');

        // Parse JSON response to get the URL
        var data = jsonDecode(responseBody);
        if (data['url'] != null) {
          String imageUrl = data['url'];
          log('Image uploaded successfully: $imageUrl');

          // Pre-download and cache the image
          await DefaultCacheManager().downloadFile(imageUrl);

          // Update image in firestore database
          await firestore
              .collection('users')
              .doc(user.uid)
              .update({'image': imageUrl});

          return imageUrl;
        }
      }
      log('Upload failed with status code: ${response.statusCode}');
      return null;
    } catch (e) {
      log('Error updating profile picture: $e');
      return null;
    }
  }

  Future<String> fetchUserProfileImage(String userId) async {
    final docSnapshot =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if (docSnapshot.exists) {
      return docSnapshot['image'] ?? '';
    } else {
      return '';
    }
  }

  // for getting specific user info
  static Stream<QuerySnapshot<Map<String, dynamic>>> getUserInfo(
      ChatUser chatUser) {
    return firestore
        .collection('users')
        .where('id', isEqualTo: chatUser.id)
        .snapshots();
  }

  // update online or last active status of user
  static Future<void> updateActiveStatus(bool isOnline) async {
    firestore.collection('users').doc(user.uid).update({
      'is_online': isOnline,
      'last_active': DateTime.now().millisecondsSinceEpoch.toString(),
      'push_token': me.pushToken,
    });
  }

  ///************** Chat Screen Related APIs **************

  // chats (collection) --> conversation_id (doc) --> messages (collection) --> message (doc)

  // useful for getting conversation id
  static String getConversationID(String id) => user.uid.hashCode <= id.hashCode
      ? '${user.uid}_$id'
      : '${id}_${user.uid}';

  // for getting all messages of a specific conversation from firestore database
  static Stream<QuerySnapshot<Map<String, dynamic>>> getAllMessages(
      ChatUser user) {
    return firestore
        .collection('chats/${getConversationID(user.id)}/messages/')
        .orderBy('sent', descending: true)
        .snapshots();
  }

  // update read status of message
  static Future<void> updateMessageReadStatus(Message message) async {
    firestore
        .collection('chats/${getConversationID(message.fromId)}/messages/')
        .doc(message.sent)
        .update({'read': DateTime.now().millisecondsSinceEpoch.toString()});
  }

  //get only last message of a specific chat
  static Stream<QuerySnapshot<Map<String, dynamic>>> getLastMessage(
      ChatUser user) {
    return firestore
        .collection('chats/${getConversationID(user.id)}/messages/')
        .orderBy('sent', descending: true)
        .limit(1)
        .snapshots();
  }

  // Get the file path with better error handling
  Future<String?> getFilePath(String fileId) async {
    try {
      var uri = Uri.parse(
          'https://api.telegram.org/bot$botToken/getFile?file_id=$fileId');
      var response = await http.get(uri);

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        if (jsonResponse['ok'] == true && jsonResponse['result'] != null) {
          return jsonResponse['result']['file_path'];
        } else {
          log('Invalid response format: ${response.body}');
          return null;
        }
      } else {
        log('Failed to get file path: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      log('Error getting file path: $e');
      return null;
    }
  }

  // Get direct file URL with validation
  String? getDirectFileUrl(String filePath) {
    try {
      final url = 'https://api.telegram.org/file/bot$botToken/$filePath';
      return url;
    } catch (e) {
      log('Error creating direct file URL: $e');
      return null;
    }
  }

  // Validate file URL
  Future<bool> isFileUrlValid(String url) async {
    try {
      final response = await http.head(Uri.parse(url));
      return response.statusCode == 200;
    } catch (e) {
      log('Error validating file URL: $e');
      return false;
    }
  }

  // Upload file with enhanced error handling
  Future<void> uploadFile(
    File file,
    ChatUser user,
    Type type,
    String fileName,
    int fileSize,
    String? fileType,
  ) async {
    // Check if the file exists
    if (!file.existsSync()) {
      print('File does not exist: ${file.path}');
      return;
    }

    // Log file details
    print('Uploading File: ${file.path}');
    print('File Size: ${file.lengthSync()} bytes');

    // Telegram Bot API endpoint for sending documents or videos
    var uri = Uri.parse(
        'https://api.telegram.org/bot$botToken/${type == Type.video ? 'sendVideo' : 'sendDocument'}');
    var request = http.MultipartRequest('POST', uri)
      ..fields['chat_id'] = storageId;

    // Add file with appropriate field name and content type
    if (type == Type.video) {
      request.files.add(await http.MultipartFile.fromPath(
        'video',
        file.path,
        contentType: MediaType('video', 'mp4'),
      ));
    } else {
      request.files.add(await http.MultipartFile.fromPath(
        'document',
        file.path,
        contentType: fileType != null ? MediaType.parse(fileType) : null,
      ));
    }

    log('Request: $request');

    try {
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      print('Response Status Code: ${response.statusCode}');
      print('Response Body: $responseBody');

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(responseBody)['result'];
        var fileId = type == Type.video
            ? jsonResponse['video']['file_id']
            : jsonResponse['document']['file_id'];
        String? filePath = await getFilePath(fileId);

        if (filePath == null) {
          print('Failed to get file path');
          return;
        }

        String? directUrl = getDirectFileUrl(filePath);
        if (directUrl == null) {
          print('Failed to get direct URL');
          return;
        }

        await sendMessage(user, directUrl, type,
            localImgPath: file.path,
            fileName: fileName,
            fileSize: fileSize,
            fileType: fileType);

        print('File uploaded and metadata saved');
      } else {
        print('Failed to upload file: ${response.statusCode}');
      }
    } catch (e) {
      print('Error uploading file: $e');
      rethrow; // Rethrow to allow proper error handling in UI
    }
  }

  //delete message
  static Future<void> deleteMessage(Message message) async {
    await firestore
        .collection('chats/${getConversationID(message.toId)}/messages/')
        .doc(message.sent)
        .delete();

    if (message.type == Type.image) {
      await storage.refFromURL(message.msg).delete();
    }
  }

  //update message
  static Future<void> updateMessage(Message message, String updatedMsg) async {
    await firestore
        .collection('chats/${getConversationID(message.toId)}/messages/')
        .doc(message.sent)
        .update({'msg': updatedMsg});
  }

  //update message reactions
  static Future<void> updateMessageReactions(
      Message message, List<String> reactions) async {
    try {
      // Get the correct conversation ID based on the message direction
      final String conversationId = message.fromId == user.uid
          ? getConversationID(message.toId)
          : getConversationID(message.fromId);

      await firestore
          .collection('chats/$conversationId/messages/')
          .doc(message.sent)
          .update({'reactions': reactions});
    } catch (e) {
      log('Error updating reactions: $e');
    }
  }

  // Authentication Methods
  static Future<UserCredential?> loginWithEmailPassword(
      String email, String password) async {
    try {
      final UserCredential userCredential =
          await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      log('Login Error: ${e.message}');
      rethrow;
    }
  }

  static Future<UserCredential?> registerWithEmailPassword(
      String email, String password) async {
    try {
      final UserCredential userCredential =
          await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      log('Registration Error: ${e.message}');
      rethrow;
    }
  }

  static Future<void> logout() async {
    try {
      await updateActiveStatus(false);
      await auth.signOut();
    } catch (e) {
      log('Logout Error: $e');
      rethrow;
    }
  }

  static Future<void> resetPassword(String email) async {
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      log('Reset Password Error: ${e.message}');
      rethrow;
    }
  }

  static Future<void> updatePassword(String newPassword) async {
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      log('Update Password Error: ${e.message}');
      rethrow;
    }
  }

  static Future<void> deleteAccount() async {
    try {
      await updateActiveStatus(false);
      await firestore.collection('users').doc(user.uid).delete();
      await user.delete();
    } catch (e) {
      log('Delete Account Error: $e');
      rethrow;
    }
  }

  // User Session Management
  static Future<void> initializeUserSession() async {
    await getFirebaseMessagingToken();
    await getSelfInfo();
    updateActiveStatus(true);
  }

  // Terms and Conditions Management
  static const String _termsVersion = '1.0.0'; // Track terms version
  static const String _termsCollection = 'user_terms';

  // Get terms and conditions content
  static String getTermsAndConditions() {
    return 'By using our app, you agree to:\n\n'
        '1. Respect other users\' privacy\n'
        '2. Not share inappropriate content\n'
        '3. Not spam or harass other users\n'
        '4. Allow us to process your data as described in our Privacy Policy\n'
        '5. Accept our terms of service\n\n'
        'For more details, please visit our website.';
  }

  // Show terms and conditions dialog
  static Future<void> showTermsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    color: Colors.blue.shade700,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Terms and Conditions',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 2,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade200,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(height: 24),

                // Terms content
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text(
                    getTermsAndConditions(),
                    style: TextStyle(
                      color: Colors.grey[800],
                      height: 1.5,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Close button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'I Understand',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Show terms and conditions error dialog
  static Future<void> showTermsErrorDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.white,
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.verified_user_outlined,
            color: Colors.blue.shade700,
            size: 32,
          ),
        ),
        title: Column(
          children: [
            Text(
              'One Last Step',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 2,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.blue.shade200,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'To complete your registration and join our community, please accept the Terms and Conditions.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[800],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Check the box to accept Terms and Conditions',
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Understood',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Save user's terms acceptance
  static Future<void> acceptTerms() async {
    try {
      await firestore.collection(_termsCollection).doc(user.uid).set({
        'accepted': true,
        'acceptedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        'termsVersion': _termsVersion,
      });
    } catch (e) {
      log('Accept Terms Error: $e');
      rethrow;
    }
  }

  // Check if user has accepted terms
  static Future<bool> hasAcceptedTerms() async {
    try {
      final doc =
          await firestore.collection(_termsCollection).doc(user.uid).get();

      return doc.exists &&
          doc.data()?['accepted'] == true &&
          doc.data()?['termsVersion'] == _termsVersion;
    } catch (e) {
      log('Check Terms Error: $e');
      return false;
    }
  }

  // Register with terms acceptance
  static Future<UserCredential?> registerWithTerms(
      String email, String password, bool acceptedTerms) async {
    if (!acceptedTerms) {
      throw FirebaseAuthException(
        code: 'terms-not-accepted',
        message: 'You must accept the terms and conditions',
      );
    }

    try {
      final userCredential = await registerWithEmailPassword(email, password);
      if (userCredential != null) {
        await acceptTerms();
      }
      return userCredential;
    } catch (e) {
      log('Register with Terms Error: $e');
      rethrow;
    }
  }

  // Method to get AI-enhanced message suggestions
  static Future<Map<String, String>> getMessageSuggestions(
      String message) async {
    try {
      const apiKey = 'YOUR_OPENROUTER_API_KEY';
      final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json; charset=utf-8',
          'HTTP-Referer': 'https://github.com/your-username/your-repo',
        },
        body: utf8.encode(jsonEncode({
          'model': 'google/gemini-2.0-flash-lite-preview-02-05:free',
          'messages': [
            {
              'role': 'system',
              'content':
                  '''You are an assistant that enhances messages in different styles while strictly preserving the original language, special characters, and formatting.

Language & Formatting Rules:
Always respond in the same language as the input.
Preserve all special characters, emojis, and symbols exactly as they appear.
Tunisian Latin Arabic (Arabizi) Rules:
If the input contains Tunisian Latin Arabic (e.g., "3" for ع, "7" for ح, "9" for ق, or words like "chna7wel", "labess", "sa7bi"), follow these style-specific guidelines:

Professional Style: Respond in formal French (no Arabizi).
Creative Style: Respond in Tunisian Latin Arabic with expressive and artistic flair.
Bold Style: Respond in Tunisian Latin Arabic with a strong and confident tone.
Funny Style: Respond in Tunisian Latin Arabic with humor and wit.
Maintain number-based letter substitutions (3, 7, 5, 9, etc.) in non-professional styles.
Keep mixed French-Arabic patterns unless switching to professional style, which should be pure French.
Other Language Rules:
English: Respond in English for all styles.
Standard Arabic (الفصحى): Respond in Standard Arabic for all styles.
French & Spanish: Maintain accents (e.g., é, è, ê, ñ, ú, etc.).
Mixed-Language Inputs: Retain the original mix of languages and dialects.
Core Principle:
Ensure responses match the tone, dialect, and character set of the input while applying the requested style. The only exception is Tunisian Arabic in professional style, which must be in French.'''
            },
            {
              'role': 'user',
              'content':
                  '''Enhance the following message in four distinct styles.

If the message is in Tunisian Arabic (Darija), the Professional style should be in French; otherwise, keep the original language.
Ensure each style reflects its unique tone and purpose.
Styles:

Professional: Formal, polished, and business-like (in French if the input is Tunisian Arabic).
Creative: Imaginative, expressive, and artistically enhanced.
Bold: Strong, confident, and impactful.
Funny: Witty, humorous, and playful.
Message: $message

Respond in this exact format (one line per style):
Professional: [professional version]
Creative: [creative version]
Bold: [bold version]
Funny: [funny version]'''
            }
          ],
        })),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        final content =
            jsonResponse['choices'][0]['message']['content'] as String;
        final suggestions = content.split('\n');

        if (suggestions.length >= 4) {
          return {
            'professional': suggestions[0].replaceAll('Professional: ', ''),
            'creative': suggestions[1].replaceAll('Creative: ', ''),
            'bold': suggestions[2].replaceAll('Bold: ', ''),
            'funny': suggestions[3].replaceAll('Funny: ', ''),
          };
        }
      }

      log('API Response: ${utf8.decode(response.bodyBytes)}');
      throw Exception('Failed to get suggestions: ${response.statusCode}');
    } catch (e) {
      log('Error getting AI suggestions: $e');
      return {
        'professional': message,
        'creative': message,
        'bold': message,
        'funny': message,
      };
    }
  }

  // Get all users with pagination (for users search)
  static Future<List<ChatUser>> getAllUsersWithPagination(
      int limit, DocumentSnapshot? lastDoc) async {
    try {
      // Use a simpler query that doesn't require a composite index
      Query<Map<String, dynamic>> query = firestore
          .collection('users')
          .orderBy('name') // Order by name only
          .limit(limit);

      // Apply pagination if lastDoc is provided
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final result = await query.get();

      // Filter out current user after getting results
      return result.docs
          .map((e) => ChatUser.fromJson(e.data()))
          .where((user) =>
              user.id != APIs.user.uid) // Filter current user client-side
          .toList();
    } catch (e) {
      log('Error getting all users: $e');
      log('Error details: ${e.toString()}');
      return [];
    }
  }

  // Search users by name or email
  static Future<List<ChatUser>> searchUsers(String query) async {
    try {
      // Search is case insensitive and searches for partial matches
      String searchTerm = query.toLowerCase();

      // Use a simpler query without the where clause that might require an index
      final snapshot =
          await firestore.collection('users').orderBy('name').get();

      // Filter current user and apply search client-side
      final filteredUsers = snapshot.docs
          .map((e) => ChatUser.fromJson(e.data()))
          .where((user) => user.id != APIs.user.uid) // Filter current user
          .where((user) => // Apply search filter
              user.name.toLowerCase().contains(searchTerm) ||
              user.email.toLowerCase().contains(searchTerm))
          .toList();

      return filteredUsers;
    } catch (e) {
      log('Error searching users: $e');
      log('Error details: ${e.toString()}');
      return [];
    }
  }

  // Add to APIs class
  static Future<void> blockUser(String userId) async {
    try {
      final batch = firestore.batch();

      // Update blocked users array
      final userDoc = firestore.collection('users').doc(user.uid);
      batch.update(userDoc, {
        'blockedUsers': FieldValue.arrayUnion([userId])
      });

      // Remove from my_users collection
      final myUserDoc = userDoc.collection('my_users').doc(userId);
      batch.delete(myUserDoc);

      // Execute both operations atomically
      await batch.commit();
    } catch (e) {
      log('Error blocking user: $e');
      rethrow;
    }
  }

  static Future<void> unblockUser(String userId) async {
    try {
      // Update blocked users array by removing the user ID
      await firestore.collection('users').doc(user.uid).update({
        'blockedUsers': FieldValue.arrayRemove([userId])
      });
    } catch (e) {
      log('Error unblocking user: $e');
      rethrow;
    }
  }

  static Stream<List<String>> getBlockedUsers() {
    return firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return [];
      final data = snapshot.data();
      if (data == null) return [];
      
      final List<dynamic> blockedUsers = data['blockedUsers'] ?? [];
      return blockedUsers.cast<String>();
    });
  }

  static Future<List<ChatUser>> getBlockedUserDetails(List<String> blockedUserIds) async {
    if (blockedUserIds.isEmpty) return [];
    
    try {
      final snapshot = await firestore
          .collection('users')
          .where('id', whereIn: blockedUserIds)
          .get();
          
      return snapshot.docs.map((doc) => ChatUser.fromJson(doc.data())).toList();
    } catch (e) {
      log('Error getting blocked user details: $e');
      return [];
    }
  }

  static Future<void> reportUser(String userId, String reason) async {
    await firestore.collection('reports').add({
      'reportedUser': userId,
      'reportedBy': user.uid,
      'reason': reason,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'status': 'pending'
    });
  }
}
