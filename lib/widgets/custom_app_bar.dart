import 'package:flutter/material.dart';
import '../api/apis.dart';
import '../utils/constants.dart';
import 'profile_image.dart';
import '../screens/profile_screen.dart';

class CustomAppBar extends StatelessWidget {
  final String title;
  final VoidCallback? onProfileUpdated;
  final List<Color>? gradientColors;
  final Alignment gradientBegin;
  final Alignment gradientEnd;
  final bool isTransparent;
  final String heroTag;
  
  const CustomAppBar({
    super.key,
    required this.title,
    this.onProfileUpdated,
    this.gradientColors,
    this.gradientBegin = Alignment.topLeft,
    this.gradientEnd = Alignment.bottomRight,
    this.isTransparent = true,
    this.heroTag = 'profile',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppConstants.appBarHeight,
      padding: AppConstants.appBarPadding,
      decoration: !isTransparent && gradientColors != null ? BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors!,
          begin: gradientBegin,
          end: gradientEnd,
        ),
      ) : null,
      child: Row(
        children: [
          // Profile button
          IconButton(
            tooltip: 'View Profile',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfileScreen(
                  user: APIs.me,
                  heroTag: heroTag,
                )),
              );

              if (result == true && onProfileUpdated != null) {
                onProfileUpdated!();
              }
            },
            icon: Hero(
              tag: '${heroTag}_${APIs.me.id}',
              child: ProfileImage(size: AppConstants.appBarIconSize, url: APIs.me.image),
            ),
          ),

          // Centered title
          Expanded(
            child: Center(
              child: Text(
                title,
                style: AppConstants.appBarTitleStyle,
              ),
            ),
          ),

          // Placeholder to maintain symmetry
          const SizedBox(width: 48),
        ],
      ),
    );
  }
} 