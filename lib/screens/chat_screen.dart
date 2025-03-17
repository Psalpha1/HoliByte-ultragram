// Dart imports
import 'dart:async';
import 'dart:io';
import 'dart:developer';

// Package imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
// import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';

// Project imports
import '../api/apis.dart';
import '../helper/my_date_util.dart';
import '../main.dart';
import '../models/chat_user.dart';
import '../models/message.dart';
import '../widgets/message_card.dart';
import '../widgets/profile_image.dart';
import 'call_page.dart';
import 'view_profile_screen.dart';
import '../widgets/voice_message_recorder.dart';

class ChatScreen extends StatefulWidget {
  final ChatUser user;

  const ChatScreen({super.key, required this.user});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = StreamController<List<Message>>.broadcast();
  final _userStatusController = StreamController<ChatUser>.broadcast();
  final _textController = TextEditingController();

  List<Message> _messages = [];
  ChatUser? _currentUser;
  Message? _replyToMessage;

  // UI State
  bool _showEmoji = false;
  bool _showSuggestions = false;
  // ignore: unused_field
  bool _isLoadingSuggestions = false;
  Map<String, String> _aiSuggestions = {};
  Timer? _suggestionTimer;

  // Voice recording state
  bool _isRecordingVoice = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
    // Configure keyboard to remove animation
    SystemChannels.textInput
        .invokeMethod('TextInput.setImeAnimation', {'enabled': false});
  }

  @override
  void dispose() {
    // Reset keyboard animation setting
    SystemChannels.textInput
        .invokeMethod('TextInput.setImeAnimation', {'enabled': true});
    _messageController.close();
    _userStatusController.close();
    _textController.dispose();
    _suggestionTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    // Subscribe to message updates
    APIs.getAllMessages(widget.user).listen(_handleNewMessages);

    // Subscribe to user status updates
    APIs.getUserInfo(widget.user).listen(_handleUserStatusUpdate);
  }

  void _handleNewMessages(QuerySnapshot snapshot) {
    if (!mounted) return;

    final newMessages = snapshot.docs
        .map((doc) => Message.fromJson(doc.data() as Map<String, dynamic>))
        .toList();

    // Only update if there are actual changes
    if (!listEquals(_messages, newMessages)) {
      _messages = newMessages;
      _messageController.add(_messages);
    }
  }

  void _handleUserStatusUpdate(QuerySnapshot snapshot) {
    if (!mounted) return;

    final users = snapshot.docs
        .map((doc) => ChatUser.fromJson(doc.data() as Map<String, dynamic>))
        .toList();

    if (users.isNotEmpty && _currentUser != users[0]) {
      _currentUser = users[0];
      _userStatusController.add(_currentUser!);
    }
  }

  Future<void> _sendMessage(String text, Type type) async {
    if (text.isEmpty) return;

    // Create a temporary message with sending state
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    final textToSend = text;

    try {
      setState(() {
        _showSuggestions = false;
        _aiSuggestions.clear();
      });

      // Clear text field immediately
      _textController.clear();

      // Determine what to store in the replyTo field
      String? replyData;
      if (_replyToMessage != null) {
        // For image messages, store the image URL
        if (_replyToMessage!.type == Type.image) {
          replyData = _replyToMessage!.msg; // The URL of the image
        }
        // For video messages, store video URL
        else if (_replyToMessage!.type == Type.video) {
          replyData = "video:${_replyToMessage!.msg}"; // The URL of the video
        }
        // For file messages, store file name prefixed with "file:"
        else if (_replyToMessage!.type == Type.file) {
          replyData = _replyToMessage!.fileName != null
              ? "file:${_replyToMessage!.fileName}"
              : "file:Unknown file";
        }
        // For text messages, store the text
        else {
          replyData = _replyToMessage!.msg;
        }
      }

      final tempMessage = Message(
        toId: widget.user.id,
        msg: textToSend,
        read: '',
        type: type,
        fromId: APIs.user.uid,
        sent: time,
        sending: true,
        replyTo: replyData,
      );

      // Add temporary message to the list
      setState(() {
        _messages.insert(0, tempMessage);
        _messageController.add(_messages);
      });

      // Clear reply immediately after sending
      _clearReply();

      // Check for internet connectivity
      try {
        final result = await InternetAddress.lookup('google.com');
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          // Send the actual message
          if (_messages.length == 1) {
            await APIs.sendFirstMessage(widget.user, textToSend, type,
                replyTo: replyData);
          } else {
            await APIs.sendMessage(widget.user, textToSend, type,
                replyTo: replyData);
          }

          // Remove temporary message (it will be replaced by the real one from Firestore)
          if (mounted) {
            setState(() {
              _messages.removeWhere((msg) => msg.sent == time && msg.sending);
              _messageController.add(_messages);
            });
          }
        }
      } on SocketException catch (_) {
        // Keep the message in sending state if there's no internet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No internet connection. Message will be sent when online.'),
            duration: Duration(seconds: 2),
          ),
        );

        // Start a periodic check for internet connection
        Timer.periodic(const Duration(seconds: 3), (timer) async {
          try {
            final result = await InternetAddress.lookup('google.com');
            if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
              timer.cancel();

              // Try sending the message again
              if (_messages.length == 1) {
                await APIs.sendFirstMessage(widget.user, textToSend, type,
                    replyTo: replyData);
              } else {
                await APIs.sendMessage(widget.user, textToSend, type,
                    replyTo: replyData);
              }

              // Remove temporary message once sent
              if (mounted) {
                setState(() {
                  _messages
                      .removeWhere((msg) => msg.sent == time && msg.sending);
                  _messageController.add(_messages);
                });
              }

              // Show success message
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Message sent successfully'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          } catch (_) {
            // Still no internet, continue waiting
          }
        });
      }
    } catch (e) {
      print('Error sending message: $e');

      // Show error in UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Remove the temporary message on error
      if (mounted) {
        setState(() {
          _messages.removeWhere((msg) => msg.sent == time && msg.sending);
          _messageController.add(_messages);
        });
      }
    }
  }

  Future<void> _handleImageSelection(ImageSource source,
      {bool multiple = false}) async {
    try {
      final ImagePicker picker = ImagePicker();

      if (multiple) {
        final List<XFile> images =
            await picker.pickMultiImage(imageQuality: 70);
        for (var image in images) {
          final time = DateTime.now().millisecondsSinceEpoch.toString();
          final tempMessage = Message(
            toId: widget.user.id,
            msg: '',
            read: '',
            type: Type.image,
            fromId: APIs.user.uid,
            sent: time,
            sending: true,
            localImgPath: image.path,
          );

          setState(() {
            _messages.insert(0, tempMessage);
            _messageController.add(_messages);
          });

          try {
            await APIs().uploadFile(
              File(image.path),
              widget.user,
              Type.image,
              image.name,
              await image.length(),
              image.mimeType,
            );
          } catch (e) {
            log('Error uploading image: $e');
            if (mounted) {
              setState(() {
                _messages.removeWhere((msg) => msg.sent == time && msg.sending);
                _messageController.add(_messages);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Failed to upload image. ${e.toString()}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      } else {
        final XFile? image =
            await picker.pickImage(source: source, imageQuality: 70);
        if (image != null) {
          final time = DateTime.now().millisecondsSinceEpoch.toString();
          final tempMessage = Message(
            toId: widget.user.id,
            msg: '',
            read: '',
            type: Type.image,
            fromId: APIs.user.uid,
            sent: time,
            sending: true,
            localImgPath: image.path,
          );

          setState(() {
            _messages.insert(0, tempMessage);
            _messageController.add(_messages);
          });

          try {
            await APIs().uploadFile(
              File(image.path),
              widget.user,
              Type.image,
              image.name,
              await image.length(),
              image.mimeType,
            );
          } catch (e) {
            log('Error uploading image: $e');
            if (mounted) {
              setState(() {
                _messages.removeWhere((msg) => msg.sent == time && msg.sending);
                _messageController.add(_messages);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Failed to upload image. ${e.toString()}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to select image')),
      );
    }
  }

  Future<void> _handleFileSelection() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );

      if (result != null) {
        for (PlatformFile file in result.files) {
          if (file.path != null) {
            final time = DateTime.now().millisecondsSinceEpoch.toString();
            final tempMessage = Message(
              toId: widget.user.id,
              msg: '',
              read: '',
              type: Type.file,
              fromId: APIs.user.uid,
              sent: time,
              sending: true,
              fileName: file.name,
              fileSize: file.size,
              fileType: file.extension,
            );

            setState(() {
              _messages.insert(0, tempMessage);
              _messageController.add(_messages);
            });

            try {
              await APIs().uploadFile(
                File(file.path!),
                widget.user,
                Type.file,
                file.name,
                file.size,
                file.extension,
              );
            } catch (e) {
              print('Error uploading file: $e');
              if (mounted) {
                setState(() {
                  _messages
                      .removeWhere((msg) => msg.sent == time && msg.sending);
                  _messageController.add(_messages);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to upload: ${file.name}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to select file')),
        );
      }
    }
  }

  // Add this widget to show AI suggestions
  Widget _buildSuggestionCard(
      String style, String suggestion, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      elevation: 4,
      shadowColor: color.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _textController.text = suggestion;
            _showSuggestions = false;
          });
        },
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Style header with icon
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    style,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Divider
              Container(
                height: 1,
                color: color.withOpacity(0.1),
              ),
              const SizedBox(height: 8),
              // Scrollable suggestion text
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.grey[800],
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Add this widget to show AI suggestions
  Widget _buildAISuggestions() {
    if (!_showSuggestions || _aiSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 140,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        children: [
          _buildSuggestionCard(
              'Professional',
              _aiSuggestions['professional'] ?? '',
              Icons.business,
              Colors.blue),
          _buildSuggestionCard('Creative', _aiSuggestions['creative'] ?? '',
              Icons.palette, Colors.purple),
          _buildSuggestionCard('Bold', _aiSuggestions['bold'] ?? '',
              Icons.flash_on, Colors.orange),
          _buildSuggestionCard('Funny', _aiSuggestions['funny'] ?? '',
              Icons.sentiment_very_satisfied, Colors.green),
        ],
      ),
    );
  }

  // Add this method to handle reply
  void _handleReply(Message message) {
    setState(() {
      _replyToMessage = message;
    });
  }

  // Add this method to clear reply
  void _clearReply() {
    setState(() {
      _replyToMessage = null;
    });
  }

  // Add this widget to show reply preview
  Widget _buildReplyPreview() {
    if (_replyToMessage == null) return const SizedBox.shrink();

    // Determine the type of reply content
    bool isImageReply = _replyToMessage!.type == Type.image;
    bool isFileReply = _replyToMessage!.type == Type.file;
    bool isVoiceReply = _replyToMessage!.type == Type.audio;
    bool isVideoReply = _replyToMessage!.type == Type.video;
    String replyContent = _replyToMessage!.msg;
    String? fileName = _replyToMessage!.fileName;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? Colors.blue[300] : Colors.blue[600];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black12 : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: isImageReply ? 80 : 40,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.reply, size: 16, color: accentColor),
                    const SizedBox(width: 4),
                    Text(
                      'Reply',
                      style: TextStyle(
                        fontSize: 13,
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (isImageReply)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 60,
                      width: 60,
                      child: _replyToMessage!.localImgPath != null &&
                              File(_replyToMessage!.localImgPath!).existsSync()
                          ? Image.file(
                              File(_replyToMessage!.localImgPath!),
                              fit: BoxFit.cover,
                            )
                          : CachedNetworkImage(
                              imageUrl: _replyToMessage!.msg,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[200],
                                child: Icon(
                                  Icons.image,
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[400],
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[200],
                                child: Icon(
                                  Icons.broken_image,
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[400],
                                ),
                              ),
                            ),
                    ),
                  )
                else if (isVideoReply)
                  Row(
                    children: [
                      Container(
                        height: 32,
                        width: 32,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.videocam,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Video message',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[300] : Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  )
                else if (isFileReply)
                  Row(
                    children: [
                      Container(
                        height: 32,
                        width: 32,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.insert_drive_file,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fileName ?? 'File',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[300] : Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  )
                else if (isVoiceReply)
                  Row(
                    children: [
                      Container(
                        height: 32,
                        width: 32,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.mic,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Voice message',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    replyContent,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close,
                size: 18, color: isDark ? Colors.grey[400] : Colors.grey[600]),
            onPressed: _clearReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Set system UI overlays to control keyboard behavior
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor:
            Theme.of(context).brightness == Brightness.dark
                ? const Color(0xff1a1a1a)
                : const Color.fromARGB(255, 234, 248, 255),
      ),
    );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PopScope(
        canPop: false,
        onPopInvoked: _handlePopScope,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff1a1a1a)
              : const Color.fromARGB(255, 234, 248, 255),
          appBar: AppBar(
            automaticallyImplyLeading: false,
            flexibleSpace: _buildAppBar(),
            actions: _buildAppBarActions(),
          ),
          body: Stack(
            children: [
              // Background Image with theme-based overlay positioned to be fixed
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                            .withOpacity(0.1) // Darker overlay for dark theme
                        : Colors.white
                            .withOpacity(0), // Light overlay for light theme
                    BlendMode.srcOver,
                  ),
                  child: Image.asset(
                    'assets/images/chat_background.png',
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // Semi-transparent gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xff1a1a1a).withOpacity(0.7)
                            : const Color.fromARGB(255, 234, 248, 255)
                                .withOpacity(0.7),
                        Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xff1a1a1a).withOpacity(0.9)
                            : const Color.fromARGB(255, 234, 248, 255)
                                .withOpacity(0.9),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // Make the message list expand to fill available space and scroll when needed
                    Expanded(
                      child: StreamBuilder<List<Message>>(
                        stream: _messageController.stream,
                        initialData: _messages,
                        builder: (context, snapshot) {
                          return _buildMessageList(snapshot.data ?? []);
                        },
                      ),
                    ),
                    // Reply preview and chat input remain at bottom
                    if (_replyToMessage != null) _buildReplyPreview(),
                    _buildChatInput(),
                    if (_showEmoji) _buildEmojiPicker(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // app bar widget
  Widget _buildAppBar() {
    return SafeArea(
      child: InkWell(
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ViewProfileScreen(user: widget.user)));
          },
          child: StreamBuilder(
              stream: _userStatusController.stream,
              builder: (context, snapshot) {
                final user = snapshot.data ?? widget.user;

                return Row(
                  children: [
                    //back button
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.arrow_back,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white70
                                    : Colors.black54)),

                    //user profile picture
                    ProfileImage(
                      size: mq.height * .05,
                      url: user.image,
                    ),

                    //for adding some space
                    const SizedBox(width: 10),

                    //user name & last seen time
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        //user name
                        Text(user.name,
                            style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w500)),

                        //for adding some space
                        const SizedBox(height: 2),

                        //last seen time of user
                        Text(
                            user.isOnline
                                ? 'Online'
                                : MyDateUtil.getLastActiveTime(
                                    context: context,
                                    lastActive: user.lastActive),
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white70
                                    : Colors.black54)),
                      ],
                    ),
                  ],
                );
              })),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      IconButton(
        icon: Icon(Icons.call), // You can use any icon here
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CallPage(
                    receiverUserId: widget.user.id,
                    receiverUserEmail: widget.user.email,
                    isIncoming: false,
                  )));
        },
      ),
    ];
  }

  Widget _buildMessageList(List<Message> messages) {
    if (messages.isEmpty) {
      return const Center(
        child: Text('Say Hii! 👋', style: TextStyle(fontSize: 20)),
      );
    }

    return ListView.builder(
      reverse: true,
      itemCount: messages.length,
      padding: EdgeInsets.only(top: mq.height * .01),
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        // Get current message
        final Message message = messages[index];

        // Check if we need to show a date separator
        final bool showDateSeparator = index == messages.length - 1 ||
            !_isSameDay(messages[index + 1].sent, message.sent);

        return MessageCard(
          message: message,
          onReplyTap: _handleReply,
          showDateSeparator: showDateSeparator,
        );
      },
    );
  }

  // Helper method to check if two timestamps are from the same day
  bool _isSameDay(String timestamp1, String timestamp2) {
    final DateTime date1 =
        DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp1));
    final DateTime date2 =
        DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp2));

    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildChatInput() {
    // Use AnimatedContainer with zero duration for immediate response
    return AnimatedContainer(
      duration: Duration.zero,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? MediaQuery.of(context).viewInsets.bottom
            : 10, // Add extra padding when keyboard is not shown
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAISuggestions(),
          Container(
            margin: EdgeInsets.symmetric(
              horizontal: mq.width * .02,
              vertical: mq.height * .01,
            ),
            child: _isRecordingVoice
                ? VoiceMessageRecorder(
                    user: widget.user,
                    onCancel: _hideVoiceMessageRecorder,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Text input field container with emoji and attachment
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey.withOpacity(0.2)
                                  : Colors.grey.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Emoji button
                              Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                child: IconButton(
                                  onPressed: () {
                                    FocusScope.of(context).unfocus();
                                    setState(() => _showEmoji = !_showEmoji);
                                  },
                                  icon: Icon(
                                    _showEmoji
                                        ? Icons.keyboard
                                        : Icons.mood_rounded,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    size: 26,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  splashRadius: 24,
                                ),
                              ),

                              // Text field
                              Expanded(
                                child: TextField(
                                  controller: _textController,
                                  keyboardType: TextInputType.multiline,
                                  maxLines: null,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      if (_showSuggestions) {
                                        _showSuggestions = false;
                                        _aiSuggestions.clear();
                                      }
                                    });
                                  },
                                  onTap: () {
                                    if (_showEmoji) {
                                      setState(() => _showEmoji = false);
                                    }

                                    // Remove the delay since we're disabling the animation
                                    setState(() {});
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Message',
                                    hintStyle: TextStyle(
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.grey[500]
                                          : Colors.grey[600],
                                      fontSize: 16,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 0,
                                      vertical: 12,
                                    ),
                                    border: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    suffixIcon: _textController.text.isNotEmpty
                                        ? IconButton(
                                            onPressed: () async {
                                              setState(() {
                                                _showSuggestions = true;
                                                _isLoadingSuggestions = true;
                                                _aiSuggestions = {
                                                  'professional': 'Loading...',
                                                  'creative': 'Loading...',
                                                  'bold': 'Loading...',
                                                  'funny': 'Loading...',
                                                };
                                              });

                                              // Cancel any existing timer
                                              _suggestionTimer?.cancel();

                                              try {
                                                // Get suggestions from API
                                                final suggestions = await APIs
                                                    .getMessageSuggestions(
                                                        _textController.text);

                                                if (mounted) {
                                                  setState(() {
                                                    _isLoadingSuggestions =
                                                        false;
                                                    _aiSuggestions =
                                                        suggestions;
                                                  });
                                                }
                                              } catch (e) {
                                                print(
                                                    'Error getting suggestions: $e');
                                                if (mounted) {
                                                  setState(() {
                                                    _isLoadingSuggestions =
                                                        false;
                                                    _showSuggestions = false;
                                                  });
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          'Failed to get suggestions. Please try again.'),
                                                      duration:
                                                          Duration(seconds: 2),
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                            icon: Icon(
                                              Icons.auto_awesome,
                                              color: Theme.of(context)
                                                          .brightness ==
                                                      Brightness.dark
                                                  ? Colors.grey[400]
                                                  : Colors.grey[600],
                                              size: 24,
                                            ),
                                            tooltip: 'Enhance text',
                                          )
                                        : null,
                                  ),
                                ),
                              ),

                              // Attachment button
                              Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                child: IconButton(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    _showAttachmentOptions();
                                  },
                                  icon: Icon(
                                    Icons.attach_file,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    size: 24,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  splashRadius: 24,
                                ),
                              ),

                              // Camera button
                              Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                child: IconButton(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    _handleImageSelection(ImageSource.camera);
                                  },
                                  icon: Icon(
                                    Icons.camera_alt,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    size: 24,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  splashRadius: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Send/Mic button
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: _textController.text.trim().isNotEmpty
                            ? _buildSendButton()
                            : _buildVoiceButton(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Send button widget
  Widget _buildSendButton() {
    return Material(
      key: const ValueKey('sendButton'),
      color: Colors.transparent,
      child: Container(
        width: 48,
        height: 48,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: () {
            if (_textController.text.trim().isNotEmpty) {
              HapticFeedback.mediumImpact();
              _sendMessage(_textController.text, Type.text);
            }
          },
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.blue[400],
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.send,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Voice message button
  Widget _buildVoiceButton() {
    return SizedBox(
      height: 50,
      width: 50,
      child: RawMaterialButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _showVoiceMessageRecorder();
        },
        padding: EdgeInsets.zero,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.blue[400],
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.mic,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  // Show voice message recorder
  void _showVoiceMessageRecorder() {
    setState(() {
      _isRecordingVoice = true;
    });
  }

  void _hideVoiceMessageRecorder() {
    setState(() {
      _isRecordingVoice = false;
    });
  }

  Widget _buildEmojiPicker() {
    return Container(
      height: mq.height * .35,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : Colors.grey[50],
      child: EmojiPicker(
        textEditingController: _textController,
        config: const Config(),
      ),
    );
  }

  Future<void> _handlePopScope(bool didPop) async {
    if (didPop) return;

    if (_showEmoji) {
      setState(() => _showEmoji = !_showEmoji);
      return;
    }

    // some delay before pop
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // Add this method to handle location permissions and get current location
  Future<void> _handleLocationSharing() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable location services'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Getting your location...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Create Google Maps URL
      String locationUrl =
          'https://www.google.com/maps?q=${position.latitude},${position.longitude}';

      // Send location message
      await _sendMessage(locationUrl, Type.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location shared successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error sharing location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to share location'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Show attachment options
  void _showAttachmentOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    late final OverlayEntry overlayEntry;

    // Create an animation controller
    final animationController = AnimationController(
      vsync: Navigator.of(context),
      duration: const Duration(milliseconds: 300),
    );

    // Create animations for different aspects
    final backdropAnimation = Tween<double>(begin: 0.0, end: 0.3).animate(
      CurvedAnimation(
        parent: animationController,
        curve: Curves.easeOut,
      ),
    );

    final menuSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    final menuScaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Animated Backdrop
          AnimatedBuilder(
            animation: backdropAnimation,
            builder: (context, child) => Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  animationController.reverse().then((_) {
                    overlayEntry.remove();
                  });
                },
                child: Container(
                  color: Colors.black.withOpacity(backdropAnimation.value),
                ),
              ),
            ),
          ),
          // Animated Menu
          Positioned(
            bottom: MediaQuery.of(context).viewInsets.bottom + 70,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: animationController,
              builder: (context, child) => SlideTransition(
                position: menuSlideAnimation,
                child: ScaleTransition(
                  scale: menuScaleAnimation,
                  child: child!,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom:
                          MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 20,
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 20, horizontal: 16),
                          decoration: BoxDecoration(
                            color:
                                isDark ? const Color(0xFF1E1E1E) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildAttachmentGridItem(
                                    icon: Icons.photo_library_rounded,
                                    label: 'Gallery',
                                    color: Colors.purple,
                                    onTap: () {
                                      animationController.reverse().then((_) {
                                        overlayEntry.remove();
                                        _handleImageSelection(
                                            ImageSource.gallery,
                                            multiple: true);
                                      });
                                    },
                                  ),
                                  _buildAttachmentGridItem(
                                    icon: Icons.videocam_rounded,
                                    label: 'Video',
                                    color: Colors.red,
                                    onTap: () {
                                      animationController.reverse().then((_) {
                                        overlayEntry.remove();
                                        _handleVideoSelection();
                                      });
                                    },
                                  ),
                                  _buildAttachmentGridItem(
                                    icon: Icons.description_rounded,
                                    label: 'Document',
                                    color: Colors.blue,
                                    onTap: () {
                                      animationController.reverse().then((_) {
                                        overlayEntry.remove();
                                        _handleFileSelection();
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildAttachmentGridItem(
                                    icon: Icons.location_on,
                                    label: 'Location',
                                    color: Colors.green,
                                    onTap: () {
                                      animationController.reverse().then((_) {
                                        overlayEntry.remove();
                                        _handleLocationSharing();
                                      });
                                    },
                                  ),
                                  // Add empty spaces to maintain grid alignment
                                  const SizedBox(width: 80),
                                  const SizedBox(width: 80),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Insert the overlay and start the animation
    Overlay.of(context).insert(overlayEntry);
    animationController.forward();
  }

  Widget _buildAttachmentGridItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: isDark ? Color(0xFF2A2A2A) : Colors.grey[100],
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Handle video selection and sending
  Future<void> _handleVideoSelection() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? video = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5), // Limit video to 5 minutes
      );

      if (video != null) {
        // Check video size (limit to 50MB)
        final videoSize = await video.length();
        if (videoSize > 50 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Video size should be less than 50MB'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        final time = DateTime.now().millisecondsSinceEpoch.toString();
        final tempMessage = Message(
          toId: widget.user.id,
          msg: '',
          read: '',
          type: Type.video,
          fromId: APIs.user.uid,
          sent: time,
          sending: true,
          localImgPath: video.path,
          fileName: video.name,
          fileSize: videoSize,
          fileType: 'video/mp4',
        );

        setState(() {
          _messages.insert(0, tempMessage);
          _messageController.add(_messages);
        });

        try {
          await APIs().uploadFile(
            File(video.path),
            widget.user,
            Type.video,
            video.name,
            videoSize,
            'video/mp4',
          );
        } catch (e) {
          log('Error uploading video: $e');
          if (mounted) {
            setState(() {
              _messages.removeWhere((msg) => msg.sent == time && msg.sending);
              _messageController.add(_messages);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Failed to upload video. ${e.toString()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error picking video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to select video'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
