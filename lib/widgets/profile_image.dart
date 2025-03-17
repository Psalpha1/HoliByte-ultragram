import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ProfileImage extends StatelessWidget {
  final double size;
  final String url;
  final bool useCache;

  const ProfileImage({
    super.key,
    required this.size,
    required this.url,
    this.useCache = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipOval(
        child: url.isEmpty || !Uri.tryParse(url)!.hasScheme
            ? _buildDefaultImage(isDark)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildShimmerEffect(isDark),
                errorWidget: (context, url, error) =>
                    _buildDefaultImage(isDark),
                cacheKey: url,
                maxHeightDiskCache: (size * 2).toInt(),
                maxWidthDiskCache: (size * 2).toInt(),
              ),
      ),
    );
  }

  Widget _buildShimmerEffect(bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: Container(
        color: isDark ? Colors.grey[850] : Colors.white,
      ),
    );
  }

  Widget _buildDefaultImage(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[200],
      child: Icon(
        Icons.person,
        size: size * 0.7,
        color: isDark ? Colors.grey[400] : Colors.grey[500],
      ),
    );
  }
}
