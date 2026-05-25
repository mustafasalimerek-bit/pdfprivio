import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/pdf_compare_service.dart';
import '../../widgets/privacy_badge.dart';

class CompareResultScreen extends StatelessWidget {
  final CompareOutcome outcome;
  final String leftName;
  final String rightName;

  const CompareResultScreen({
    super.key,
    required this.outcome,
    required this.leftName,
    required this.rightName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Differences'),
      ),
      body: SafeArea(
        child: MaxWidthBody(
          child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PrivacyBadge(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _Summary(
                outcome: outcome,
                leftName: leftName,
                rightName: rightName,
              ),
            ),
            Expanded(
              child: outcome.isIdentical
                  ? const _IdenticalCard()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: outcome.pages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _PageDiffCard(diff: outcome.pages[index]);
                      },
                    ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final CompareOutcome outcome;
  final String leftName;
  final String rightName;

  const _Summary({
    required this.outcome,
    required this.leftName,
    required this.rightName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Side(
                  label: 'Left',
                  name: leftName,
                  pageCount: outcome.leftPageCount,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.compare_arrows, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: _Side(
                  label: 'Right',
                  name: rightName,
                  pageCount: outcome.rightPageCount,
                ),
              ),
            ],
          ),
          const Divider(height: 22, color: AppColors.border),
          Row(
            children: [
              _Stat(
                label: 'Pages changed',
                value: '${outcome.changedPages}',
                color: outcome.isIdentical
                    ? AppColors.textSecondary
                    : AppColors.primary,
              ),
              const _StatDivider(),
              _Stat(
                label: 'Added',
                value: '+${outcome.totalAdditions}',
                color: AppColors.success,
              ),
              const _StatDivider(),
              _Stat(
                label: 'Removed',
                value: '-${outcome.totalDeletions}',
                color: AppColors.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  final String label;
  final String name;
  final int pageCount;
  const _Side({
    required this.label,
    required this.name,
    required this.pageCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '$pageCount pages',
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: AppColors.border,
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

class _PageDiffCard extends StatelessWidget {
  final PageDiff diff;
  const _PageDiffCard({required this.diff});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: diff.isUnchanged
              ? AppColors.border
              : AppColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: diff.isUnchanged
                      ? AppColors.textTertiary.withValues(alpha: 0.15)
                      : AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Page ${diff.pageIndex + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: diff.isUnchanged
                        ? AppColors.textSecondary
                        : AppColors.primary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              if (!diff.isUnchanged) ...[
                Text(
                  '+${diff.additions}',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '-${diff.deletions}',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ] else
                const Text(
                  'No changes',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
          if (!diff.isUnchanged) ...[
            const SizedBox(height: 10),
            SelectableText.rich(
              _buildDiffSpan(diff.segments),
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  TextSpan _buildDiffSpan(List<DiffSegment> segments) {
    final spans = <TextSpan>[];
    for (final s in segments) {
      switch (s.op) {
        case DiffOp.equal:
          // Trim huge equal blocks to a single ellipsis line so the diff
          // stays scannable. We keep up to 200 chars of context on either
          // side of changes for readability.
          spans.add(TextSpan(text: s.text));
        case DiffOp.insert:
          spans.add(TextSpan(
            text: s.text,
            style: TextStyle(
              backgroundColor: AppColors.success.withValues(alpha: 0.22),
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ));
        case DiffOp.delete:
          spans.add(TextSpan(
            text: s.text,
            style: TextStyle(
              backgroundColor: AppColors.error.withValues(alpha: 0.18),
              color: AppColors.error,
              decoration: TextDecoration.lineThrough,
              decorationColor: AppColors.error,
            ),
          ));
      }
    }
    return TextSpan(children: spans);
  }
}

class _IdenticalCard extends StatelessWidget {
  const _IdenticalCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 52,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Identical text',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'These two PDFs have the same text content. Visual changes '
              "(layout, images) aren't compared yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
