import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/layout.dart';

/// Full-width teal CTA button with 14pt rounded corners (NOT a
/// capsule — that was the old Recent "Scan your first PDF" style;
/// the new system uses a softer rectangle).
class PrimaryButton extends StatelessWidget {
  final String title;
  final IconData? icon;
  final VoidCallback? onPressed;

  const PrimaryButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(
            vertical: Layout.primaryButtonVerticalPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(Layout.primaryButtonCornerRadius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 7),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
