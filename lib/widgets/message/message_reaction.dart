import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/apis.dart';
import '../../models/chat_user.dart';
import '../../models/message.dart';

class MessageReaction {
  /// Builds a reaction bubble widget
  static Widget buildReactionBubble(
      List<String>? reactions, bool isMe, bool isDark,
      {Function()? onTap}) {
    if (reactions == null || reactions.isEmpty) return const SizedBox.shrink();

    // Count reactions by emoji
    Map<String, List<String>> reactionUsers = {};
    for (String reaction in reactions) {
      final parts = reaction.split(':');
      final userId = parts[0];
      final emoji = parts[1];
      if (!reactionUsers.containsKey(emoji)) {
        reactionUsers[emoji] = [];
      }
      reactionUsers[emoji]!.add(userId);
    }

    return GestureDetector(
      onTap: onTap ?? () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: reactionUsers.entries.map((entry) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.key,
                  style: const TextStyle(fontSize: 14),
                ),
                if (entry.value.length > 1) ...[
                  const SizedBox(width: 2),
                  Text(
                    entry.value.length.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Shows a bottom sheet with reaction details
  static void showReactionsDetailSheet(BuildContext context,
      Map<String, List<String>> reactionUsers, bool isDark, Message message) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[500] : Colors.grey[600];
    final currentUserId = APIs.user.uid;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    // Create a stream controller to manage user details
    final usersController = StreamController<Map<String, ChatUser>>();

    // Function to load user details
    void loadUserDetails(List<String> userIds) async {
      try {
        final usersSnapshot = await APIs.firestore
            .collection('users')
            .where('id', whereIn: userIds)
            .get();

        final Map<String, ChatUser> userMap = {};
        for (var doc in usersSnapshot.docs) {
          final user = ChatUser.fromJson(doc.data());
          userMap[user.id] = user;
        }

        if (!usersController.isClosed) {
          usersController.add(userMap);
        }
      } catch (e) {
        log('Error loading user details: $e');
        if (!usersController.isClosed) {
          usersController.add({});
        }
      }
    }

    // Get all unique user IDs
    final allUserIds = reactionUsers.values.expand((x) => x).toSet().toList();

    // Create tabs for reactions
    final List<String> tabs = ['All', ...reactionUsers.keys];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        // Selected tab value notifier
        final selectedTab = ValueNotifier<String>(tabs[0]);

        // Load user details when sheet opens
        loadUserDetails(allUserIds);

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Reactions',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Tabs
              Container(
                height: 40,
                margin: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ValueListenableBuilder<String>(
                    valueListenable: selectedTab,
                    builder: (context, selected, _) {
                      return Row(
                        children: tabs.map((tab) {
                          final isSelected = selected == tab;
                          final count = tab == 'All'
                              ? reactionUsers.values.expand((x) => x).length
                              : reactionUsers[tab]?.length ?? 0;
                          return GestureDetector(
                            onTap: () => selectedTab.value = tab,
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isDark
                                        ? Colors.white10
                                        : Colors.black.withOpacity(0.1))
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.transparent
                                      : isDark
                                          ? Colors.white24
                                          : Colors.black12,
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (tab != 'All')
                                    Text(
                                      tab,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  if (tab != 'All') const SizedBox(width: 4),
                                  Text(
                                    tab == 'All'
                                        ? 'All ($count)'
                                        : count.toString(),
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ),
              // User list with profile pictures
              Expanded(
                child: StreamBuilder<Map<String, ChatUser>>(
                  stream: usersController.stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final userMap = snapshot.data ?? {};

                    return ValueListenableBuilder<String>(
                      valueListenable: selectedTab,
                      builder: (context, selected, _) {
                        final List<String> filteredUsers;
                        if (selected == 'All') {
                          filteredUsers =
                              reactionUsers.values.expand((x) => x).toList();
                        } else {
                          filteredUsers = reactionUsers[selected] ?? [];
                        }

                        if (filteredUsers.isEmpty) {
                          return Center(
                            child: Text(
                              'No reactions yet',
                              style: TextStyle(color: subtitleColor),
                            ),
                          );
                        }

                        // Sort the users list to put current user first
                        filteredUsers.sort((a, b) {
                          if (a == currentUserId) return -1;
                          if (b == currentUserId) return 1;
                          return 0;
                        });

                        return ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: filteredUsers.length,
                          itemBuilder: (context, index) {
                            final userId = filteredUsers[index];
                            final user = userMap[userId];
                            final isCurrentUser = userId == currentUserId;
                            final emoji = selected == 'All'
                                ? reactionUsers.entries
                                    .firstWhere(
                                        (entry) => entry.value.contains(userId))
                                    .key
                                : selected;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[200],
                                child: user?.image != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: CachedNetworkImage(
                                          imageUrl: user!.image,
                                          fit: BoxFit.cover,
                                          width: 40,
                                          height: 40,
                                          placeholder: (context, url) =>
                                              const CircularProgressIndicator(
                                                  strokeWidth: 2),
                                          errorWidget: (context, url, error) =>
                                              Icon(
                                            Icons.person,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black54,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.person,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black54,
                                      ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isCurrentUser
                                              ? 'You'
                                              : (user?.name ?? 'Unknown User'),
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: isCurrentUser
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        if (user?.about != null &&
                                            user!.about.isNotEmpty)
                                          Text(
                                            user.about,
                                            style: TextStyle(
                                              color: subtitleColor,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  if (userId == currentUserId) ...[
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () async {
                                        Navigator.pop(context);
                                        try {
                                          final result =
                                              await InternetAddress.lookup(
                                                  'google.com');
                                          if (result.isNotEmpty &&
                                              result[0].rawAddress.isNotEmpty) {
                                            // Get the conversation ID using the other user's ID
                                            final otherUserId =
                                                message.fromId == APIs.user.uid
                                                    ? message.toId
                                                    : message.fromId;
                                            final conversationId =
                                                APIs.getConversationID(
                                                    otherUserId);

                                            // Get the message document using the correct path
                                            final messageDoc = await APIs
                                                .firestore
                                                .collection(
                                                    'chats/$conversationId/messages')
                                                .doc(message.sent)
                                                .get();

                                            if (!messageDoc.exists) return;

                                            List<String> reactions =
                                                List<String>.from(
                                                    messageDoc.data()?[
                                                                'reactions']
                                                            as List<dynamic>? ??
                                                        []);

                                            // Remove the user's reaction
                                            reactions.removeWhere((reaction) =>
                                                reaction
                                                    .startsWith('$userId:'));

                                            // Update the message with new reactions
                                            await messageDoc.reference.update(
                                                {'reactions': reactions});
                                          }
                                        } catch (e) {
                                          print('Error removing reaction: $e');
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.grey[800]
                                              : Colors.grey[200],
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      // Ensure the controller is closed when the sheet is dismissed
      if (!usersController.isClosed) {
        usersController.close();
      }
    });
  }

  /// Handle adding or removing a reaction
  static Future<void> handleCustomReaction(
      String messageId, bool isMe, String emoji) async {
    try {
      final currentUserId = APIs.user.uid;

      // Get the message document using the correct path
      final messageDoc = await APIs.firestore
          .collection('chats')
          .doc(messageId)
          .collection('messages')
          .doc(messageId)
          .get();

      if (!messageDoc.exists) {
        log('Message document does not exist');
        return;
      }

      // Get the other user's ID from the message document
      final Map<String, dynamic> data =
          messageDoc.data() as Map<String, dynamic>;
      final String fromId = data['fromId'] as String;
      final String toId = data['toId'] as String;
      final String otherUserId = fromId == currentUserId ? toId : fromId;

      // Get the correct conversation ID
      final String conversationId = APIs.getConversationID(otherUserId);

      // Now get the message document from the correct path
      final correctMessageDoc = await APIs.firestore
          .collection('chats/$conversationId/messages')
          .doc(messageId)
          .get();

      if (!correctMessageDoc.exists) {
        log('Message document not found in the correct path');
        return;
      }

      List<String> reactions = List<String>.from(
          correctMessageDoc.data()?['reactions'] as List<dynamic>? ?? []);

      // Check if the reaction already exists
      final existingReaction = '$currentUserId:$emoji';
      final hasReaction = reactions.contains(existingReaction);

      if (hasReaction) {
        reactions.remove(existingReaction);
      } else {
        // Remove any existing reaction from this user
        reactions
            .removeWhere((reaction) => reaction.startsWith('$currentUserId:'));
        // Add the new reaction
        reactions.add(existingReaction);
      }

      // Update the message with new reactions
      await correctMessageDoc.reference.update({'reactions': reactions});
    } catch (e) {
      log('Error handling reaction: $e');
      // You might want to add error handling here
      // For example, showing a snackbar or toast message
    }
  }
}
