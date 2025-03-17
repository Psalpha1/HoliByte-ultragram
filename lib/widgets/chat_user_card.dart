import 'package:flutter/material.dart';

import '../api/apis.dart';
import '../helper/my_date_util.dart';
import '../models/chat_user.dart';
import '../models/message.dart';
import '../screens/chat_screen.dart';
import 'profile_image.dart';

//card to represent a single user in home screen
class ChatUserCard extends StatefulWidget {
  final ChatUser user;
  final Message? lastMessage;
  final VoidCallback? onTap;
  final String heroTag;

  const ChatUserCard({
    super.key,
    required this.user,
    this.lastMessage,
    this.onTap,
    this.heroTag = 'chat_card',
  });

  @override
  State<ChatUserCard> createState() => _ChatUserCardState();
}

class _ChatUserCardState extends State<ChatUserCard> {
  Message? _message;
  bool _showOptions = false;

  @override
  Widget build(BuildContext context) {
    // Get the media query data for responsive sizing
    final mediaQuery = MediaQuery.of(context);

    return Card(
      margin: EdgeInsets.symmetric(
          horizontal: mediaQuery.size.width * .04, vertical: 4),
      color: Colors.transparent,
      // elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(user: widget.user),
              ),
            );
          }
        },
        onLongPress: () {
          setState(() {
            _showOptions = !_showOptions;
          });
        },
        child: StreamBuilder(
          stream: APIs.getLastMessage(widget.user),
          builder: (context, snapshot) {
            final data = snapshot.data?.docs;
            final list =
                data?.map((e) => Message.fromJson(e.data())).toList() ?? [];
            if (list.isNotEmpty) _message = list[0];

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: mediaQuery.size.width * .03,
                vertical: mediaQuery.size.height * .015,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    children: [
                      // User profile picture
                      ProfileImage(
                        url: widget.user.image,
                        size: mediaQuery.size.height * .055,
                      ),

                      SizedBox(width: mediaQuery.size.width * .03),

                      // User info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // User name and last message time
                            Row(
                              children: [
                                // User name
                                Expanded(
                                  child: Text(
                                    widget.user.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Last message time
                                if (_message != null &&
                                    constraints.maxWidth > 250)
                                  Text(
                                    MyDateUtil.getLastMessageTime(
                                      context: context,
                                      time: _message!.sent,
                                    ),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Last Message
                            Row(
                              children: [
                                Expanded(
                                  child: _buildLastMessageText(_message),
                                ),
                                if (_message != null &&
                                    constraints.maxWidth <= 250) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    MyDateUtil.getLastMessageTime(
                                      context: context,
                                      time: _message!.sent,
                                    ),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Unread Message Indicator
                      if (_message != null &&
                          _message!.fromId != APIs.user.uid &&
                          _message!.read.isEmpty)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLastMessageText(Message? message) {
    if (message == null) return const SizedBox.shrink();

    String text;
    IconData? icon;

    switch (message.type) {
      case Type.image:
        text = '📸 Photo';
        icon = Icons.image;
        break;
      case Type.video:
        text = '📹 Video';
        icon = Icons.videocam;
        break;
      case Type.file:
        text = '📎 ${message.fileName ?? 'File'}';
        icon = Icons.attach_file;
        break;
      case Type.audio:
        text = '🎤 Voice message';
        icon = Icons.mic;
        break;
      default:
        text = message.msg;
        icon = null;
    }

    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[400]
                : Colors.grey[600],
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[400]
                  : Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }
}
