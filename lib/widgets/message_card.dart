import 'package:flutter/material.dart';
import '../models/message.dart';

// Using the new modular structure
import 'message/message.dart' as msg;

// This file is a bridge to the new modular structure
// Make sure to gradually migrate direct imports of this file to use 'message/message.dart'

/// For showing single message details - Bridge to new implementation
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
    // Just delegate to our new implementation
    return msg.MessageCard(
      message: widget.message,
      onReplyTap: widget.onReplyTap,
      showDateSeparator: widget.showDateSeparator,
    );
  }
}

// Class definition for date separator
class DateSeparator extends StatelessWidget {
  final String date;
  final bool isDark;

  const DateSeparator({
    super.key,
    required this.date,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return msg.DateSeparator(date: date, isDark: isDark);
  }
}
