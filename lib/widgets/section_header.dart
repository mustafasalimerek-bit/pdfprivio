import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/layout.dart';

/// Uppercase tertiary-grey label that sits above each [AppCard].
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 4,
        bottom: Layout.sectionHeaderToCardSpacing,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: Layout.sectionHeaderFontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: Layout.sectionHeaderLetterSpacing,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
