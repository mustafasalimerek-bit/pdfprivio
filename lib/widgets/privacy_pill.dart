import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/layout.dart';
import '../core/utils/responsive.dart';

/// Compact "Stays on your iPhone" / "Stays on your iPad" pill — green
/// status dot + teal label on a soft-teal background. Used immediately
/// under the page title on Recent and other top-level surfaces, so
/// the on-device promise greets the user before any tool action.
class PrivacyPill extends StatelessWidget {
  /// Optional override. When null we render "Stays on your <noun>"
  /// where the noun matches the device class (iPhone vs iPad).
  final String? text;

  const PrivacyPill({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    final label = text ?? 'Stays on your ${Breakpoints.deviceNoun(context)}';
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
            label,
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
