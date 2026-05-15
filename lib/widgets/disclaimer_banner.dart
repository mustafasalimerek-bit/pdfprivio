import 'package:flutter/material.dart';

import '../core/theme/colors.dart';

/// Subtle, recurring inline disclaimer. Used on the empty state and the
/// result screen of any tool whose output could lull a user into thinking
/// it's a substitute for human review (PII scan, redact, sign).
///
/// We surface these in the UI — not buried in ToS — because the failure
/// mode (e.g. a missed SSN leaking out) is high-cost for the user and we
/// want them visually reminded each time, not once at install.
class DisclaimerBanner extends StatelessWidget {
  final IconData icon;
  final String message;

  const DisclaimerBanner({
    super.key,
    this.icon = Icons.info_outline,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.warning,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
