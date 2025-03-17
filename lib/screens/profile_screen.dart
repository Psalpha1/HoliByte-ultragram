import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:we_chat/helper/debouncer.dart';
import 'package:we_chat/screens/auth/loginOrRegister.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:we_chat/themes/theme_provider.dart';
import 'package:we_chat/widgets/profile_image.dart';
import 'package:flutter/services.dart';

import '../../api/apis.dart';
import '../../helper/dialogs.dart';
import '../../main.dart';
import '../../models/chat_user.dart';

class ProfileScreen extends StatefulWidget {
  final ChatUser user;
  final String heroTag;

  const ProfileScreen({
    super.key,
    required this.user,
    this.heroTag = 'profile',
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  final _debouncer = Debouncer(milliseconds: 500);
  bool _isLoading = false;
  String? _image;
  final _formKey = GlobalKey<FormState>();
  bool _isImagePrecached = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Precache the network image only once
    if (!_isImagePrecached && widget.user.image.isNotEmpty) {
      precacheImage(
        CachedNetworkImageProvider(widget.user.image),
        context,
      );
      _isImagePrecached = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FloatingActionButton(
            backgroundColor: Colors.redAccent,
            onPressed: () async {
              //for showing progress dialog
              Dialogs.showLoading(context);

              await APIs.updateActiveStatus(false);

              //sign out from app
              await APIs.auth.signOut().then((value) async {
                await GoogleSignIn().signOut().then((value) {
                  //for hiding progress dialog
                  Navigator.pop(context);

                  //for moving to home screen
                  Navigator.pop(context);

                  //replacing home screen with login screen
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginOrRegister()),
                  );
                });
              });
            },
            child: const Icon(
              Icons.logout,
              color: Colors.white,
            ),
          ),
        ),
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue.shade400,
                Colors.purple.shade300,
                Colors.pink.shade200,
              ],
              transform: GradientRotation(
                  DateTime.now().millisecondsSinceEpoch / 5000),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.all(mq.width * .05),
                        child: Column(
                          children: [
                            _buildProfileImage(),
                            SizedBox(height: mq.height * .02),
                            _buildEmailWidget(),
                            SizedBox(height: mq.height * .03),
                            _buildForm(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      toolbarHeight: 80,
      leadingWidth: 54,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Edit Profile',
        style: TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => AnimatedThemeSwitcher(
              onPressed: _toggleTheme,
              isDarkMode: themeProvider.isDarkMode,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileImage() {
    return Hero(
      tag: '${widget.heroTag}_${widget.user.id}',
      child: Stack(
        children: [
          if (_isLoading)
            _buildShimmerEffect()
          else if (_image != null)
            Container(
              width: mq.height * .2,
              height: mq.height * .2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.file(
                  File(_image!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildErrorWidget(),
                ),
              ),
            )
          else
            ProfileImage(
              size: mq.height * .2,
              url: widget.user.image,
              useCache: true,
            ),
          Positioned(
            bottom: 0,
            right: 0,
            child: _buildEditButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildEditButton() {
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      color: Colors.blue,
      child: InkWell(
        onTap: _showBottomSheet,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(
            Icons.edit,
            color: Colors.white,
            size: mq.height * .022,
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerEffect() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        width: mq.height * .2,
        height: mq.height * .2,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: mq.height * .2,
      height: mq.height * .2,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        size: mq.height * .1,
        color: Colors.grey[400],
      ),
    );
  }

  Widget _buildEmailWidget() {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: TextStyle(
        fontSize: 16,
        color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black54,
        fontWeight: FontWeight.w500,
      ),
      child: Text(widget.user.email),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildNameField(),
          SizedBox(height: mq.height * .02),
          _buildAboutField(),
          SizedBox(height: mq.height * .04),
          _buildUpdateButton(),
          SizedBox(height: mq.height * .04),
          _buildSettingsSection(),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).cardColor,
      ),
      child: TextFormField(
        initialValue: widget.user.name,
        onSaved: (val) => APIs.me.name = val ?? '',
        validator: (val) =>
            val != null && val.isNotEmpty ? null : 'Required Field',
        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.person, color: Colors.blue),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          hintText: 'eg. Happy Singh',
          label: const Text('Name'),
          hintStyle:
              TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
        ),
      ),
    );
  }

  Widget _buildAboutField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).cardColor,
      ),
      child: TextFormField(
        initialValue: widget.user.about,
        onSaved: (val) => APIs.me.about = val ?? '',
        validator: (val) =>
            val != null && val.isNotEmpty ? null : 'Required Field',
        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.info_outline, color: Colors.blue),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          hintText: 'eg. Feeling Happy',
          label: const Text('About'),
          hintStyle:
              TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
        ),
      ),
    );
  }

  Widget _buildUpdateButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: Size(mq.width * .5, mq.height * .06),
      ),
      onPressed: _updateProfile,
      icon: const Icon(Icons.save, size: 28),
      label: const Text('SAVE CHANGES', style: TextStyle(fontSize: 16)),
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 16.0),
          child: Text(
            'Settings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
        ),
        _buildSettingsTile(
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          onTap: () {
            HapticFeedback.mediumImpact();
            Dialogs.showComingSoon(context, 'This settings ');
          },
        ),
        const Divider(height: 1),
        _buildSettingsTile(
          icon: Icons.security_outlined,
          title: 'Privacy & Security',
          onTap: () {
            HapticFeedback.mediumImpact();
            Dialogs.showComingSoon(context, 'Privacy settings');
          },
        ),
        const Divider(height: 1),
        _buildSettingsTile(
          icon: Icons.settings_outlined,
          title: 'General Settings',
          onTap: () {
            HapticFeedback.mediumImpact();
            Dialogs.showComingSoon(context, 'General settings');
          },
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          icon,
          color: Colors.blue,
          size: 24,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).textTheme.titleMedium?.color,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
      ),
    );
  }

  void _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Save form data
      _formKey.currentState!.save();

      // Update profile picture if a new image was selected
      if (_image != null) {
        final String? newImageUrl =
            await APIs.updateProfilePicture(File(_image!));
        if (newImageUrl != null) {
          // Clear the cached image
          await DefaultCacheManager().removeFile(widget.user.image);

          // Update the user's image URL
          widget.user.image = newImageUrl;
          APIs.me.image = newImageUrl;

          // Pre-cache the new image
          if (mounted) {
            await precacheImage(
              NetworkImage(newImageUrl),
              context,
            );
          }
        }
      }

      // Update user info
      await APIs.updateUserInfo();

      if (mounted) {
        Dialogs.showSnackbar(context, 'Profile Updated Successfully!');
        // Return true to indicate profile was updated
        Navigator.pop(context, true);
      }
    } catch (e) {
      log('Error updating profile: $e');
      if (mounted) {
        Dialogs.showSnackbar(
            context, 'Failed to update profile: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (_) {
        return ListView(
          shrinkWrap: true,
          padding:
              EdgeInsets.only(top: mq.height * .03, bottom: mq.height * .05),
          children: [
            const Text(
              'Pick Profile Picture',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: mq.height * .02),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildImagePickerButton(
                  'assets/images/add_image.png',
                  ImageSource.gallery,
                ),
                _buildImagePickerButton(
                  'assets/images/camera.png',
                  ImageSource.camera,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildImagePickerButton(String assetPath, ImageSource source) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        shape: const CircleBorder(),
        fixedSize: Size(mq.width * .3, mq.height * .15),
      ),
      onPressed: () async {
        final ImagePicker picker = ImagePicker();
        final XFile? image =
            await picker.pickImage(source: source, imageQuality: 80);
        if (image != null) {
          log('Image Path: ${image.path}');

          setState(() {
            _image = image.path; // Store local image path
          });

          Navigator.pop(context); // Close bottom sheet
        }
      },
      child: Image.asset(assetPath),
    );
  }

  void _toggleTheme() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    themeProvider.toggleTheme();
  }
}

// Create this new widget class in profile_screen.dart
class AnimatedThemeSwitcher extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDarkMode;

  const AnimatedThemeSwitcher({
    super.key,
    required this.onPressed,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 200),
      scale: 1.0,
      child: IconButton(
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: animation.value * 2.0 * 3.14159,
                  child: child,
                );
              },
              child: child,
            );
          },
          child: Icon(
            isDarkMode ? Icons.light_mode : Icons.dark_mode,
            key: ValueKey<bool>(isDarkMode),
            color: Colors.white,
            size: 24,
          ),
        ),
        onPressed: () {
          onPressed();
        },
      ),
    );
  }
}
