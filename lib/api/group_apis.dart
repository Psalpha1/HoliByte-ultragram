import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart';

import '../models/chat_user.dart';
import '../models/group.dart';
import '../models/group_message.dart';
import '../models/message.dart';
import 'apis.dart';

class GroupAPIs {
  // Telegram Bot credentials
  static final String botToken = "YOUR_BOT_TOKEN";
  static final String storageId = "YOUR_STORAGE_ID";

  // Firestore instance
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  // Create a new group
  static Future<Group?> createGroup({
    required String name,
    required String description,
    required File? imageFile,
    required List<String> members,
    bool isPublic = false,
  }) async {
    try {
      // Generate a unique group ID
      final String groupId = firestore.collection('groups').doc().id;
      final String time = DateTime.now().millisecondsSinceEpoch.toString();

      // Add current user to members and admins
      if (!members.contains(APIs.user.uid)) {
        members.add(APIs.user.uid);
      }

      // Upload group image if provided
      String imageUrl = '';
      if (imageFile != null) {
        imageUrl = await _uploadGroupImage(imageFile, groupId) ?? '';
      }

      // Create group object
      final group = Group(
        id: groupId,
        name: name,
        description: description,
        image: imageUrl,
        createdAt: time,
        createdBy: APIs.user.uid,
        members: members,
        admins: [APIs.user.uid], // Creator is the first admin
        lastMessage: '',
        lastMessageTime: time,
        isPublic: isPublic,
      );

      // Save group to Firestore
      await firestore.collection('groups').doc(groupId).set(group.toJson());

      // Add group reference to each member's groups collection
      for (var memberId in members) {
        await firestore
            .collection('users')
            .doc(memberId)
            .collection('groups')
            .doc(groupId)
            .set({'joined_at': time});
      }

      // Create welcome message
      await sendGroupMessage(
        group: group,
        msg: '${APIs.me.name} created this group',
        type: Type.text,
      );

      return group;
    } catch (e) {
      log('Error creating group: $e');
      rethrow; // Rethrow to allow proper error handling in UI
    }
  }

