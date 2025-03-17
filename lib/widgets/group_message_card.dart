import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/apis.dart';
import '../helper/my_date_util.dart';
import '../main.dart';
import '../models/group_message.dart';
import '../models/message.dart';
import '../models/chat_user.dart';
import 'message/date_separator.dart';
import 'message/message_components.dart';
import 'profile_image.dart';

// Custom painter for the menu arrow pointing up or down
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

/// For showing single group message details
class GroupMessageCard extends StatefulWidget {
  const GroupMessageCard({
    super.key,
    required this.message,
    this.onReplyTap,
    this.showDateSeparator = false,
  });

  final GroupMessage message;
  final Function(GroupMessage)? onReplyTap;
  final bool showDateSeparator;

  @override
  State<GroupMessageCard> createState() => _GroupMessageCardState();
}

class _GroupMessageCardState extends State<GroupMessageCard> {
  static OverlayEntry? _overlayEntry;

  // Reactions list
  static const _reactions = [
    {'emoji': '❤️', 'label': 'Love'},
    {'emoji': '😂', 'label': 'Haha'},
    {'emoji': '😮', 'label': 'Wow'},
    {'emoji': '😢', 'label': 'Sad'},
    {'emoji': '😡', 'label': 'Angry'},
    {'emoji': '👍', 'label': 'Like'},
  ];

