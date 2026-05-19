import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/layout.dart';

/// Compact "Stays on your iPhone" / "On-device" pill — green status
/// dot + teal label on a soft-teal background. Used immediately
/// under the page title on Recent and other top-level surfaces, so
/// the on-device promise greets the user before any tool action.
class PrivacyPill extends StatelessWidget {
  final String text;

  const PrivacyPill({super.key, this.text = 'Stays on your device'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.pillHorizontalPadding,
        vertical: Layout.pillVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: AppColors.iconTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