  // Upload group image
  static Future<String?> _uploadGroupImage(File file, String groupId) async {
    try {
      // Check if file exists
      if (!file.existsSync()) {
        log("File not found");
        return null;
      }

      final uri = Uri.parse('https://YOUR_UPLOAD_URL.com/upload.php');
      final request = http.MultipartRequest('POST', uri);

      // Determine file type
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

      // Upload image
      final fileStream = http.MultipartFile.fromBytes(
        'file',
        await file.readAsBytes(),
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
          log('Group image uploaded successfully: $imageUrl');
          return imageUrl;
        }
      }

      log('Upload failed with status code: ${response.statusCode}');
      return null;
    } catch (e) {
      log('Error uploading group image: $e');
      return null;
    }
  }

  // Get all groups for current user
  static Stream<QuerySnapshot<Map<String, dynamic>>> getUserGroups() {
    return firestore
        .collection('users')
        .doc(APIs.user.uid)
        .collection('groups')
        .snapshots();
  }

  // Get group details by ID
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getGroupById(
      String groupId) {
    return firestore.collection('groups').doc(groupId).snapshots();
  }

  // Sort groups by their last message timestamp
  /// Sort groups by their last message timestamps without requiring additional Firebase requests.
  ///
  /// This method sorts a list of groups based on their last messages, similar to how
  /// individual chats are sorted. The UI should set up listeners for each group's last
  /// message and maintain a map of the most recent messages.
  ///
  /// Example usage in a stateful widget:
  /// ```dart
  /// List<Group> _groups = [];
  /// Map<String, GroupMessage?> _lastMessages = {};
  /// List<StreamSubscription> _subscriptions = [];
  ///
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   _loadGroups();
  /// }
  ///
  /// void _loadGroups() {
  ///   final subscription = GroupAPIs.getAllGroups().listen((groups) {
  ///     if (!mounted) return;
  ///
  ///     // Setup listeners for last messages for each group
  ///     for (var group in groups) {
  ///       final msgSubscription = GroupAPIs.getGroupLastMessage(group.id).listen((msgSnapshot) {
  ///         if (!mounted) return;
  ///
  ///         if (msgSnapshot.docs.isNotEmpty) {
  ///           setState(() {
  ///             _lastMessages[group.id] = GroupMessage.fromJson(msgSnapshot.docs.first.data());
  ///             _groups = GroupAPIs.sortGroupsByLastMessage(groups, _lastMessages);
  ///           });
  ///         } else {
  ///           setState(() {
  ///             _lastMessages[group.id] = null;
  ///             _groups = GroupAPIs.sortGroupsByLastMessage(groups, _lastMessages);
  ///           });
  ///         }
  ///       });
  ///
  ///       _subscriptions.add(msgSubscription);
  ///     }
  ///
  ///     setState(() {
  ///       _groups = GroupAPIs.sortGroupsByLastMessage(groups, _lastMessages);
  ///     });
  ///   });
  ///
  ///   _subscriptions.add(subscription);
  /// }
  ///
  /// @override
  /// void dispose() {
  ///   for (var subscription in _subscriptions) {
  ///     subscription.cancel();
  ///   }
  ///   super.dispose();
  /// }
  /// ```
  static List<Group> sortGroupsByLastMessage(
      List<Group> groups, Map<String, GroupMessage?> lastMessages) {
    return List<Group>.from(groups)
      ..sort((a, b) {
        final aMessage = lastMessages[a.id];
        final bMessage = lastMessages[b.id];

        if (aMessage == null && bMessage == null) {
          // If no messages for both groups, sort by lastMessageTime from group object
          return b.lastMessageTime.compareTo(a.lastMessageTime);
        }
        if (aMessage == null) return 1;
        if (bMessage == null) return -1;

        return int.parse(bMessage.sent).compareTo(int.parse(aMessage.sent));
      });
  }

  // Get all groups that current user is a member of (with optimized sorting)
  /// Get all groups that the current user is a member of.
  ///
  /// This method returns a stream of groups without final sorting by messages.
  /// For proper sorting that matches the chat user list behavior:
  /// 1. Use this method to get the initial list of groups
  /// 2. For each group, set up a listener on getGroupLastMessage(groupId)
  /// 3. Maintain a map of group IDs to their last messages
  /// 4. Use sortGroupsByLastMessage() to sort the groups by their last messages
  ///
  /// See the example in the documentation for sortGroupsByLastMessage().
  static Stream<List<Group>> getAllGroups() {
    // This method now returns the basic group list without sorting
    // The UI should set up listeners for last messages and use sortGroupsByLastMessage
    return getUserGroups().asyncMap((groupsSnapshot) async {
      List<Group> groups = [];
      final futures = <Future>[];

      for (var doc in groupsSnapshot.docs) {
        final groupId = doc.id;
        final future =
            firestore.collection('groups').doc(groupId).get().then((groupDoc) {
          if (groupDoc.exists) {
            groups.add(Group.fromJson(groupDoc.data()!));
          }
        }).catchError((e) {
          log('Error fetching group $groupId: $e');
        });

        futures.add(future);
      }

      await Future.wait(futures);

      // Sort by lastMessageTime as a fallback, but UI should re-sort with last messages
      groups.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

      return groups;
    });
  }

  // Send message to group
  static Future<void> sendGroupMessage({
    required Group group,
    required String msg,
    required Type type,
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

      // Get current user info
      final currentUser = APIs.me;

      // Construct group message object
      final GroupMessage message = GroupMessage(
        groupId: group.id,
        fromId: APIs.user.uid,
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
        senderName: currentUser.name,
        senderImage: currentUser.image,
      );

      // Reference to Firestore group messages
      final ref = firestore.collection('group_chats/${group.id}/messages/');

      // Save message to Firestore
      await ref.doc(time).set(message.toJson());

      // Update group's last message and time
      await firestore.collection('groups').doc(group.id).update({
        'last_message': _getLastMessagePreview(message),
        'last_message_time': time,
      });

      // Send notifications to group members
      _sendGroupNotifications(group, message);
    } catch (e) {
      log('❌ Error sending group message: $e');
    }
  }

  // Get all messages of a specific group
  static Stream<QuerySnapshot<Map<String, dynamic>>> getGroupMessages(
      String groupId) {
    return firestore
        .collection('group_chats/$groupId/messages/')
        .orderBy('sent', descending: true)
        .snapshots();
  }

  // Helper method to get last message preview for group
  static String _getLastMessagePreview(GroupMessage message) {
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
        content = '🎤 Voice message';
        break;
      case Type.video:
        content = '📹 Video';
        break;
    }

    return '$senderName: $content';
  }

  // Send notifications to all group members except sender
  static Future<void> _sendGroupNotifications(
      Group group, GroupMessage message) async {
    try {
      // Get all group members except current user
      final members = group.members.where((id) => id != APIs.user.uid).toList();

      if (members.isEmpty) return;

      // Get FCM tokens for all members
      final usersSnapshot = await firestore
          .collection('users')
          .where('id', whereIn: members)
          .get();

      // Prepare notification content
      String notificationText = '';

      switch (message.type) {
        case Type.text:
          notificationText = message.msg;
          break;
        case Type.image:
          notificationText = '📷 Photo';
          break;
        case Type.file:
          notificationText = '📁 File';
          break;
        case Type.audio:
          notificationText = '🎤 Voice message';
          break;
        case Type.video:
          notificationText = '📹 Video';
          break;
      }

      // Send notification to each member
      for (var doc in usersSnapshot.docs) {
        final user = ChatUser.fromJson(doc.data());

        if (user.pushToken.isNotEmpty) {
          await APIs.sendPushNotification(
              user, '${group.name}\n${message.senderName}: $notificationText');
        }
      }
    } catch (e) {
      log('Error sending group notifications: $e');
    }
  }

  // Add members to group
  static Future<void> addGroupMembers(
      String groupId, List<String> newMembers) async {
    try {
      // Get current group data
      final groupDoc = await firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final group = Group.fromJson(groupDoc.data()!);
      final currentMembers = group.members;
      final time = DateTime.now().millisecondsSinceEpoch.toString();

      // Filter out members who are already in the group
      final membersToAdd =
          newMembers.where((id) => !currentMembers.contains(id)).toList();

      if (membersToAdd.isEmpty) return;

      // Add new members to group
      final updatedMembers = [...currentMembers, ...membersToAdd];
      await firestore.collection('groups').doc(groupId).update({
        'members': updatedMembers,
      });

      // Add group reference to each new member's groups collection
      for (var memberId in membersToAdd) {
        await firestore
            .collection('users')
            .doc(memberId)
            .collection('groups')
            .doc(groupId)
            .set({'joined_at': time});
      }

      // Get names of added members - process in batches of 10 to avoid Firestore limitations
      List<String> memberNames = [];

      // Process in batches of 10 (Firestore limit for whereIn)
      for (int i = 0; i < membersToAdd.length; i += 10) {
        final end =
            (i + 10 < membersToAdd.length) ? i + 10 : membersToAdd.length;
        final batch = membersToAdd.sublist(i, end);

        final batchSnapshot = await firestore
            .collection('users')
            .where('id', whereIn: batch)
            .get();

        final batchNames = batchSnapshot.docs
            .map((doc) => ChatUser.fromJson(doc.data()).name)
            .toList();

        memberNames.addAll(batchNames);
      }

      final memberNamesStr = memberNames.join(', ');

      // Send system message about new members
      await sendGroupMessage(
        group: group,
        msg: '${APIs.me.name} added $memberNamesStr to the group',
        type: Type.text,
      );
    } catch (e) {
      log('Error adding group members: $e');
      rethrow; // Rethrow to allow proper error handling in UI
    }
  }

  // Remove member from group
  static Future<void> removeGroupMember(String groupId, String memberId) async {
    try {
      // Get current group data
      final groupDoc = await firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final group = Group.fromJson(groupDoc.data()!);

      // Check if current user is admin
      if (!group.admins.contains(APIs.user.uid)) {
        log('Only admins can remove members');
        return;
      }

      // Remove member from group
      final updatedMembers =
          group.members.where((id) => id != memberId).toList();

      // Also remove from admins if they were an admin
      final updatedAdmins = group.admins.where((id) => id != memberId).toList();

      await firestore.collection('groups').doc(groupId).update({
        'members': updatedMembers,
        'admins': updatedAdmins,
      });

      // Remove group reference from member's groups collection
      await firestore
          .collection('users')
          .doc(memberId)
          .collection('groups')
          .doc(groupId)
          .delete();

      // Get removed member's name
      final userDoc = await firestore.collection('users').doc(memberId).get();
      final userName = ChatUser.fromJson(userDoc.data()!).name;

      // Send system message about removed member
      await sendGroupMessage(
        group: group,
        msg: '${APIs.me.name} removed $userName from the group',
        type: Type.text,
      );
    } catch (e) {
      log('Error removing group member: $e');
    }
  }

  // Leave group
  static Future<void> leaveGroup(String groupId) async {
    try {
      // Get current group data
      final groupDoc = await firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final group = Group.fromJson(groupDoc.data()!);

      // Remove current user from members
      final updatedMembers =
          group.members.where((id) => id != APIs.user.uid).toList();

      // Remove from admins if they were an admin
      final updatedAdmins =
          group.admins.where((id) => id != APIs.user.uid).toList();

      // If this was the last member, delete the group
      if (updatedMembers.isEmpty) {
        await _deleteGroup(groupId);
        return;
      }

      // If this was the last admin, make the oldest member an admin
      if (updatedAdmins.isEmpty && updatedMembers.isNotEmpty) {
        updatedAdmins.add(updatedMembers.first);
      }

      await firestore.collection('groups').doc(groupId).update({
        'members': updatedMembers,
        'admins': updatedAdmins,
      });

      // Remove group reference from user's groups collection
      await firestore
          .collection('users')
          .doc(APIs.user.uid)
          .collection('groups')
          .doc(groupId)
          .delete();

      // Send system message about user leaving
      await sendGroupMessage(
        group: group,
        msg: '${APIs.me.name} left the group',
        type: Type.text,
      );
    } catch (e) {
      log('Error leaving group: $e');
    }
  }

  // Delete group (only for admins)
  static Future<void> _deleteGroup(String groupId) async {
    try {
      // Delete group document
      await firestore.collection('groups').doc(groupId).delete();

      // Delete all messages
      final messagesSnapshot =
          await firestore.collection('group_chats/$groupId/messages/').get();

      for (var doc in messagesSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete group chat collection
      await firestore.collection('group_chats').doc(groupId).delete();

      // Remove group reference from all members
      final usersWithGroupSnapshot = await firestore
          .collectionGroup('groups')
          .where(FieldPath.documentId, isEqualTo: groupId)
          .get();

      for (var doc in usersWithGroupSnapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      log('Error deleting group: $e');
    }
  }

  // Make user an admin
  static Future<void> makeGroupAdmin(String groupId, String userId) async {
    try {
      // Get current group data
      final groupDoc = await firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final group = Group.fromJson(groupDoc.data()!);

      // Check if current user is admin
      if (!group.admins.contains(APIs.user.uid)) {
        log('Only admins can add new admins');
        return;
      }

      // Check if user is already an admin
      if (group.admins.contains(userId)) {
        return;
      }

      // Add user to admins
      final updatedAdmins = [...group.admins, userId];
      await firestore.collection('groups').doc(groupId).update({
        'admins': updatedAdmins,
      });

      // Get user's name
      final userDoc = await firestore.collection('users').doc(userId).get();
      final userName = ChatUser.fromJson(userDoc.data()!).name;

      // Send system message about new admin
      await sendGroupMessage(
        group: group,
        msg: '${APIs.me.name} made $userName an admin',
        type: Type.text,
      );
    } catch (e) {
      log('Error making user admin: $e');
    }
  }

  // Update group info
  static Future<void> updateGroupInfo({
    required String groupId,
    String? name,
    String? description,
    File? imageFile,
    bool? isPublic,
  }) async {
    try {
      // Get current group data
      final groupDoc = await firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final group = Group.fromJson(groupDoc.data()!);

      // Check if current user is admin
      if (!group.admins.contains(APIs.user.uid)) {
        log('Only admins can update group info');
        return;
      }

      // Prepare update data
      final Map<String, dynamic> updateData = {};

      if (name != null && name.trim().isNotEmpty) {
        updateData['name'] = name;
      }

      if (description != null) {
        updateData['description'] = description;
      }

      if (isPublic != null) {
        updateData['is_public'] = isPublic;
      }

      // Upload new image if provided
      if (imageFile != null) {
        final imageUrl = await _uploadGroupImage(imageFile, groupId);
        if (imageUrl != null) {
          updateData['image'] = imageUrl;
        }
      }

      if (updateData.isEmpty) return;

      // Update group info
      await firestore.collection('groups').doc(groupId).update(updateData);

      // Send system message about group update
      String updateMsg = '${APIs.me.name} updated ';
      if (updateData.containsKey('name')) {
        updateMsg += 'group name';
      } else if (updateData.containsKey('description')) {
        updateMsg += 'group description';
      } else if (updateData.containsKey('image')) {
        updateMsg += 'group image';
      } else if (updateData.containsKey('is_public')) {
        updateMsg += isPublic! ? 'group to public' : 'group to private';
      } else {
        updateMsg += 'group info';
      }

      await sendGroupMessage(
        group: group,
        msg: updateMsg,
        type: Type.text,
      );
    } catch (e) {
      log('Error updating group info: $e');
    }
  }

  // Get the file path with better error handling
  static Future<String?> getFilePath(String fileId) async {
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
  static String? getDirectFileUrl(String filePath) {
    try {
      final url = 'https://api.telegram.org/file/bot$botToken/$filePath';
      return url;
    } catch (e) {
      log('Error creating direct file URL: $e');
      return null;
    }
  }

  // Validate file URL
  static Future<bool> isFileUrlValid(String url) async {
    try {
      final response = await http.head(Uri.parse(url));
      return response.statusCode == 200;
    } catch (e) {
      log('Error validating file URL: $e');
      return false;
    }
  }

  // Upload file to Telegram for group chats
  static Future<void> uploadFileToTelegram(
    File file,
    Group group,
    Type type,
    String fileName,
    int fileSize,
    String? fileType,
    String? replyTo,
  ) async {
    // Check if the file exists
    if (!file.existsSync()) {
      log('File does not exist: ${file.path}');
      return;
    }

    // Log file details
    log('Uploading File to Telegram: ${file.path}');
    log('File Size: ${file.lengthSync()} bytes');

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

      log('Response Status Code: ${response.statusCode}');
      log('Response Body: $responseBody');

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(responseBody)['result'];
        var fileUrl = type == Type.video
            ? jsonResponse['video']['file_id']
            : jsonResponse['document']['file_id'];
        String? filePath = await getFilePath(fileUrl);

        if (filePath == null) {
          log('Failed to get file path');
          return;
        }

        String? directUrl = getDirectFileUrl(filePath);
        if (directUrl == null) {
          log('Failed to get direct URL');
          return;
        }

        // Send the message with the file URL
        await sendGroupMessage(
          group: group,
          msg: directUrl,
          type: type,
          localImgPath: file.path,
          fileName: fileName,
          fileSize: fileSize,
          fileType: fileType,
          replyTo: replyTo,
        );
      } else {
        log('Failed to upload file to Telegram: ${response.statusCode}');
      }
    } catch (e) {
      log('Error uploading file to Telegram: $e');
    }
  }

  // Upload image to Telegram for group chats
  static Future<void> uploadImageToTelegram(
    File imageFile,
    Group group,
    String? replyTo,
  ) async {
    // Check if the file exists
    if (!imageFile.existsSync()) {
      log('Image file does not exist: ${imageFile.path}');
      return;
    }

    // Log file details
    log('Uploading Image to Telegram: ${imageFile.path}');
    log('Image Size: ${imageFile.lengthSync()} bytes');

    // Telegram Bot API endpoint for sending photos
    var uri = Uri.parse('https://api.telegram.org/bot$botToken/sendPhoto');
    var request = http.MultipartRequest('POST', uri)
      ..fields['chat_id'] = storageId
      ..files.add(await http.MultipartFile.fromPath('photo', imageFile.path));

    log('Request: $request');

    try {
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      log('Response Status Code: ${response.statusCode}');
      log('Response Body: $responseBody');

      if (response.statusCode == 200) {
        var fileUrl =
            jsonDecode(responseBody)['result']['photo'].last['file_id'];
        String? filePath = await getFilePath(fileUrl!);

        if (filePath == null) {
          log('Failed to get file path');
          return;
        }

        String? directUrl = getDirectFileUrl(filePath);
        if (directUrl == null) {
          log('Failed to get direct URL');
          return;
        }

        // Send the message with the image URL
        await sendGroupMessage(
          group: group,
          msg: directUrl,
          type: Type.image,
          localImgPath: imageFile.path,
          replyTo: replyTo,
        );
      } else {
        log('Failed to upload image to Telegram: ${response.statusCode}');
      }
    } catch (e) {
      log('Error uploading image to Telegram: $e');
    }
  }

  // Get all public groups
  static Future<List<Group>> getPublicGroups() async {
    try {
      log('Fetching public groups...');

      // Get all groups the user is already a member of
      final userGroupsSnapshot = await firestore
          .collection('users')
          .doc(APIs.user.uid)
          .collection('groups')
          .get();

      final userGroupIds =
          userGroupsSnapshot.docs.map((doc) => doc.id).toList();
      log('User is a member of ${userGroupIds.length} groups');

      // Get all public groups
      final publicGroupsSnapshot = await firestore
          .collection('groups')
          .where('is_public', isEqualTo: true)
          .get();

      log('Found ${publicGroupsSnapshot.docs.length} public groups in total');

      // Filter out groups the user is already a member of
      List<Group> publicGroups = [];
      for (var doc in publicGroupsSnapshot.docs) {
        final group = Group.fromJson(doc.data());
        if (!userGroupIds.contains(group.id)) {
          publicGroups.add(group);
        }
      }

      log('Found ${publicGroups.length} public groups that user is not a member of');

      // Sort by creation time (newest first)
      publicGroups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return publicGroups;
    } catch (e) {
      log('Error getting public groups: $e');
      return [];
    }
  }

  // Join a public group
  static Future<void> joinPublicGroup(Group group) async {
    try {
      // Check if the group is public
      if (!group.isPublic) {
        log('Cannot join a private group');
        throw Exception('This group is private');
      }

      final String time = DateTime.now().millisecondsSinceEpoch.toString();

      // Add user to group members
      final updatedMembers = [...group.members, APIs.user.uid];
      await firestore.collection('groups').doc(group.id).update({
        'members': updatedMembers,
      });

      // Add group reference to user's groups collection
      await firestore
          .collection('users')
          .doc(APIs.user.uid)
          .collection('groups')
          .doc(group.id)
          .set({'joined_at': time});

      // Send system message about user joining
      await sendGroupMessage(
        group: group,
        msg: '${APIs.me.name} joined the group',
        type: Type.text,
      );
    } catch (e) {
      log('Error joining public group: $e');
      rethrow; // Rethrow to allow proper error handling in UI
    }
  }

  // Get last message of a specific group
  /// Get a stream of the last message for a specific group.
  ///
  /// This method is used in conjunction with getAllGroups() and sortGroupsByLastMessage()
  /// to properly sort groups by their last message timestamps without requiring
  /// additional Firebase requests.
  ///
  /// @param groupId The ID of the group to get the last message for
  /// @return A stream of the last message document for the group
  static Stream<QuerySnapshot<Map<String, dynamic>>> getGroupLastMessage(
      String groupId) {
    return firestore
        .collection('group_chats/$groupId/messages/')
        .orderBy('sent', descending: true)
        .limit(1)
        .snapshots();
  }

  // Get real-time updates for a specific group
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getGroupUpdates(
      String groupId) {
    return firestore.collection('groups').doc(groupId).snapshots();
  }
}
