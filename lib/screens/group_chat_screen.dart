import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/apis.dart';
import '../api/group_apis.dart';
import '../helper/dialogs.dart';
import '../helper/my_date_util.dart';
import '../main.dart';
import '../models/group.dart';
import '../models/group_message.dart';
import '../models/message.dart';
import '../widgets/group_message_card.dart';
import '../widgets/profile_image.dart';
import 'group_info_screen.dart';
import '../widgets/voice_message_recorder.dart';

class GroupChatScreen extends StatefulWidget {
  final Group group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _messageController = StreamController<List<GroupMessage>>.broadcast();
  final _groupInfoController = StreamController<Group>.broadcast();
  final _textController = TextEditingController();

  List<GroupMessage> _messages = [];
  Group? _currentGroup;
  GroupMessage? _replyToMessage;

  // UI State
  bool _showEmoji = false;
  bool _isUploading = false;
  bool _showSuggestions = false;
  bool _isLoadingSuggestions = false;
  Map<String, String> _aiSuggestions = {};
  Timer? _suggestionTimer;

  // Add state variable for voice recording
  bool _isRecordingVoice = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.close();
    _groupInfoController.close();
    _textController.dispose();
    _suggestionTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    // Subscribe to message updates
    GroupAPIs.getGroupMessages(widget.group.id).listen(_handleNewMessages);

