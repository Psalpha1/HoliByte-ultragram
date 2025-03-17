import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';

class MessageImageViewer {
  /// Shows a full screen image viewer
  static void showImageViewer(BuildContext context, String imageUrl,
      {String? heroTag}) {
    final TransformationController transformationController =
        TransformationController();
    final ValueNotifier<bool> isControlsVisible = ValueNotifier<bool>(true);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Function to handle double tap zoom
    void handleDoubleTapDown(TapDownDetails details) {
      if (transformationController.value != Matrix4.identity()) {
        // If already zoomed in, reset to default view
        transformationController.value = Matrix4.identity();
      } else {
        // Zoom in to where the user tapped
        final position = details.localPosition;
        final Matrix4 newMatrix = Matrix4.identity()
          ..translate(-position.dx * 2, -position.dy * 2)
          ..scale(3.0);
        transformationController.value = newMatrix;
      }
    }

    // Function to toggle controls visibility
    void toggleControls() {
      isControlsVisible.value = !isControlsVisible.value;
    }

    // Function to close dialog immediately
    void closeDialog() {
      transformationController.dispose();
      Navigator.of(context, rootNavigator: true).pop();
    }

    // Function to save image to gallery
    Future<void> saveImageToGallery(BuildContext dialogContext) async {
      try {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text('Saving image...'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );

        final result =
            await GallerySaver.saveImage(imageUrl, albumName: 'We Chat');

        if (result != null && result) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Image saved to gallery'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            const SnackBar(
              content: Text('Failed to save image'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        log('Error saving image: $e');
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    showDialog(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black.withOpacity(0.9),
      barrierDismissible: true,
      builder: (dialogContext) => GestureDetector(
        onTap: toggleControls,
        onDoubleTapDown: handleDoubleTapDown,
        onDoubleTap:
            () {}, // Empty function required for onDoubleTapDown to work
        child: WillPopScope(
          onWillPop: () async {
            transformationController.dispose();
            return true;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Interactive image viewer
              InteractiveViewer(
                transformationController: transformationController,
                minScale: 0.5,
                maxScale: 5.0,
                clipBehavior: Clip.none,
                panEnabled: true,
                scaleEnabled: true,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Hero(
                  tag: heroTag ?? imageUrl,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Loading image...',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.image_not_supported,
                                size: 50, color: Colors.white),
                            const SizedBox(height: 16),
                            Text(
                              'Failed to load image',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Controls overlay that can be toggled
              ValueListenableBuilder<bool>(
                valueListenable: isControlsVisible,
                builder: (context, isVisible, child) {
                  return AnimatedOpacity(
                    opacity: isVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: child,
                  );
                },
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Column(
                    children: [
                      // Top controls
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(
                              top: 32, left: 16, right: 16, bottom: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Save button
                              GestureDetector(
                                onTap: () => saveImageToGallery(dialogContext),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.download,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                              ),
                              // Close button
                              GestureDetector(
                                onTap: closeDialog,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom hint
                      const Spacer(),
                      Text(
                        'Double-tap to zoom',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to build bottom action buttons
  static Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
