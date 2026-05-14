import 'package:flutter/material.dart';

import '../core/theme/colors.dart';

/// Modal progress overlay with a percentage, status text, and a Cancel button.
///
/// Use this for any operation longer than ~500ms. We deliberately show a
/// number (not just a spinner) because "indefinite spinner" is the #1 source
/// of "is this app frozen?" reviews for PDF utilities.
class ProgressOverlay extends StatelessWidget {
  /// 0.0 to 1.0. Null means indeterminate.
  final double? progress;
  final String title;
  final String? subtitle;
  final VoidCallback? onCancel;

  const ProgressOverlay({
    super.key,
    required this.title,
    this.progress,
    this.subtitle,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final pct = progress == null ? null : (progress! * 100).toStringAsFixed(0);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (pct != null)
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (onCancel != null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
