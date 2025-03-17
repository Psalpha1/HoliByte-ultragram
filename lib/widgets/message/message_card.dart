import 'package:flutter/material.dart';
import '../../api/apis.dart';
import '../../helper/my_date_util.dart';
import '../../main.dart';
import '../../models/message.dart';
import 'date_separator.dart';
import 'message_bottom_sheet.dart';
import 'message_components.dart';
import 'dart:developer';

/// For showing single message details
class MessageCard extends StatefulWidget {
  const MessageCard({
    super.key,
    required this.message,
    this.onReplyTap,
    this.showDateSeparator = false,
  });

  final Message message;
  final Function(Message)? onReplyTap;
  final bool showDateSeparator;

  @override
  State<MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<MessageCard> {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Mark as read if not already
    if (widget.message.read.isEmpty) {
      APIs.updateMessageReadStatus(widget.message);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMessageContent(isMe),
          ],
        ),
      ],
    );
  }

  // Method to handle reactions
  void _handleReaction(bool isMe) async {
    final currentUserId = APIs.user.uid;
    final messageId = widget.message.sent;
    final emoji = '❤️';
    final otherUserId = widget.message.fromId == currentUserId
        ? widget.message.toId
        : widget.message.fromId;
    final conversationId = APIs.getConversationID(otherUserId);

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
          .collection('chats/$conversationId/messages')
          .doc(messageId)
          .get();

      if (!messageDoc.exists) {
        log('Message document not found');
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
      log('Error updating reaction: $e');
      // Revert the optimistic update if there was an error
      setState(() {
        widget.message.reactions = List<String>.from(widget.message.reactions
            .where((r) => !r.startsWith('$currentUserId:')));
      });
    }
  }

  // Method to show bottom sheet
  void _showBottomSheet(bool isMe) {
    MessageBottomSheet.showBottomSheet(
      context,
      widget.message,
      isMe,
      widget.onReplyTap,
      bubbleContext: context, // Pass the bubble's context
    );
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

  // Get the appropriate message widget based on type
  Widget _getMessageByType(bool isMe, Type type) {
    switch (type) {
      case Type.text:
        return MessageComponents.buildTextMessage(
          context: context,
          message: widget.message,
          isMe: isMe,
          onLongPress: _showBottomSheet,
          onDoubleTap: _handleReaction,
          replyTo: widget.message.replyTo,
          forwarded: widget.message.forwarded,
        );

      case Type.image:
        return MessageComponents.buildImageMessage(
          context: context,
          message: widget.message,
          isMe: isMe,
          onLongPress: _showBottomSheet,
          onDoubleTap: _handleReaction,
          replyTo: widget.message.replyTo,
          forwarded: widget.message.forwarded,
        );

      case Type.video:
        return MessageComponents.buildVideoMessage(
          context: context,
          message: widget.message,
          isMe: isMe,
          onLongPress: _showBottomSheet,
          onDoubleTap: _handleReaction,
          replyTo: widget.message.replyTo,
          forwarded: widget.message.forwarded,
        );

      case Type.file:
        return MessageComponents.buildFileMessage(
          context: context,
          message: widget.message,
          isMe: isMe,
          onLongPress: _showBottomSheet,
          onDoubleTap: _handleReaction,
          replyTo: widget.message.replyTo,
          forwarded: widget.message.forwarded,
        );

      case Type.audio:
        return MessageComponents.buildVoiceMessage(
          context: context,
          message: widget.message,
          isMe: isMe,
          onLongPress: _showBottomSheet,
          onDoubleTap: _handleReaction,
          replyTo: widget.message.replyTo,
          forwarded: widget.message.forwarded,
        );

      default:
        return const SizedBox(); // Fallback
    }
  }

  // Create a dismissible wrapper for swipe to reply functionality
  Widget _createDismissibleWrapper(
      {required bool isMe, required Widget child}) {
    // Only add dismissible if reply functionality is provided
    if (widget.onReplyTap == null) return child;

    return Dismissible(
      key: Key(widget.message.sent),
      direction:
          isMe ? DismissDirection.endToStart : DismissDirection.startToEnd,
      dismissThresholds: const {
        DismissDirection.endToStart: 0.4,
        DismissDirection.startToEnd: 0.4,
      },
      // Add smooth resizing animation
      resizeDuration: const Duration(milliseconds: 150),
      // Add more natural movement curve for the animation
      movementDuration: const Duration(milliseconds: 200),
      // Use a custom curve for more natural feel
      behavior: HitTestBehavior.opaque,
      // This controls the behavior when drag ends - makes it more smooth
      onResize: () {},
      onUpdate: (details) {
        // This helps make the animation feel more responsive
      },
      confirmDismiss: (direction) async {
        // Perform the reply action
        if (widget.onReplyTap != null) {
          widget.onReplyTap!(widget.message);
        }
        // Reduced delay for more responsive feel
        await Future.delayed(const Duration(milliseconds: 100));
        return false; // Always return to original position
      },
      background: Container(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        padding: EdgeInsets.only(
            right: isMe ? mq.width * .08 : 0, left: isMe ? 0 : mq.width * .08),
        child: TweenAnimationBuilder(
          duration: const Duration(milliseconds: 150),
          tween: Tween<double>(begin: 0.9, end: 1.0),
          curve: Curves.easeOut,
          builder: (context, double value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isMe ? Colors.green : Colors.blue).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.reply_rounded,
                  color: isMe ? Colors.green : Colors.blue,
                  size: 20,
                ),
              ),
            );
          },
        ),
      ),
      child: child,
    );
  }
}
