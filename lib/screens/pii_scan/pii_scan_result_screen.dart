import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_pii_scan_service.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/privacy_badge.dart';
import '../redact/redact_screen.dart';

class PiiScanResultScreen extends StatelessWidget {
  final PiiScanOutcome outcome;
  final String sourceName;
  final PdfDocument? sourceDoc;

  const PiiScanResultScreen({
    super.key,
    required this.outcome,
    required this.sourceName,
    this.sourceDoc,
  });

  void _redactAll(BuildContext context) {
    HapticsService.instance.tap();
    final terms = <String>{};
    for (final m in outcome.matches) {
      final t = m.matchedText.trim();
      if (t.length >= 3) terms.add(t);
    }
    if (terms.isEmpty || sourceDoc == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RedactScreen(
          initialDoc: sourceDoc,
          initialSearches: terms.toList(),
          initialCaseSensitive: true,
          heroTitle: 'Redact all PII findings',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFindings = outcome.hasFindings;
    final canRedact = hasFindings && sourceDoc != null;
    final byCategory = <PiiCategory, List<PiiMatch>>{};
    for (final m in outcome.matches) {
      byCategory.putIfAbsent(m.category, () => []).add(m);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan results'),
      ),
      body: SafeArea(
        child: MaxWidthBody(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: PrivacyBadge(),
            ),
            const SizedBox(height: 12),
            _SummaryCard(outcome: outcome),
            const SizedBox(height: 14),
            if (hasFindings) ...[
              const DisclaimerBanner(
                message: 'Pattern matching can miss things and flag '
                    'false positives. Verify each finding by eye before '
                    'sharing or redacting.',
              ),
              const SizedBox(height: 14),
            ],
            if (canRedact) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _redactAll(context),
                  icon: const Icon(Icons.format_color_fill),
                  label: Text(
                    'Redact all ${outcome.totalCount} finding'
                    '${outcome.totalCount == 1 ? '' : 's'}',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (outcome.wasMostlyEmpty)
              const _NoTextLayerHint()
            else if (!hasFindings)
              const _CleanHint()
            else ...[
              for (final cat in PiiCategory.values)
                if (byCategory.containsKey(cat))
                  _CategoryBlock(
                    category: cat,
                    matches: byCategory[cat]!,
                  ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final PiiScanOutcome outcome;
  const _SummaryCard({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final total = outcome.totalCount;
    final clean = total == 0 && !outcome.wasMostlyEmpty;
    final color = clean
        ? AppColors.success
        : (total > 0 ? AppColors.error : AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              clean
                  ? Icons.verified_outlined
                  : (total > 0 ? Icons.warning_amber_rounded : Icons.help_outline),
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clean
                      ? 'No PII detected'
                      : (total > 0
                          ? '$total finding${total == 1 ? '' : 's'}'
                          : 'No text to scan'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  total > 0
                      ? '${outcome.pagesWithFindings} of ${outcome.totalPages} '
                          'pages have matches'
                      : '${outcome.totalPages} pages scanned in '
                          '${outcome.elapsed.inMilliseconds} ms',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CleanHint extends StatelessWidget {
  const _CleanHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        "We didn't find SSNs, EINs, credit cards, IBANs, "
        "emails, or phone numbers. "
        "Patterns checked may not cover every regional ID — "
        "review by eye is still wise before sharing.",
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }
}

class _NoTextLayerHint extends StatelessWidget {
  const _NoTextLayerHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.primary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "This PDF has no text layer — likely a pure scan. "
              "Run the OCR tool first to add a text layer, then re-scan.",
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  final PiiCategory category;
  final List<PiiMatch> matches;
  const _CategoryBlock({required this.category, required this.matches});

  Color get _color {
    switch (category.severity) {
      case 'high':
        return AppColors.error;
      case 'medium':
        return Colors.orange.shade700;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      category.severity.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: _color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          category.description,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${matches.length}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            for (var i = 0; i < matches.length; i++) ...[
              _MatchRow(match: matches[i]),
              if (i != matches.length - 1)
                const Divider(height: 1, color: AppColors.border),
            ],
          ],
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  final PiiMatch match;
  const _MatchRow({required this.match});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        HapticsService.instance.select();
        await Clipboard.setData(ClipboardData(text: match.matchedText));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'p.${match.pageIndex + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    match.redactedPreview,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const Icon(
                  Icons.copy_outlined,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              match.contextSnippet,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
