import 'package:flutter/material.dart';
import '../../api/apis.dart';  // For API calls

import '../../helper/my_date_util.dart';
import '../../main.dart';
import '../../models/chat_user.dart';
import '../utils/constants.dart';
import '../widgets/profile_image.dart';

class ViewProfileScreen extends StatefulWidget {
  final ChatUser user;
  final String heroTag;

  const ViewProfileScreen({
    super.key, 
    required this.user,
    this.heroTag = AppConstants.viewProfileHeroTag,
  });

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.user.name),
          centerTitle: true,
          backgroundColor: theme.primaryColor,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: _handleMenuSelection,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Block User'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.report_problem, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Report User'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: mq.width * .05),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: mq.height * .03),
                  Hero(
                    tag: '${widget.heroTag}_${widget.user.id}',
                    child: ProfileImage(
                      size: mq.height * .2,
                      url: widget.user.image,
                    ),
                  ),
                  SizedBox(height: mq.height * .03),
                  Text(
                    widget.user.email,
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16),
                  ),
                  SizedBox(height: mq.height * .02),
                  _buildInfoRow('About: ', widget.user.about, theme),
                  SizedBox(height: mq.height * .02),
                  _buildInfoRow(
                    'Joined On: ',
                    MyDateUtil.getLastMessageTime(
                      context: context,
                      time: widget.user.createdAt,
                      showYear: true,
                    ),
                    theme,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
        ),
      ],
    );
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'block':
        _showActionDialog(
          'Block User',
          'Are you sure you want to block ${widget.user.name}?',
          _handleBlockUser,
        );
        break;
      case 'report':
        _showActionDialog(
          'Report User',
          'Are you sure you want to report ${widget.user.name}?',
          _handleReportUser,
        );
        break;
    }
  }

  void _showActionDialog(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text(
              'Confirm',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _handleBlockUser() async {
    try {
      // Show loading indicator
      _showLoadingDialog();
      
      // Call API to block user
      await APIs.blockUser(widget.user.id);
      
      if (mounted) {
        // Hide loading dialog
        Navigator.pop(context);
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.user.name} has been blocked'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        
        // Navigate back to previous screen
        Navigator.pop(context);
      }
    } catch (e) {
      // Hide loading dialog
      Navigator.pop(context);
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to block user: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleReportUser() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select reason for reporting:'),
            const SizedBox(height: 16),
            ..._buildReportOptions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildReportOptions() {
    final reportReasons = [
      'Inappropriate Content',
      'Harassment',
      'Spam',
      'Fake Account',
      'Other'
    ];

    return reportReasons.map((reason) {
      return ListTile(
        dense: true,
        title: Text(reason),
        leading: const Icon(Icons.report_problem_outlined),
        onTap: () => _submitReport(reason),
      );
    }).toList();
  }

  void _submitReport(String reason) async {
    try {
      // Close report options dialog
      Navigator.pop(context);
      
      // Show loading indicator
      _showLoadingDialog();
      
      // Call API to submit report
      await APIs.reportUser(widget.user.id, reason);
      
      if (mounted) {
        // Hide loading dialog
        Navigator.pop(context);
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.user.name} has been reported'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Hide loading dialog
      Navigator.pop(context);
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to report user: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
