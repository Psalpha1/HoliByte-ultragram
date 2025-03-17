import 'package:flutter/material.dart';

/// A custom page route that provides smooth transitions between pages with different gradient backgrounds
class GradientPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final List<Color> fromGradient;
  final List<Color> toGradient;
  
  GradientPageRoute({
    required this.page,
    required this.fromGradient,
    required this.toGradient,
    super.settings,
  }) : super(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
  
  /// Get the interpolated gradient colors based on the animation value
  List<Color> getAnimatedGradient(double animationValue) {
    if (fromGradient.length != toGradient.length) {
      // If gradients have different lengths, just return the target gradient
      return toGradient;
    }
    
    List<Color> animatedColors = [];
    
    for (int i = 0; i < fromGradient.length; i++) {
      final fromColor = fromGradient[i];
      final toColor = toGradient[i];
      
      final r = _lerpInt(fromColor.red, toColor.red, animationValue);
      final g = _lerpInt(fromColor.green, toColor.green, animationValue);
      final b = _lerpInt(fromColor.blue, toColor.blue, animationValue);
      final a = _lerpInt(fromColor.alpha, toColor.alpha, animationValue);
      
      animatedColors.add(Color.fromARGB(a, r, g, b));
    }
    
    return animatedColors;
  }
  
  /// Linear interpolation for integer values
  int _lerpInt(int start, int end, double t) {
    return (start + (end - start) * t).round();
  }
}

/// A widget that animates the background gradient during page transitions
class GradientTransitionBuilder extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;
  final List<Color> fromGradient;
  final List<Color> toGradient;
  
  const GradientTransitionBuilder({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    required this.fromGradient,
    required this.toGradient,
  });
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final gradientColors = _getAnimatedGradient(animation.value);
        
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: child,
        );
      },
      child: child,
    );
  }
  
  List<Color> _getAnimatedGradient(double animationValue) {
    if (fromGradient.length != toGradient.length) {
      return toGradient;
    }
    
    List<Color> animatedColors = [];
    
    for (int i = 0; i < fromGradient.length; i++) {
      final fromColor = fromGradient[i];
      final toColor = toGradient[i];
      
      final r = _lerpInt(fromColor.red, toColor.red, animationValue);
      final g = _lerpInt(fromColor.green, toColor.green, animationValue);
      final b = _lerpInt(fromColor.blue, toColor.blue, animationValue);
      final a = _lerpInt(fromColor.alpha, toColor.alpha, animationValue);
      
      animatedColors.add(Color.fromARGB(a, r, g, b));
    }
    
    return animatedColors;
  }
  
  int _lerpInt(int start, int end, double t) {
    return (start + (end - start) * t).round();
  }
} 