    // Subscribe to group info updates
    GroupAPIs.getGroupById(widget.group.id).listen(_handleGroupInfoUpdate);
  }

  void _handleNewMessages(QuerySnapshot snapshot) {
    if (!mounted) return;

    final newMessages = snapshot.docs
        .map((doc) => GroupMessage.fromJson(doc.data() as Map<String, dynamic>))
        .toList();

    _messages = newMessages;
    _messageController.add(_messages);
  }

  void _handleGroupInfoUpdate(DocumentSnapshot snapshot) {
    if (!mounted || !snapshot.exists) return;

    final updatedGroup =
        Group.fromJson(snapshot.data() as Map<String, dynamic>);

    if (_currentGroup != updatedGroup) {
      _currentGroup = updatedGroup;
      _groupInfoController.add(_currentGroup!);
    }
  }

  void _clearReply() {
    setState(() => _replyToMessage = null);
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
        canPop: !_showEmoji,
        onPopInvoked: (didPop) {
          if (!didPop && _showEmoji) {
            setState(() => _showEmoji = false);
          }
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff1a1a1a)
              : const Color.fromARGB(255, 234, 248, 255),
          appBar: AppBar(
            automaticallyImplyLeading: false,
            flexibleSpace: _buildAppBar(),
            actions: [
              // Info button
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          GroupInfoScreen(group: _currentGroup ?? widget.group),
                    ),
                  );
                },
                icon: Icon(
                  Icons.more_vert,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                ),
              ),
            ],
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
              // Main UI
              SafeArea(
                bottom: true,
                child: Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<List<GroupMessage>>(
                        stream: _messageController.stream,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.group,
                                    size: 60,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white70
                                        : Colors.blue.withOpacity(0.7),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Say Hi to the group! 👋',
                                    style: TextStyle(
                                      fontSize: 20,
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return _buildMessageList(snapshot.data!);
                        },
                      ),
                    ),

                    // Show reply preview if replying to a message
                    if (_replyToMessage != null) _buildReplyPreview(),

                    // Show progress indicator when uploading
                    if (_isUploading)
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),

                    // Replace Padding with AnimatedContainer for chat input
                    _buildChatInput(),

                    // Show emoji picker when emoji button is pressed
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

  // Build app bar with group info
  Widget _buildAppBar() {
    return SafeArea(
      child: StreamBuilder<Group>(
        stream: _groupInfoController.stream,
        initialData: widget.group,
        builder: (context, snapshot) {
          final group = snapshot.data ?? widget.group;

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupInfoScreen(group: group),
                ),
              );
            },
            child: Row(
              children: [
                // Back button
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                ),

                // Group image
                ProfileImage(
                  url: group.image,
                  size: mq.height * .05,
                ),

                const SizedBox(width: 10),

                // Group info (name & members)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group name
                      Text(
                        group.name,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      // Member count
                      const SizedBox(height: 2),
                      Text(
                        '${group.members.length} members',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Build message list
  Widget _buildMessageList(List<GroupMessage> messages) {
    return ListView.builder(
      reverse: true,
      itemCount: messages.length,
      padding: EdgeInsets.only(top: mq.height * .01),
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        // Determine if we should show date separator
        bool showDateSeparator = false;

        if (index == messages.length - 1) {
          // Always show for the first message in the list
          showDateSeparator = true;
        } else {
          // Check if the date is different from the previous message
          final currentDate = MyDateUtil.getMessageDate(
            context: context,
            time: messages[index].sent,
          );

          final previousDate = MyDateUtil.getMessageDate(
            context: context,
            time: messages[index + 1].sent,
          );

          if (currentDate != previousDate) {
            showDateSeparator = true;
          }
        }

        return GroupMessageCard(
          message: messages[index],
          showDateSeparator: showDateSeparator,
          onReplyTap: (message) {
            setState(() => _replyToMessage = message);
            FocusScope.of(context).requestFocus(FocusNode());
          },
        );
      },
    );
  }

  // Build reply preview
  Widget _buildReplyPreview() {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: _replyToMessage!.type == Type.image ? 80 : 40,
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
                if (_replyToMessage!.type == Type.image)
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
                else if (_replyToMessage!.type == Type.video)
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
                      Text(
                        'Video message',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                      ),
                    ],
                  )
                else if (_replyToMessage!.type == Type.file)
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
                          _replyToMessage!.fileName ?? 'File',
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
                else if (_replyToMessage!.type == Type.audio)
                  Row(
                    children: [
                      Icon(
                        Icons.mic,
                        size: 14,
                        color: accentColor,
                      ),
                      const SizedBox(width: 6),
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
                    _replyToMessage!.msg,
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

  // Build emoji picker
  Widget _buildEmojiPicker() {
    return SizedBox(
      height: mq.height * .35,
      child: EmojiPicker(
        textEditingController: _textController,
        config: const Config(),
      ),
    );
  }

  // Build the chat input at the bottom
  Widget _buildChatInput() {
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
                    group: widget.group,
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
                                        : Icons.emoji_emotions,
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
                                  onTap: () {
                                    if (_showEmoji) {
                                      setState(() => _showEmoji = !_showEmoji);
                                    }
                                  },
                                  onChanged: (value) {
                                    setState(() {
                                      if (_showSuggestions) {
                                        _showSuggestions = false;
                                        _aiSuggestions.clear();
                                      }
                                    });
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
                            : _buildMicButton(),
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

  // Microphone button widget
  Widget _buildMicButton() {
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
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
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

  // Handle image selection from gallery or camera
  Future<void> _handleImageSelection(ImageSource source,
      {bool multiple = false}) async {
    try {
      final ImagePicker picker = ImagePicker();

      if (multiple) {
        final List<XFile> images =
            await picker.pickMultiImage(imageQuality: 70);
        for (var image in images) {
          setState(() => _isUploading = true);

          try {
            await GroupAPIs.uploadImageToTelegram(
              File(image.path),
              _currentGroup ?? widget.group,
              _replyToMessage?.msg,
            );
          } finally {
            if (mounted) {
              setState(() => _isUploading = false);
            }
          }
        }
      } else {
        final XFile? image = await picker.pickImage(
          source: source,
          imageQuality: 70,
        );

        if (image != null) {
          setState(() => _isUploading = true);

          try {
            await GroupAPIs.uploadImageToTelegram(
              File(image.path),
              _currentGroup ?? widget.group,
              _replyToMessage?.msg,
            );
          } finally {
            if (mounted) {
              setState(() => _isUploading = false);
            }
          }
        }
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        Dialogs.showSnackbar(
          context,
          'Failed to select image',
        );
      }
    }
  }

  // Handle file selection
  Future<void> _handleFileSelection() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );

      if (result != null) {
        for (PlatformFile file in result.files) {
          if (file.path != null) {
            // Check file size (limit to 10MB)
            if (file.size > 10 * 1024 * 1024) {
              if (mounted) {
                Dialogs.showSnackbar(
                  context,
                  'File size should be less than 10MB',
                );
              }
              continue;
            }

            setState(() => _isUploading = true);

            try {
              await GroupAPIs.uploadFileToTelegram(
                File(file.path!),
                _currentGroup ?? widget.group,
                Type.file,
                file.name,
                file.size,
                file.extension,
                _replyToMessage?.msg,
              );
            } finally {
              if (mounted) {
                setState(() => _isUploading = false);
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error picking file: $e');
      if (mounted) {
        Dialogs.showSnackbar(
          context,
          'Failed to select file',
        );
      }
    }
  }

  // Send text message
  Future<void> _sendMessage(String text, Type type) async {
    if (text.trim().isEmpty) return;

    // Clear text field immediately
    _textController.clear();

    // Get reply data if replying
    String? replyData;
    if (_replyToMessage != null) {
      if (_replyToMessage!.type == Type.image) {
        replyData = _replyToMessage!.msg; // URL of the image
      } else if (_replyToMessage!.type == Type.file) {
        replyData = _replyToMessage!.fileName != null
            ? "file:${_replyToMessage!.fileName}"
            : "file:Unknown file";
      } else {
        replyData = _replyToMessage!.msg;
      }
    }

    // Clear reply immediately after sending
    _clearReply();

    try {
      // Send the message
      await GroupAPIs.sendGroupMessage(
        group: _currentGroup ?? widget.group,
        msg: text,
        type: type,
        replyTo: replyData,
      );
    } catch (e) {
      // Show error message
      if (mounted) {
        Dialogs.showSnackbar(
          context,
          'Failed to send message. Please try again.',
        );
      }
    }
  }

  // Get user name from ID
  String _getNameFromId(String userId) {
    // If it's the current user, return "You"
    if (userId == APIs.user.uid) {
      return "You";
    }

    // For other users, return a generic name
    return "User";
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

  // Add this method to build suggestion cards
  Widget _buildSuggestionCard(
      String style, String suggestion, IconData icon, Color color) {
    return GestureDetector(
      onTap: () {
        _textController.text = suggestion;
        setState(() {
          _showSuggestions = false;
          _aiSuggestions.clear();
        });
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2A2A2A)
            : Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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

  // Add this method to handle location sharing
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
            Dialogs.showSnackbar(
              context,
              'Video size should be less than 50MB',
            );
          }
          return;
        }

        setState(() => _isUploading = true);

        try {
          // Get reply data if replying
          String? replyData;
          if (_replyToMessage != null) {
            if (_replyToMessage!.type == Type.video) {
              replyData = "video:${_replyToMessage!.msg}";
            } else if (_replyToMessage!.type == Type.image) {
              replyData = _replyToMessage!.msg;
            } else if (_replyToMessage!.type == Type.file) {
              replyData = "file:${_replyToMessage!.fileName ?? 'Unknown file'}";
            } else {
              replyData = _replyToMessage!.msg;
            }
          }

          // Upload the video
          await GroupAPIs.uploadFileToTelegram(
            File(video.path),
            _currentGroup ?? widget.group,
            Type.video,
            video.name,
            videoSize,
            'video/mp4',
            replyData,
          );

          // Clear reply after successful upload
          _clearReply();
        } finally {
          if (mounted) {
            setState(() => _isUploading = false);
          }
        }
      }
    } catch (e) {
      print('Error picking video: $e');
      if (mounted) {
        Dialogs.showSnackbar(
          context,
          'Failed to select video',
        );
      }
    }
  }
}
