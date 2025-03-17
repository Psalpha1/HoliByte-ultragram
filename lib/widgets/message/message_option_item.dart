import 'package:flutter/material.dart';

/// Modern option item for bottom sheet
class ModernOptionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool isDark;

  const ModernOptionItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    // Theme-adaptive colors
    final normalTextColor = isDark ? Colors.white : Colors.black87;
    final normalIconColor = isDark ? Colors.white : Colors.black87;
    final rippleColor = isDark ? Colors.white24 : Colors.black12;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: rippleColor,
        highlightColor: rippleColor.withOpacity(0.5),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? Colors.redAccent : normalIconColor,
                size: 22,
              ),
              const SizedBox(width: 24),
              Text(
                label,
                style: TextStyle(
                  color: isDestructive ? Colors.redAccent : normalTextColor,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
