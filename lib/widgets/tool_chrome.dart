import 'package:flutter/material.dart';

import '../core/theme/colors.dart';

/// Shared chrome for the editorial tool-screen pattern. Every tool
/// screen has two states — empty (first open) and populated (file
/// picked / configured). These widgets capture the layout boiler-
/// plate so each tool screen only writes its own copy + hero +
/// per-tool content.

/// Empty state — hero glyph + title + subtitle + primary pill CTA
/// + optional alt-source chips + "Stays on your iPhone" footer.
class ToolEmptyState extends StatelessWidget {
  final Widget? hero;
  final IconData? heroIcon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final List<ToolAltSource> altSources;
  final bool showPrivacyFooter;

  const ToolEmptyState({
    super.key,
    this.hero,
    this.heroIcon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    this.primaryIcon = Icons.add,
    required this.onPrimary,
    this.altSources = const [],
    this.showPrivacyFooter = true,
  });

  @override
  Widget build(BuildContext context) {
    final heroWidget = hero ??
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: AppColors.iconTint,
            shape: BoxShape.circle,
          ),
          child: Icon(
            heroIcon ?? Icons.description_outlined,
            color: AppColors.primary,
            size: 40,
          ),
        );
    return Column(
      children: [
        const SizedBox(height: 24),
        const Spacer(),
        heroWidget,
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ToolPrimaryButton(
            label: primaryLabel,
            icon: primaryIcon,
            onTap: onPrimary,
          ),
        ),
        if (altSources.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Or pick from',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final s in altSources)
                ToolAltChip(icon: s.icon, label: s.label, onTap: s.onTap),
            ],
          ),
        ],
        const Spacer(),
        if (showPrivacyFooter)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 18),
            child: PrivacyFooter(),
          ),
      ],
    );
  }
}

/// Pill-shaped primary CTA. Full width within its parent.
class ToolPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;

  const ToolPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? onTap : null,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

/// Compact alt-source chip ("Photos" / "Recent" / "Scan") shown
/// under the primary CTA in empty states.
class ToolAltChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ToolAltChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ToolAltSource {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const ToolAltSource({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// "Stays on your iPhone" footer — pinned green dot + privacy
/// tagline. Lives at the bottom of empty states.
class PrivacyFooter extends StatelessWidget {
  const PrivacyFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Stays on your iPhone',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.success,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Centered summary strip shown at the top of a populated tool
/// screen — "3 files · 16 pages · ~2.3 MB" / "1 page · 280 KB".
class ToolSummaryStrip extends StatelessWidget {
  final String text;
  const ToolSummaryStrip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// White rounded card with optional dividers between children.
class ToolCard extends StatelessWidget {
  final List<Widget> children;
  final bool dividers;
  final EdgeInsets padding;

  const ToolCard({
    super.key,
    required this.children,
    this.dividers = false,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (dividers && i != children.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.border.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mini paper glyph — lines on a card. Used as the per-file thumb
/// in populated tool screens.
class ToolPaperGlyph extends StatelessWidget {
  final double width;
  final double height;
  const ToolPaperGlyph({super.key, this.width = 38, this.height = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(6, 9, 6, 0),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in const [22.0, 18.0, 14.0])
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Container(
                width: w,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.iconTint,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// File row inside a tool card — paper glyph + filename + meta on
/// the left, optional trailing widget on the right.
class ToolFileRow extends StatelessWidget {
  final String name;
  final String meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  const ToolFileRow({
    super.key,
    required this.name,
    required this.meta,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            const ToolPaperGlyph(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!,
            ] else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
