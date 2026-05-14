import 'package:flutter/material.dart';

import '../core/theme/colors.dart';

/// Small pill that signals "this work is happening on-device".
///
/// Visible on every action screen so the user is constantly reminded of the
/// privacy guarantee — this is core brand positioning, not just decoration.
class PrivacyBadge extends StatelessWidget {
  final bool compact;
  const PrivacyBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 14,
            color: AppColors.success,
          ),
          const SizedBox(width: 6),
          Text(
            compact ? 'On-device' : 'Processing locally · 0 KB uploaded',
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
