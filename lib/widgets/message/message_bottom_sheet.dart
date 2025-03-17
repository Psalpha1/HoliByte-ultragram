import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import '../../api/apis.dart';
import '../../helper/dialogs.dart';
import '../../models/chat_user.dart';
import '../../models/message.dart';

// Custom painter for the menu arrow pointing down
class MenuArrowPainter extends CustomPainter {
  final bool isUpward;
  final Color color;

  MenuArrowPainter(
      {this.isUpward = false, this.color = const Color(0xFF2A2A2A)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isUpward) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MenuArrowPainter oldDelegate) =>
      isUpward != oldDelegate.isUpward || color != oldDelegate.color;
}

class MessageBottomSheet {
  static OverlayEntry? _overlayEntry;

  static const _reactions = [
    {'emoji': '❤️', 'label': 'Love'},
    {'emoji': '😂', 'label': 'Haha'},
    {'emoji': '😮', 'label': 'Wow'},
    {'emoji': '😢', 'label': 'Sad'},
    {'emoji': '😡', 'label': 'Angry'},
    {'emoji': '👍', 'label': 'Like'},
  ];

  /// Show custom floating menu with message options
  static void showBottomSheet(
    BuildContext context,
    Message message,
    bool isMe,
    Function(Message)? onReplyTap, {
    required BuildContext bubbleContext,
    Offset? position,
  }) {
    try {
      // Close any existing overlay
      _overlayEntry?.remove();
      _overlayEntry = null;

      // Get the overlay state
      final overlay = Overlay.of(context);

      // Get the message bubble's position and size
      final RenderBox bubbleBox = bubbleContext.findRenderObject() as RenderBox;
      final bubblePosition = bubbleBox.localToGlobal(Offset.zero);
      final bubbleSize = bubbleBox.size;

      // Calculate position that keeps menu within screen bounds
      final size = MediaQuery.of(context).size;
      final menuWidth = 200.0; // Fixed width for a more compact menu
      final menuHeight = 280.0; // Approximate height based on content

      // Calculate emoji menu dimensions
      final emojiMenuHeight = 52.0;
      final emojiMenuWidth = 280.0;
      final emojiMenuGap = 8.0;

      // Position the menu below the bubble
      double left = isMe
          ? bubblePosition.dx +
              bubbleSize.width -
              menuWidth // Align to right edge for sender's messages
          : bubblePosition.dx; // Align to left edge for receiver's messages
      double top = bubblePosition.dy +
          bubbleSize.height +
          4; // 4dp gap between bubble and menu

      // Calculate emoji menu position
      double emojiLeft =
          bubblePosition.dx + (bubbleSize.width - emojiMenuWidth) / 2;
      double emojiTop = bubblePosition.dy - emojiMenuHeight - emojiMenuGap;

      // Adjust emoji menu position to keep within screen bounds
      if (emojiLeft < 8) emojiLeft = 8;
      if (emojiLeft + emojiMenuWidth > size.width - 8) {
        emojiLeft = size.width - emojiMenuWidth - 8;
      }

      // Check if menu needs to be moved above
      bool showMenuAbove = false;
      if (top + menuHeight > size.height - 8) {
        showMenuAbove = true;
        top = bubblePosition.dy - menuHeight - 4;
        // Move emoji menu above the options menu
        emojiTop = top - emojiMenuHeight - emojiMenuGap;
      }

      // Ensure emoji menu doesn't go off the top of the screen
      if (emojiTop < 8) {
        emojiTop = bubblePosition.dy + bubbleSize.height + emojiMenuGap;
      }

      // Adjust menu left position to keep within screen bounds
      if (left + menuWidth > size.width) {
        left = size.width - menuWidth - 8;
      }
      if (left < 8) left = 8;

      _overlayEntry = OverlayEntry(
        builder: (context) => Stack(
          children: [
            // Backdrop for closing menu
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _overlayEntry?.remove();
                  _overlayEntry = null;
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            // Emoji reaction menu
            Positioned(
              left: emojiLeft,
              top: emojiTop,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0.8, end: 1.0),
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Container(
                    height: emojiMenuHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _reactions.map((reaction) {
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              _overlayEntry?.remove();
                              _overlayEntry = null;
                              _handleCustomReaction(
                                  message, isMe, reaction['emoji']!);
                            },
                            child: Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              child: Text(
                                reaction['emoji']!,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            // Options menu
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0.8, end: 1.0),
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Container(
                    width: menuWidth,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Add arrow at appropriate position
                        if (!showMenuAbove)
                          Transform.translate(
                            offset: Offset(
                              isMe ? menuWidth - 24 : 12,
                              -6,
                            ),
                            child: CustomPaint(
                              painter: MenuArrowPainter(),
                              size: const Size(12, 6),
                            ),
                          ),
                        _buildOption(
                          icon: Icons.reply_outlined,
                          label: 'Reply',
                          onTap: () {
                            _overlayEntry?.remove();
                            _overlayEntry = null;
                            if (onReplyTap != null) onReplyTap(message);
                          },
                        ),
                        if (message.type == Type.text && isMe)
                          _buildOption(
                            icon: Icons.edit_outlined,
                            label: 'Edit',
                            onTap: () {
                              _overlayEntry?.remove();
                              _overlayEntry = null;
                              _showMessageUpdateDialog(context, message);
                            },
                          ),
                        _buildOption(
                          icon: Icons.forward,
                          label: 'Forward',
                          onTap: () {
                            _overlayEntry?.remove();
                            _overlayEntry = null;
                            showForwardDialog(context, message);
                          },
                        ),
                        if (message.type == Type.text)
                          _buildOption(
                            icon: Icons.content_copy_outlined,
                            label: 'Copy',
                            onTap: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: message.msg));
                              _overlayEntry?.remove();
                              _overlayEntry = null;
                              Dialogs.showSnackbar(
                                  context, 'Text copied to clipboard');
                            },
                          ),
                        _buildOption(
                          icon: Icons.translate,
                          label: 'Show translation',
                          onTap: () {
                            _overlayEntry?.remove();
                            _overlayEntry = null;
                            Dialogs.showComingSoon(
                                context, 'Translation feature');
                          },
                        ),
                        if (isMe)
                          _buildOption(
                            icon: Icons.delete_outline,
                            label: 'Unsend',
                            onTap: () async {
                              await APIs.deleteMessage(message);
                              _overlayEntry?.remove();
                              _overlayEntry = null;
                            },
                            isDestructive: true,
                          ),
                        if (!isMe)
                          _buildOption(
                            icon: Icons.more_horiz,
                            label: 'More',
                            onTap: () {
                              _overlayEntry?.remove();
                              _overlayEntry = null;
                              // Show additional options
                            },
                          ),
                        if (showMenuAbove)
                          Transform.translate(
                            offset: Offset(
                              isMe ? menuWidth - 24 : 12,
                              0,
                            ),
                            child: CustomPaint(
                              painter: MenuArrowPainter(isUpward: true),
                              size: const Size(12, 6),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      // Insert the overlay entry
      overlay.insert(_overlayEntry!);
    } catch (e) {
      log('Error showing message options: $e');
      // Handle the error gracefully
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
  }

  static Widget _buildOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? Colors.redAccent : Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isDestructive ? Colors.redAccent : Colors.white,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Handle custom reaction
  static Future<void> _handleCustomReaction(
      Message message, bool isMe, String emoji) async {
    try {
      final currentUserId = APIs.user.uid;
      Set<String> reactions = message.reactions.toSet();

      // Toggle the reaction
      if (reactions.contains('$currentUserId:$emoji')) {
        reactions.remove('$currentUserId:$emoji');
      } else {
        // Remove any existing reaction from this user
        reactions
            .removeWhere((reaction) => reaction.startsWith('$currentUserId:'));
        // Add the new reaction
        reactions.add('$currentUserId:$emoji');
      }

      await APIs.updateMessageReactions(message, reactions.toList());
    } catch (e) {
      log('Error handling reaction: $e');
    }
  }

  // Dialog for updating message content
  static void _showMessageUpdateDialog(
      final BuildContext context, Message message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final TextEditingController editController =
        TextEditingController(text: message.msg);

    // Theme-adaptive colors
    final backgroundColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final inputBackgroundColor = isDark ? Colors.grey[900] : Colors.grey[100];
    final hintColor = isDark ? Colors.grey[500] : Colors.grey[600];
    final buttonColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dialog title
              Text(
                'Edit Message',
                style: TextStyle(
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Text field for editing
              TextField(
                controller: editController,
                maxLines: null,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputBackgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                  hintText: 'Enter your message',
                  hintStyle: TextStyle(color: hintColor),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Cancel button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: hintColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),

                  // Update button
                  TextButton(
                    onPressed: () {
                      APIs.updateMessage(message, editController.text.trim());
                      Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: buttonColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    child: const Text('Update'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show forward dialog
  static void showForwardDialog(BuildContext context, Message message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[500] : Colors.grey[600];

    // Create a stream controller to manage users
    final usersController = StreamController<List<ChatUser>>();

    // Function to load users once
    void loadUsers() async {
      try {
        final snapshot = await APIs.firestore
            .collection('users')
            .doc(APIs.user.uid)
            .collection('my_users')
            .get();

        if (snapshot.docs.isNotEmpty) {
          final userIds = snapshot.docs.map((e) => e.id).toList();
          final usersSnapshot = await APIs.firestore
              .collection('users')
              .where('id', whereIn: userIds)
              .get();

          final users = usersSnapshot.docs
              .map((e) => ChatUser.fromJson(e.data()))
              .toList();

          if (!usersController.isClosed) {
            usersController.add(users);
          }
        } else {
          if (!usersController.isClosed) {
            usersController.add([]);
          }
        }
      } catch (e) {
        log('Error loading users: $e');
        if (!usersController.isClosed) {
          usersController.add([]);
        }
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        // Load users when dialog opens
        loadUsers();

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle indicator
              Container(
                margin: const EdgeInsets.only(top: 10),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.forward,
                      color: textColor,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Forward to...',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        usersController.close();
                        Navigator.pop(ctx);
                      },
                      icon: Icon(
                        Icons.close,
                        color: subtitleColor,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // User list
              Expanded(
                child: StreamBuilder<List<ChatUser>>(
                  stream: usersController.stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Text(
                          'No users found!',
                          style: TextStyle(color: textColor),
                        ),
                      );
                    }

                    final users = snapshot.data!;
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8),
                      physics: const BouncingScrollPhysics(),
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        return _buildUserItem(
                          context,
                          users[index],
                          message,
                          isDark,
                          textColor,
                          subtitleColor,
                          onForwardComplete: () {
                            usersController.close();
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
      // Ensure the controller is closed when the dialog is dismissed
      if (!usersController.isClosed) {
        usersController.close();
      }
    });
  }

  // Helper method to build user item in forward dialog
  static Widget _buildUserItem(
    BuildContext context,
    ChatUser user,
    Message message,
    bool isDark,
    Color textColor,
    Color? subtitleColor, {
    VoidCallback? onForwardComplete,
  }) {
    return InkWell(
      onTap: () async {
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        final theme = Theme.of(context);
        Navigator.pop(context);

        try {
          OverlayEntry? loadingOverlay;
          loadingOverlay = OverlayEntry(
            builder: (context) => Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(
                  color: isDark ? Colors.white : theme.primaryColor,
                ),
              ),
            ),
          );

          Overlay.of(context).insert(loadingOverlay);

          // Forward the message with forwarded flag set to true
          if (message.type == Type.text) {
            await APIs.sendMessage(
              user,
              message.msg,
              message.type,
              forwarded: true,
            );
          } else if (message.type == Type.image) {
            await APIs.sendMessage(
              user,
              message.msg,
              message.type,
              forwarded: true,
            );
          } else if (message.type == Type.file) {
            await APIs.sendMessage(
              user,
              message.msg,
              message.type,
              fileName: message.fileName,
              fileSize: message.fileSize,
              fileType: message.fileType,
              forwarded: true,
            );
          }

          loadingOverlay.remove();
          onForwardComplete?.call();

          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Message forwarded to ${user.name}'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } catch (e) {
          log('Error forwarding message: $e');
          onForwardComplete?.call();
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Failed to forward message'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // User avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
              child: user.image.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(
                        imageUrl: user.image,
                        fit: BoxFit.cover,
                        width: 40,
                        height: 40,
                        placeholder: (context, url) =>
                            const CircularProgressIndicator(strokeWidth: 2),
                        errorWidget: (context, url, error) => Icon(
                          Icons.person,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.person,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
            ),
            const SizedBox(width: 12),
            // User name and email
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
