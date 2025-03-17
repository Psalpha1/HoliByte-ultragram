import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/message.dart';
import '../../main.dart';
import '../../helper/my_date_util.dart';
import 'message_image_viewer.dart';
import 'message_reaction.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer';
import '../../widgets/voice_message_player.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class MessageComponents {
  /// Build a text message container
  static Widget buildTextMessage({
    required BuildContext context,
    required Message message,
    required bool isMe,
    required Function(bool) onLongPress,
    required Function(bool) onDoubleTap,
    String? replyTo,
    bool forwarded = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (replyTo != null)
          Container(
            margin: EdgeInsets.only(
              left: isMe ? 0 : mq.width * .04,
              right: isMe ? mq.width * .04 : 0,
              bottom: 2,
            ),
            constraints: BoxConstraints(maxWidth: mq.width * .7),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe
                  ? (isDark
                      ? Colors.green.withOpacity(0.2)
                      : const Color.fromARGB(255, 218, 255, 176)
                          .withOpacity(0.5))
                  : (isDark
                      ? Colors.blue.withOpacity(0.2)
                      : const Color.fromARGB(255, 221, 245, 255)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 12),
              ),
              border: Border.all(
                color: isMe
                    ? (isDark
                        ? Colors.green.withOpacity(0.3)
                        : Colors.lightGreen.withOpacity(0.3))
                    : (isDark
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.lightBlue.withOpacity(0.3)),
                width: 1,
              ),
            ),
            child: buildReplyContent(context, replyTo, isMe, isDark),
          ),
        Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: EdgeInsets.only(
                left: isMe ? 0 : mq.width * .04,
                right: isMe ? mq.width * .04 : 0,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Material(
                    color: Colors.transparent,
                    elevation: 0,
                    animationDuration: const Duration(milliseconds: 150),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMe ? 20 : 5),
                      bottomRight: Radius.circular(isMe ? 5 : 20),
                    ),
                    child: InkWell(
                      onLongPress: () => onLongPress(isMe),
                      onDoubleTap: () => onDoubleTap(isMe),
                      onTap: () {},
                      splashColor: isMe
                          ? Colors.green.withOpacity(0.3)
                          : Colors.blue.withOpacity(0.3),
                      highlightColor: isMe
                          ? Colors.green.withOpacity(0.2)
                          : Colors.blue.withOpacity(0.2),
                      splashFactory: InkRipple.splashFactory,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMe ? 20 : 5),
                        bottomRight: Radius.circular(isMe ? 5 : 20),
                      ),
                      child: Container(
                        constraints: BoxConstraints(maxWidth: mq.width * .7),
                        padding: EdgeInsets.all(message.type == Type.image
                            ? mq.width * .03
                            : mq.width * .04),
                        decoration: BoxDecoration(
                          color: message.sending
                              ? (isMe
                                  ? (isDark
                                      ? Colors.green.withOpacity(0.3)
                                      : Colors.lightGreen.withOpacity(0.3))
                                  : (isDark
                                      ? Colors.blue.withOpacity(0.3)
                                      : Colors.lightBlue.withOpacity(0.3)))
                              : (isMe
                                  ? (isDark
                                      ? Colors.green.withOpacity(0.4)
                                      : Colors.lightGreen.withOpacity(0.4))
                                  : (isDark
                                      ? Colors.blue.withOpacity(0.4)
                                      : Colors.lightBlue.withOpacity(0.4))),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMe ? 20 : 5),
                            bottomRight: Radius.circular(isMe ? 5 : 20),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (forwarded) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.forward,
                                    size: 14,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Forwarded',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                            RichText(
                              text:
                                  _buildTextSpan(message.msg, isDark, context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (message.reactions.isNotEmpty)
                    Positioned(
                      bottom: -10,
                      left: isMe ? 0 : null,
                      right: isMe ? null : 0,
                      child: MessageReaction.buildReactionBubble(
                        message.reactions,
                        isMe,
                        isDark,
                        onTap: () {
                          MessageReaction.showReactionsDetailSheet(
                            context,
                            _getReactionUserMap(message.reactions),
                            isDark,
                            Message(
                              toId: '',
                              msg: '',
                              read: '',
                              type: Type.text,
                              fromId: '',
                              sent: message.sent,
                              reactions: message.reactions,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            // Message time and loading/seen status below the text
            Padding(
              padding: EdgeInsets.only(
                left: isMe ? 0 : mq.width * .04,
                right: isMe ? mq.width * .04 : 0,
                top: message.reactions.isEmpty ? 4 : 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    MyDateUtil.getFormattedTime(
                        context: context, time: message.sent),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[400]
                          : Colors.black54,
                    ),
                  ),
                  if (message.sending) ...[
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? Colors.grey[400]! : Colors.black54,
                        ),
                      ),
                    ),
                  ] else if (isMe) ...[
                    const SizedBox(width: 5),
                    if (message.read.isNotEmpty)
                      const Icon(Icons.done_all_rounded,
                          color: Colors.blue, size: 16)
                    else
                      Icon(Icons.done_rounded,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.black54,
                          size: 16),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build an image message
  static Widget buildImageMessage({
    required BuildContext context,
    required Message message,
    required bool isMe,
    required Function(bool) onLongPress,
    required Function(bool) onDoubleTap,
    String? replyTo,
    bool forwarded = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasLocalImage = message.localImgPath != null &&
        message.localImgPath!.isNotEmpty &&
        File(message.localImgPath!).existsSync();

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (replyTo != null)
          Container(
            margin: EdgeInsets.only(
              left: isMe ? 0 : mq.width * .04,
              right: isMe ? mq.width * .04 : 0,
              bottom: 2,
            ),
            constraints: BoxConstraints(maxWidth: mq.width * .7),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe
                  ? (isDark
                      ? Colors.green.withOpacity(0.2)
                      : const Color.fromARGB(255, 218, 255, 176)
                          .withOpacity(0.5))
                  : (isDark
                      ? Colors.blue.withOpacity(0.2)
                      : const Color.fromARGB(255, 221, 245, 255)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 12),
              ),
              border: Border.all(
                color: isMe
                    ? (isDark
                        ? Colors.green.withOpacity(0.3)
                        : Colors.lightGreen.withOpacity(0.3))
                    : (isDark
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.lightBlue.withOpacity(0.3)),
                width: 1,
              ),
            ),
            child: buildReplyContent(context, replyTo, isMe, isDark),
          ),
        Stack(
          children: [
            Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  margin: EdgeInsets.only(
                    left: isMe ? 0 : mq.width * .04,
                    right: isMe ? mq.width * .04 : 0,
                    top: mq.height * .01,
                    bottom: mq.height * .005,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: mq.width * .7,
                    maxHeight: mq.height * .4,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    elevation: 0,
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onLongPress: () => onLongPress(isMe),
                      onDoubleTap: () => onDoubleTap(isMe),
                      onTap: () {
                        // Show fullscreen image viewer
                        MessageImageViewer.showImageViewer(
                          context,
                          message.msg,
                          heroTag: message.sent,
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Stack(
                          children: [
                            // Load image from local path if available, otherwise from network
                            hasLocalImage
                                ? Image.file(
                                    File(message.localImgPath!),
                                    width: mq.width * .7,
                                    height: mq.height * .4,
                                    fit: BoxFit.cover,
                                  )
                                : CachedNetworkImage(
                                    imageUrl: message.msg,
                                    width: mq.width * .7,
                                    height: mq.height * .4,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: isMe
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.blue.withOpacity(0.1),
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                      color: isMe
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.blue.withOpacity(0.1),
                                      child: const Center(
                                        child: Icon(Icons.image_not_supported,
                                            size: 70),
                                      ),
                                    ),
                                  ),

                            // Forwarded badge on top
                            if (forwarded)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.forward,
                                          color: Colors.white, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'Forwarded',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Message time and loading/seen status below the image
                Padding(
                  padding: EdgeInsets.only(
                    left: isMe ? 0 : mq.width * .04,
                    right: isMe ? mq.width * .04 : 0,
                    bottom: mq.height * .005,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        MyDateUtil.getFormattedTime(
                            context: context, time: message.sent),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.black54,
                        ),
                      ),
                      if (message.sending) ...[
                        const SizedBox(width: 5),
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? Colors.grey[400]! : Colors.black54,
                            ),
                          ),
                        ),
                      ] else if (isMe) ...[
                        const SizedBox(width: 5),
                        if (message.read.isNotEmpty)
                          const Icon(Icons.done_all_rounded,
                              color: Colors.blue, size: 16)
                        else
                          Icon(Icons.done_rounded,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[400]
                                  : Colors.black54,
                              size: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (message.reactions.isNotEmpty)
              Positioned(
                bottom: 0,
                right: isMe ? null : mq.width * .04,
                left: isMe ? mq.width * .04 : null,
                child: MessageReaction.buildReactionBubble(
                  message.reactions,
                  isMe,
                  isDark,
                  onTap: () {
                    MessageReaction.showReactionsDetailSheet(
                      context,
                      _getReactionUserMap(message.reactions),
                      isDark,
                      Message(
                        toId: '',
                        msg: '',
                        read: '',
                        type: Type.image,
                        fromId: '',
                        sent: message.sent,
                        reactions: message.reactions,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Build a file message
  static Widget buildFileMessage({
    required BuildContext context,
    required Message message,
    required bool isMe,
    required Function(bool) onLongPress,
    required Function(bool) onDoubleTap,
    String? replyTo,
    bool forwarded = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fileIcon = _getFileIcon(message.fileType ?? '');
    final fileName = message.fileName ?? 'File';
    final fileSize = _formatFileSize(message.fileSize ?? 0);

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (replyTo != null)
          Container(
            margin: EdgeInsets.only(
              left: isMe ? 0 : mq.width * .04,
              right: isMe ? mq.width * .04 : 0,
              bottom: 2,
            ),
            constraints: BoxConstraints(maxWidth: mq.width * .7),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe
                  ? (isDark
                      ? Colors.green.withOpacity(0.2)
                      : const Color.fromARGB(255, 218, 255, 176)
                          .withOpacity(0.5))
                  : (isDark
                      ? Colors.blue.withOpacity(0.2)
                      : const Color.fromARGB(255, 221, 245, 255)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 12),
              ),
              border: Border.all(
                color: isMe
                    ? (isDark
                        ? Colors.green.withOpacity(0.3)
                        : Colors.lightGreen.withOpacity(0.3))
                    : (isDark
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.lightBlue.withOpacity(0.3)),
                width: 1,
              ),
            ),
            child: buildReplyContent(context, replyTo, isMe, isDark),
          ),
        Stack(
          children: [
            Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  margin: EdgeInsets.only(
                    left: isMe ? 0 : mq.width * .04,
                    right: isMe ? mq.width * .04 : 0,
                    top: mq.height * .01,
                    bottom: mq.height * .005,
                  ),
                  constraints: BoxConstraints(maxWidth: mq.width * .7),
                  child: Material(
                    color: Colors.transparent,
                    elevation: 0,
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onLongPress: () => onLongPress(isMe),
                      onDoubleTap: () => onDoubleTap(isMe),
                      onTap: () async {
                        // Handle file opening logic
                        if (message.msg.isNotEmpty) {
                          try {
                            final url = Uri.parse(message.msg);
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url,
                                  mode: LaunchMode.externalApplication);
                            }
                          } catch (e) {
                            log('Error opening file: $e');
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: message.sending
                              ? (isMe
                                  ? (isDark
                                      ? Colors.green.withOpacity(0.3)
                                      : Colors.lightGreen.withOpacity(0.3))
                                  : (isDark
                                      ? Colors.blue.withOpacity(0.3)
                                      : Colors.lightBlue.withOpacity(0.3)))
                              : (isMe
                                  ? (isDark
                                      ? Colors.green.withOpacity(0.4)
                                      : Colors.lightGreen.withOpacity(0.4))
                                  : (isDark
                                      ? Colors.blue.withOpacity(0.4)
                                      : Colors.lightBlue.withOpacity(0.4))),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              fileIcon,
                              size: 40,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    fileSize,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.download,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Message time and loading/seen status below the file
                Padding(
                  padding: EdgeInsets.only(
                    left: isMe ? 0 : mq.width * .04,
                    right: isMe ? mq.width * .04 : 0,
                    bottom: mq.height * .005,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        MyDateUtil.getFormattedTime(
                            context: context, time: message.sent),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.black54,
                        ),
                      ),
                      if (message.sending) ...[
                        const SizedBox(width: 5),
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? Colors.grey[400]! : Colors.black54,
                            ),
                          ),
                        ),
                      ] else if (isMe) ...[
                        const SizedBox(width: 5),
                        if (message.read.isNotEmpty)
                          const Icon(Icons.done_all_rounded,
                              color: Colors.blue, size: 16)
                        else
                          Icon(Icons.done_rounded,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[400]
                                  : Colors.black54,
                              size: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (message.reactions.isNotEmpty)
              Positioned(
                bottom: 0,
                right: isMe ? null : mq.width * .04,
                left: isMe ? mq.width * .04 : null,
                child: MessageReaction.buildReactionBubble(
                  message.reactions,
                  isMe,
                  isDark,
                  onTap: () {
                    MessageReaction.showReactionsDetailSheet(
                      context,
                      _getReactionUserMap(message.reactions),
                      isDark,
                      Message(
                        toId: '',
                        msg: '',
                        read: '',
                        type: Type.file,
                        fromId: '',
                        sent: message.sent,
                        reactions: message.reactions,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Build a video message container
  static Widget buildVideoMessage({
    required BuildContext context,
    required Message message,
    required bool isMe,
    required Function(bool) onLongPress,
    required Function(bool) onDoubleTap,
    String? replyTo,
    bool forwarded = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasLocalVideo = message.localImgPath != null &&
        message.localImgPath!.isNotEmpty &&
        File(message.localImgPath!).existsSync();

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (replyTo != null)
          Container(
            margin: EdgeInsets.only(
              left: isMe ? 0 : mq.width * .04,
              right: isMe ? mq.width * .04 : 0,
              bottom: 2,
            ),
            constraints: BoxConstraints(maxWidth: mq.width * .7),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe
                  ? (isDark
                      ? Colors.green.withOpacity(0.2)
                      : const Color.fromARGB(255, 218, 255, 176)
                          .withOpacity(0.5))
                  : (isDark
                      ? Colors.blue.withOpacity(0.2)
                      : const Color.fromARGB(255, 221, 245, 255)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 12),
              ),
              border: Border.all(
                color: isMe
                    ? (isDark
                        ? Colors.green.withOpacity(0.3)
                        : Colors.lightGreen.withOpacity(0.3))
                    : (isDark
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.lightBlue.withOpacity(0.3)),
                width: 1,
              ),
            ),
            child: buildReplyContent(context, replyTo, isMe, isDark),
          ),
        Stack(
          children: [
            Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  margin: EdgeInsets.only(
                    left: isMe ? 0 : mq.width * .04,
                    right: isMe ? mq.width * .04 : 0,
                    top: mq.height * .01,
                    bottom: mq.height * .005,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: mq.width * .7,
                    maxHeight: mq.height * .4,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    elevation: 0,
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onLongPress: () => onLongPress(isMe),
                      onDoubleTap: () => onDoubleTap(isMe),
                      onTap: () {
                        // Show fullscreen video player
                        _showVideoPlayer(context, message.msg,
                            hasLocalVideo ? message.localImgPath! : null);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Stack(
                          children: [
                            // Video thumbnail
                            hasLocalVideo
                                ? _buildLocalVideoThumbnail(
                                    message.localImgPath!)
                                : _buildNetworkVideoThumbnail(
                                    message.msg, isMe, isDark),

                            // Play button overlay
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withOpacity(0.2),
                                child: Center(
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Forwarded badge on top
                            if (forwarded)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.forward,
                                          color: Colors.white, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'Forwarded',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Message time and loading/seen status below the video
                Padding(
                  padding: EdgeInsets.only(
                    left: isMe ? 0 : mq.width * .04,
                    right: isMe ? mq.width * .04 : 0,
                    bottom: mq.height * .005,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        MyDateUtil.getFormattedTime(
                            context: context, time: message.sent),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.black54,
                        ),
                      ),
                      if (message.sending) ...[
                        const SizedBox(width: 5),
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? Colors.grey[400]! : Colors.black54,
                            ),
                          ),
                        ),
                      ] else if (isMe) ...[
                        const SizedBox(width: 5),
                        if (message.read.isNotEmpty)
                          const Icon(Icons.done_all_rounded,
                              color: Colors.blue, size: 16)
                        else
                          Icon(Icons.done_rounded,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[400]
                                  : Colors.black54,
                              size: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (message.reactions.isNotEmpty)
              Positioned(
                bottom: 0,
                right: isMe ? null : mq.width * .04,
                left: isMe ? mq.width * .04 : null,
                child: MessageReaction.buildReactionBubble(
                  message.reactions,
                  isMe,
                  isDark,
                  onTap: () {
                    MessageReaction.showReactionsDetailSheet(
                      context,
                      _getReactionUserMap(message.reactions),
                      isDark,
                      Message(
                        toId: '',
                        msg: '',
                        read: '',
                        type: Type.video,
                        fromId: '',
                        sent: message.sent,
                        reactions: message.reactions,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Helper method to build local video thumbnail
  static Widget _buildLocalVideoThumbnail(String path) {
    return _VideoThumbnail(
      videoPath: path,
      isLocal: true,
    );
  }

  // Helper method to build network video thumbnail
  static Widget _buildNetworkVideoThumbnail(
      String url, bool isMe, bool isDark) {
    return _VideoThumbnail(
      videoPath: url,
      isLocal: false,
    );
  }

  // Helper method to show a fullscreen video player
  static void _showVideoPlayer(
      BuildContext context, String videoUrl, String? localPath) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => VideoDialog(
        videoUrl: videoUrl,
        localPath: localPath,
      ),
    );
  }

  /// Build a voice message container
  static Widget buildVoiceMessage({
    required BuildContext context,
    required Message message,
    required bool isMe,
    required Function(bool) onLongPress,
    required Function(bool) onDoubleTap,
    String? replyTo,
    bool forwarded = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (replyTo != null)
          Container(
            margin: EdgeInsets.only(
              left: isMe ? 0 : mq.width * .04,
              right: isMe ? mq.width * .04 : 0,
              bottom: 2,
            ),
            constraints: BoxConstraints(maxWidth: mq.width * .7),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe
                  ? (isDark
                      ? Colors.green.withOpacity(0.2)
                      : const Color.fromARGB(255, 218, 255, 176)
                          .withOpacity(0.5))
                  : (isDark
                      ? Colors.blue.withOpacity(0.2)
                      : const Color.fromARGB(255, 221, 245, 255)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 12),
              ),
              border: Border.all(
                color: isMe
                    ? (isDark
                        ? Colors.green.withOpacity(0.3)
                        : Colors.lightGreen.withOpacity(0.3))
                    : (isDark
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.lightBlue.withOpacity(0.3)),
                width: 1,
              ),
            ),
            child: buildReplyContent(context, replyTo, isMe, isDark),
          ),
        Stack(
          children: [
            Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Show forwarded label if message is forwarded
                if (forwarded) ...[
                  Container(
                    margin: EdgeInsets.only(
                      left: isMe ? 0 : mq.width * .04,
                      right: isMe ? mq.width * .04 : 0,
                      bottom: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.forward,
                          size: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Forwarded',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Voice message player
                GestureDetector(
                  onLongPress: () => onLongPress(isMe),
                  onDoubleTap: () => onDoubleTap(isMe),
                  child: Container(
                    margin: EdgeInsets.only(
                      left: isMe ? 0 : mq.width * .04,
                      right: isMe ? mq.width * .04 : 0,
                    ),
                    child: VoiceMessagePlayer(
                      audioUrl: message.msg,
                      isMe: isMe,
                    ),
                  ),
                ),

                // Message time and loading/seen status below the voice message
                Padding(
                  padding: EdgeInsets.only(
                    left: isMe ? 0 : mq.width * .04,
                    right: isMe ? mq.width * .04 : 0,
                    bottom: mq.height * .005,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        MyDateUtil.getFormattedTime(
                            context: context, time: message.sent),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.black54,
                        ),
                      ),
                      if (message.sending) ...[
                        const SizedBox(width: 5),
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? Colors.grey[400]! : Colors.black54,
                            ),
                          ),
                        ),
                      ] else if (isMe) ...[
                        const SizedBox(width: 5),
                        if (message.read.isNotEmpty)
                          const Icon(Icons.done_all_rounded,
                              color: Colors.blue, size: 16)
                        else
                          Icon(Icons.done_rounded,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[400]
                                  : Colors.black54,
                              size: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (message.reactions.isNotEmpty)
              Positioned(
                bottom: 0,
                right: isMe ? null : mq.width * .04,
                left: isMe ? mq.width * .04 : null,
                child: MessageReaction.buildReactionBubble(
                  message.reactions,
                  isMe,
                  isDark,
                  onTap: () {
                    MessageReaction.showReactionsDetailSheet(
                      context,
                      _getReactionUserMap(message.reactions),
                      isDark,
                      Message(
                        toId: '',
                        msg: '',
                        read: '',
                        type: Type.audio,
                        fromId: '',
                        sent: message.sent,
                        reactions: message.reactions,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Helper method to get file color based on extension
  static Color getFileColor(String extension, bool isDark) {
    switch (extension) {
      case '.pdf':
        return isDark ? Colors.red[300]! : Colors.red;
      case '.doc':
      case '.docx':
        return isDark ? Colors.blue[300]! : Colors.blue;
      case '.xls':
      case '.xlsx':
        return isDark ? Colors.green[300]! : Colors.green.shade700;
      case '.zip':
      case '.rar':
        return isDark ? Colors.orange[300]! : Colors.orange;
      default:
        return isDark ? Colors.grey[400]! : Colors.grey[700]!;
    }
  }

  // Helper method to get file icon based on extension
  static IconData getFileIcon(String extension) {
    switch (extension) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.description;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart;
      case '.zip':
      case '.rar':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  // Helper method to format file size
  static String getFormattedFileSize(int? bytes) {
    if (bytes == null) return '0 B';
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  // Helper method to build image loading widget
  static Widget buildImageLoadingWidget() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  // Helper method to build image error widget
  static Widget buildImageErrorWidget() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.red),
          const SizedBox(height: 8),
          Text(
            'Failed to load image',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Helper method to build reply content
  static Widget buildReplyContent(
      BuildContext context, String replyData, bool isMe, bool isDark) {
    bool isImageUrl = replyData.startsWith('http') &&
        (replyData.contains('.jpg') ||
            replyData.contains('.jpeg') ||
            replyData.contains('.png') ||
            replyData.contains('.gif') ||
            replyData.contains('.webp'));

    // Check if it's a file reply
    bool isFileReply = replyData.startsWith('file:');
    // Check if it's a video reply
    bool isVideoReply = replyData.startsWith('video:');
    // Check if it's a voice message reply (audio URLs from your server)
    bool isVoiceReply = replyData.contains('users_audio_messages');
    String fileName = '';

    if (isFileReply) {
      fileName = replyData.substring(5); // Remove the 'file:' prefix
    } else if (isVideoReply) {
      replyData = replyData.substring(6); // Remove the 'video:' prefix
    }

    // Common reply header
    Widget replyHeader = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: (isMe ? Colors.green : Colors.blue).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.reply,
            size: 12,
            color: isMe
                ? (isDark ? Colors.green[300] : Colors.green)
                : (isDark ? Colors.blue[300] : Colors.blue),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Reply',
          style: TextStyle(
            fontSize: 11,
            color: isMe
                ? (isDark ? Colors.green[300] : Colors.green[700])
                : (isDark ? Colors.blue[300] : Colors.blue[700]),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    if (isImageUrl) {
      // Image reply content
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          replyHeader,
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: replyData,
              height: 50,
              width: 50,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                height: 50,
                width: 50,
                color: isDark ? Colors.grey[800] : Colors.grey[300],
                child: const Icon(Icons.image, color: Colors.white70),
              ),
              errorWidget: (context, url, error) => Container(
                height: 50,
                width: 50,
                color: isDark ? Colors.grey[800] : Colors.grey[300],
                child: const Icon(Icons.broken_image, color: Colors.white70),
              ),
            ),
          ),
        ],
      );
    } else if (isFileReply) {
      // File reply content
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          replyHeader,
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                height: 30,
                width: 30,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (isMe ? Colors.green : Colors.blue).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.insert_drive_file,
                  size: 16,
                  color: isMe
                      ? (isDark ? Colors.green[300] : Colors.green)
                      : (isDark ? Colors.blue[300] : Colors.blue),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (isVideoReply) {
      // Video message reply content
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          replyHeader,
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                height: 30,
                width: 30,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (isMe ? Colors.green : Colors.blue).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.videocam,
                  size: 16,
                  color: isMe
                      ? (isDark ? Colors.green[300] : Colors.green)
                      : (isDark ? Colors.blue[300] : Colors.blue),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Video message',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[800],
                ),
              ),
            ],
          ),
        ],
      );
    } else if (isVoiceReply) {
      // Voice message reply content
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          replyHeader,
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                height: 30,
                width: 30,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (isMe ? Colors.green : Colors.blue).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.mic,
                  size: 16,
                  color: isMe
                      ? (isDark ? Colors.green[300] : Colors.green)
                      : (isDark ? Colors.blue[300] : Colors.blue),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Voice message',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[800],
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      // Text reply content
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          replyHeader,
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              replyData,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[800],
              ),
            ),
          ),
        ],
      );
    }
  }

  // Helper method to convert reactions to user map
  static Map<String, List<String>> _getReactionUserMap(List<String> reactions) {
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
    return reactionUsers;
  }

  static TextSpan _buildTextSpan(
      String text, bool isDark, BuildContext context) {
    // Improved URL regex pattern that handles URLs with commas and special characters
    final urlPattern = RegExp(
      r'(?:(?:https?:\/\/)?(?:www\.)?)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}(?:[-a-zA-Z0-9()@:%_\+,.~#?&\/=]*)',
      caseSensitive: false,
    );

    List<TextSpan> spans = [];
    int start = 0;

    // Find all URLs in the text
    for (Match match in urlPattern.allMatches(text)) {
      // Add text before the URL
      if (match.start > start) {
        spans.add(TextSpan(
          text: text.substring(start, match.start),
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ));
      }

      // Add the URL with custom styling and tap handler
      String url = text.substring(match.start, match.end).trim();

      // Remove trailing commas or periods if they're not part of the URL
      if (url.endsWith(',') || url.endsWith('.')) {
        String lastChar = url[url.length - 1];
        // Check if the last dot is not part of the domain (e.g., .com, .org)
        bool isLastDotPartOfDomain = url.endsWith('.com') ||
            url.endsWith('.org') ||
            url.endsWith('.net') ||
            url.endsWith('.edu') ||
            url.endsWith('.io') ||
            url.endsWith('.dev') ||
            url.endsWith('.tn');

        if (lastChar == ',' || (lastChar == '.' && !isLastDotPartOfDomain)) {
          url = url.substring(0, url.length - 1);
          // Adjust the start position for the next iteration
          start = match.end - 1;
        } else {
          start = match.end;
        }
      } else {
        start = match.end;
      }

      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          fontSize: 15,
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            try {
              // Clean up the URL
              url = url.toLowerCase();

              // Add https:// if no scheme is present
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                url = 'https://$url';
              }

              final uri = Uri.parse(url);
              try {
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                  webOnlyWindowName: '_blank',
                );
              } catch (e) {
                // If https fails, try http
                final httpUri =
                    Uri.parse(url.replaceFirst('https://', 'http://'));
                try {
                  await launchUrl(
                    httpUri,
                    mode: LaunchMode.externalApplication,
                    webOnlyWindowName: '_blank',
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not open browser for: $url'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              }
            } catch (e) {
              print('URL Error: $e for URL: $url'); // For debugging
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Invalid URL format: $url'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
      ));
    }

    // Add remaining text after the last URL
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: TextStyle(
          fontSize: 15,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ));
    }

    return TextSpan(children: spans);
  }

  // Helper method to download a file
  static void onDownload(Message message) {
    // Implement file download logic here
    log('Downloading file: ${message.fileName}');
    // This would typically launch a download process
  }

  // Helper method to format time
  static String getFormattedTime(String timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Helper method to get icon for file type
  static IconData _getFileIcon(String fileType) {
    fileType = fileType.toLowerCase();

    if (fileType.isEmpty) {
      return Icons.insert_drive_file;
    }

    if (fileType == 'pdf') {
      return Icons.picture_as_pdf;
    } else if (['doc', 'docx', 'txt', 'rtf'].contains(fileType)) {
      return Icons.description;
    } else if (['xls', 'xlsx', 'csv'].contains(fileType)) {
      return Icons.table_chart;
    } else if (['ppt', 'pptx'].contains(fileType)) {
      return Icons.slideshow;
    } else if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp']
        .contains(fileType)) {
      return Icons.image;
    } else if (['mp3', 'wav', 'ogg', 'flac', 'm4a'].contains(fileType)) {
      return Icons.audio_file;
    } else if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'mkv'].contains(fileType)) {
      return Icons.video_file;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(fileType)) {
      return Icons.folder_zip;
    } else if (['exe', 'bat', 'sh', 'app', 'bin'].contains(fileType)) {
      return Icons.apps;
    }

    return Icons.insert_drive_file;
  }

  /// Helper method to format file size
  static String _formatFileSize(int fileSizeInBytes) {
    if (fileSizeInBytes < 1024) {
      return '$fileSizeInBytes B';
    } else if (fileSizeInBytes < 1024 * 1024) {
      final sizeInKB = (fileSizeInBytes / 1024).toStringAsFixed(1);
      return '$sizeInKB KB';
    } else if (fileSizeInBytes < 1024 * 1024 * 1024) {
      final sizeInMB = (fileSizeInBytes / (1024 * 1024)).toStringAsFixed(1);
      return '$sizeInMB MB';
    } else {
      final sizeInGB =
          (fileSizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
      return '$sizeInGB GB';
    }
  }

  // Helper method to build reactions display
  static Widget buildReactions(BuildContext context, List<String> reactions,
      String messageId, bool isMe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: 0,
      right: isMe ? null : mq.width * .04,
      left: isMe ? mq.width * .04 : null,
      child: MessageReaction.buildReactionBubble(
        reactions,
        isMe,
        isDark,
        onTap: () {
          MessageReaction.showReactionsDetailSheet(
            context,
            _getReactionUserMap(reactions),
            isDark,
            Message(
              toId:
                  '', // These values don't matter as we're just passing for the UI
              msg: '',
              read: '',
              type: Type.audio,
              fromId: '',
              sent: messageId,
              reactions: reactions,
            ),
          );
        },
      ),
    );
  }
}

// Video dialog widget for popup video player
class VideoDialog extends StatefulWidget {
  final String videoUrl;
  final String? localPath;

  const VideoDialog({
    super.key,
    required this.videoUrl,
    this.localPath,
  });

  @override
  State<VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<VideoDialog> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = null;
      });

      if (widget.localPath != null && File(widget.localPath!).existsSync()) {
        _videoPlayerController =
            VideoPlayerController.file(File(widget.localPath!));
      } else {
        // Ensure URL has scheme
        String videoUrl = widget.videoUrl;
        if (!videoUrl.startsWith('http://') &&
            !videoUrl.startsWith('https://')) {
          videoUrl = 'https://$videoUrl';
        }

        _videoPlayerController =
            VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      }

      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        showControls: true,
        allowFullScreen: true,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text(
                  'Error playing video: $errorMessage',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    _initializePlayer();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        },
      );

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error initializing video player: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: mq.width * 0.95,
              maxHeight: mq.height * 0.7,
            ),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildVideoPlayer(),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Failed to load video\n${_errorMessage ?? ""}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                _initializePlayer();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _chewieController == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    return Chewie(controller: _chewieController!);
  }
}

// Video thumbnail widget
class _VideoThumbnail extends StatefulWidget {
  final String videoPath;
  final bool isLocal;

  const _VideoThumbnail({
    required this.videoPath,
    required this.isLocal,
  });

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  static final Map<String, VideoPlayerController> _videoCache = {};
  static const int _maxCacheSize = 10; // Maximum number of cached videos

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      // Check if video is in cache
      if (_videoCache.containsKey(widget.videoPath)) {
        _controller = _videoCache[widget.videoPath];
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
        return;
      }

      // Clean cache if it exceeds maximum size
      if (_videoCache.length >= _maxCacheSize) {
        _cleanCache();
      }

      // Initialize new controller
      if (widget.isLocal && File(widget.videoPath).existsSync()) {
        _controller = VideoPlayerController.file(File(widget.videoPath));
      } else {
        // Ensure URL has scheme
        String videoUrl = widget.videoPath;
        if (!videoUrl.startsWith('http://') &&
            !videoUrl.startsWith('https://')) {
          videoUrl = 'https://$videoUrl';
        }
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      }

      await _controller!.initialize();
      await _controller!.setLooping(false);
      await _controller!.setVolume(0.0);
      await _controller!.seekTo(Duration.zero);

      // Add to cache
      _videoCache[widget.videoPath] = _controller!;

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing video controller: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _cleanCache() {
    if (_videoCache.length < _maxCacheSize) return;

    // Get the first entry to remove (oldest)
    final entryToRemove = _videoCache.entries.first;
    entryToRemove.value.dispose();
    _videoCache.remove(entryToRemove.key);
  }

  @override
  void dispose() {
    // Don't dispose the controller if it's cached
    if (_controller != null && !_videoCache.containsKey(widget.videoPath)) {
      _controller!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Container(
        width: mq.width * .7,
        height: mq.height * .4,
        color: Colors.grey[800],
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    if (_hasError) {
      return Container(
        width: mq.width * .7,
        height: mq.height * .4,
        color: Colors.grey[800],
        child: const Center(
          child: Icon(
            Icons.error_outline,
            color: Colors.white,
            size: 40,
          ),
        ),
      );
    }

    return Container(
      width: mq.width * .7,
      height: mq.height * .4,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