  @override
  Widget build(BuildContext context) {
    bool isMe = APIs.user.uid == widget.message.fromId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        if (widget.showDateSeparator)
          DateSeparator(
            date: MyDateUtil.getMessageDate(
                context: context, time: widget.message.sent),
            isDark: isDark,
          ),
        Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            isMe ? _greenMessage() : _blueMessage(),
          ],
        ),
      ],
    );
  }

  // Method for sending user's messages (green bubbles)
  Widget _greenMessage() {
    bool isMe = true;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildMessageContent(isMe),
          ],
        ),
      ],
    );
  }

  // Method for received messages (blue bubbles)
  Widget _blueMessage() {
    bool isMe = false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sender's profile picture
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: ProfileImage(
            url: widget.message.senderImage,
            size: 30,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender's name
            Padding(
              padding: EdgeInsets.only(left: mq.width * .04),
              child: Text(
                widget.message.senderName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            _buildMessageContent(isMe),
          ],
        ),
      ],
    );
  }

  // Method to handle reactions
  void _handleReaction(bool isMe, String emoji) async {
    final currentUserId = APIs.user.uid;
    final messageId = widget.message.sent;
    final groupId = widget.message.toId;

    // Optimistically update the UI
    setState(() {
      if (widget.message.reactions.contains('$currentUserId:$emoji')) {
        widget.message.reactions.remove('$currentUserId:$emoji');
      } else {
        // Remove any existing reaction from this user
        widget.message.reactions
            .removeWhere((reaction) => reaction.startsWith('$currentUserId:'));
        // Add the new reaction
        widget.message.reactions.add('$currentUserId:$emoji');
      }
    });

    try {
      // Update directly in Firestore
      final messageDoc = await APIs.firestore
          .collection('group_chats/$groupId/messages')
          .doc(messageId)
          .get();

      if (!messageDoc.exists) {
        return;
      }

      List<String> reactions = List<String>.from(
          messageDoc.data()?['reactions'] as List<dynamic>? ?? []);

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
      await messageDoc.reference.update({'reactions': reactions});
    } catch (e) {
      // Revert the optimistic update if there was an error
      setState(() {
        widget.message.reactions = List<String>.from(widget.message.reactions
            .where((r) => !r.startsWith('$currentUserId:')));
      });
    }
  }

  // Show floating menu options and emoji reactions
  void _showFloatingMenu(bool isMe, BuildContext bubbleContext) {
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
                              _handleReaction(isMe, reaction['emoji']!);
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
                            if (widget.onReplyTap != null) {
                              widget.onReplyTap!(widget.message);
                            }
                          },
                        ),
                        if (widget.message.type == Type.text && isMe)
                          _buildOption(
                            icon: Icons.edit_outlined,
                            label: 'Edit',
                            onTap: () {
                              _overlayEntry?.remove();
                              _overlayEntry = null;
                              _showMessageUpdateDialog();
                            },
                          ),
                        _buildOption(
                          icon: Icons.forward,
                          label: 'Forward',
                          onTap: () {
                            _overlayEntry?.remove();
                            _overlayEntry = null;
                            _showForwardDialog(context);
                          },
                        ),
                        if (widget.message.type == Type.text)
                          _buildOption(
                            icon: Icons.content_copy_outlined,
                            label: 'Copy',
                            onTap: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: widget.message.msg));
                              _overlayEntry?.remove();
                              _overlayEntry = null;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Text copied to clipboard'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        _buildOption(
                          icon: Icons.translate,
                          label: 'Translate',
                          onTap: () {
                            _overlayEntry?.remove();
                            _overlayEntry = null;
                            // Implement translation
                          },
                        ),
                        if (isMe)
                          _buildOption(
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            onTap: () async {
                              _overlayEntry?.remove();
                              _overlayEntry = null;
                              _confirmDeleteMessage();
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
      print('Error showing message options: $e');
      // Handle the error gracefully
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
  }

  Widget _buildOption({
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

  // Dialog for updating message content
  void _showMessageUpdateDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final TextEditingController editController =
        TextEditingController(text: widget.message.msg);

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
                      _updateMessage(editController.text.trim());
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

  // Method to update a message
  void _updateMessage(String newText) async {
    try {
      await APIs.firestore
          .collection('group_chats/${widget.message.toId}/messages')
          .doc(widget.message.sent)
          .update({'msg': newText});

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message updated successfully!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update message!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Confirm delete dialog
  void _confirmDeleteMessage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: backgroundColor,
        title: Text(
          'Delete Message',
          style: TextStyle(color: textColor),
        ),
        content: Text(
          'Are you sure you want to delete this message?',
          style: TextStyle(color: textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Method to delete a message
  void _deleteMessage() async {
    try {
      await APIs.firestore
          .collection('group_chats/${widget.message.toId}/messages')
          .doc(widget.message.sent)
          .delete();

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted successfully!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete message!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Build the message content based on message type
  Widget _buildMessageContent(bool isMe) {
    final type = widget.message.type;

    // Create dismissible wrapper for swipe to reply
    Widget contentWidget = _createDismissibleWrapper(
      isMe: isMe,
      child: _getMessageByType(isMe, type),
    );

    return contentWidget;
  }

  // Create dismissible wrapper for swipe to reply
  Widget _createDismissibleWrapper(
      {required bool isMe, required Widget child}) {
    return Dismissible(
      key: Key('dismissible_${widget.message.sent}'),
      direction:
          isMe ? DismissDirection.endToStart : DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        if (widget.onReplyTap != null) {
          widget.onReplyTap!(widget.message);
        }
        return false;
      },
      background: Container(
        padding: EdgeInsets.symmetric(horizontal: mq.width * .04),
        color: Colors.transparent,
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: const Icon(
          Icons.reply_rounded,
          color: Colors.blue,
          size: 26,
        ),
      ),
      child: child,
    );
  }

  // Get the appropriate message widget based on type
  Widget _getMessageByType(bool isMe, Type type) {
    // Use Builder to get a context that can find the message's RenderObject
    return Builder(builder: (bubbleContext) {
      Widget content;

      switch (type) {
        case Type.text:
          content = MessageComponents.buildTextMessage(
            context: context,
            message: widget.message,
            isMe: isMe,
            onLongPress: (_) => _showFloatingMenu(isMe, bubbleContext),
            onDoubleTap: (_) => _handleReaction(isMe, '❤️'),
            replyTo: widget.message.replyTo,
            forwarded: widget.message.forwarded,
          );
          break;
        case Type.image:
          content = MessageComponents.buildImageMessage(
            context: context,
            message: widget.message,
            isMe: isMe,
            onLongPress: (_) => _showFloatingMenu(isMe, bubbleContext),
            onDoubleTap: (_) => _handleReaction(isMe, '❤️'),
            replyTo: widget.message.replyTo,
            forwarded: widget.message.forwarded,
          );
          break;
        case Type.video:
          content = MessageComponents.buildVideoMessage(
            context: context,
            message: widget.message,
            isMe: isMe,
            onLongPress: (_) => _showFloatingMenu(isMe, bubbleContext),
            onDoubleTap: (_) => _handleReaction(isMe, '❤️'),
            replyTo: widget.message.replyTo,
            forwarded: widget.message.forwarded,
          );
          break;
        case Type.file:
          content = MessageComponents.buildFileMessage(
            context: context,
            message: widget.message,
            isMe: isMe,
            onLongPress: (_) => _showFloatingMenu(isMe, bubbleContext),
            onDoubleTap: (_) => _handleReaction(isMe, '❤️'),
            replyTo: widget.message.replyTo,
            forwarded: widget.message.forwarded,
          );
          break;
        case Type.audio:
          content = MessageComponents.buildVoiceMessage(
            context: context,
            message: widget.message,
            isMe: isMe,
            onLongPress: (_) => _showFloatingMenu(isMe, bubbleContext),
            onDoubleTap: (_) => _handleReaction(isMe, '❤️'),
            replyTo: widget.message.replyTo,
            forwarded: widget.message.forwarded,
          );
          break;
        default:
          content = MessageComponents.buildTextMessage(
            context: context,
            message: widget.message,
            isMe: isMe,
            onLongPress: (_) => _showFloatingMenu(isMe, bubbleContext),
            onDoubleTap: (_) => _handleReaction(isMe, '❤️'),
            replyTo: widget.message.replyTo,
            forwarded: widget.message.forwarded,
          );
      }

      return content;
    });
  }

  // Show forward dialog for group messages
  void _showForwardDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[500] : Colors.grey[600];

    // Check if user is authenticated
    if (APIs.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to forward messages'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Create a stream controller to manage users
    final usersController = StreamController<List<ChatUser>>();

    // Function to load users once
    void loadUsers() async {
      try {
        final currentUser = APIs.auth.currentUser;
        if (currentUser == null) {
          usersController.add([]);
          return;
        }

        final snapshot = await APIs.firestore
            .collection('users')
            .doc(currentUser.uid)
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
                        return _buildUserForwardItem(
                          context,
                          users[index],
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
    );
  }

  // Build user item for forward dialog
  Widget _buildUserForwardItem(
    BuildContext context,
    ChatUser user,
    bool isDark,
    Color textColor,
    Color? subtitleColor, {
    VoidCallback? onForwardComplete,
  }) {
    return InkWell(
      onTap: () async {
        // Check if user is still authenticated
        if (APIs.auth.currentUser == null) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in to forward messages'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        Navigator.pop(context);
        final scaffoldMessenger = ScaffoldMessenger.of(context);

        // Show loading overlay
        final loadingOverlay = OverlayEntry(
          builder: (context) => Container(
            color: Colors.black.withOpacity(0.5),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
        Overlay.of(context).insert(loadingOverlay);

        try {
          // Make sure user.id is not null
          if (user.id.isEmpty) {
            throw Exception("User ID is empty");
          }

          // Forward the message based on type
          if (widget.message.type == Type.text) {
            // Make sure message text is not null
            String messageText =
                widget.message.msg.isNotEmpty ? widget.message.msg : "";

            await APIs.sendMessage(
              user,
              messageText,
              widget.message.type,
              forwarded: true,
            );
          } else if (widget.message.type == Type.image) {
            // Make sure image URL is not null
            String imageUrl =
                widget.message.msg.isNotEmpty ? widget.message.msg : "";

            await APIs.sendMessage(
              user,
              imageUrl,
              widget.message.type,
              forwarded: true,
            );
          } else if (widget.message.type == Type.file) {
            // Make sure file URL is not null
            String fileUrl =
                widget.message.msg.isNotEmpty ? widget.message.msg : "";
            String fileName = widget.message.fileName ?? "";
            int? fileSize = widget.message.fileSize;
            String? fileType = widget.message.fileType;

            await APIs.sendMessage(
              user,
              fileUrl,
              widget.message.type,
              fileName: fileName,
              fileSize: fileSize,
              fileType: fileType,
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
          loadingOverlay.remove();
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Failed to forward message: ${e.toString()}'),
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
                            const CircularProgressIndicator(),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.person),
                      ),
                    )
                  : const Icon(Icons.person),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  if (user.about.isNotEmpty)
                    Text(
                      user.about,
                      style: TextStyle(
                        fontSize: 14,
                        color: subtitleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
