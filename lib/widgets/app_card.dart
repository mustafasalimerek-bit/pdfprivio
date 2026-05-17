import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/layout.dart';

/// White rounded container that groups one or more [CardRow]s.
///
/// Named `AppCard` to avoid collision with Flutter's built-in
/// [Card] widget — same intent, different default styling
/// (cream-background palette, 14pt corner radius, no elevation).
class AppCard extends StatelessWidget {
  final List<Widget> children;

  const AppCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Layout.cardCornerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// Row inside an [AppCard]. Single-tap full-bleed InkWell, with a
/// hair divider beneath unless [isLast] is set.
class CardRow extends StatelessWidget {
  final Widget leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isLast;

  const CardRow({
    super.key,
    required this.leading,
    this.trailing,
    this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.all(Layout.cardInternalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: leading),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onTap != null)
          Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: row),
          )
        else
          row,
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: Layout.cardDividerInset),
            child: Divider(
              height: 1,
              thickness: 1,
              color: AppColors.border.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }
}

/// Icon + title + optional subtitle — the standard left-side payload
/// for a [CardRow]. Wraps the soft-teal icon container ([Layout.iconContainerSize]).
class CardRowLeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const CardRowLeading({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: Layout.iconContainerSize,
          height: Layout.iconContainerSize,
          decoration: BoxDecoration(
            color: AppColors.iconTint,
            borderRadius:
                BorderRadius.circular(Layout.iconContainerCornerRadius),
          ),
          child: Icon(icon, color: AppColors.primary, size: Layout.iconSize),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Right-aligned grey value (e.g. "Mustafa", "Match system") shown
/// inside a row. Caller picks either this or a Switch / chevron.
class CardRowTrailingValue extends StatelessWidget {
  final String text;

  const CardRowTrailingValue(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Grey chevron, ~14pt, identical position across rows.
class CardRowChevron extends StatelessWidget {
  const CardRowChevron({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.chevron_right,
      color: AppColors.textTertiary,
      size: 18,
    );
  }
}
