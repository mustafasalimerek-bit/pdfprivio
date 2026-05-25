import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_text_extract_service.dart';
import '../../data/services/share_service.dart';
import '../../widgets/privacy_badge.dart';

class ExtractTextResultScreen extends StatelessWidget {
  final TextExtractOutcome outcome;
  final String sourceName;

  const ExtractTextResultScreen({
    super.key,
    required this.outcome,
    required this.sourceName,
  });

  Future<void> _copyAll(BuildContext context) async {
    HapticsService.instance.tap();
    await Clipboard.setData(ClipboardData(text: outcome.fullText));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportTxt(BuildContext context) async {
    HapticsService.instance.tap();
    final file = await PdfTextExtractService.instance.writeAsTextFile(
      baseName: sourceName,
      text: outcome.fullText,
    );
    if (!context.mounted) return;
    await ShareService.shareWithFeedback(
      context,
      ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: ShareService.originFromContext(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = outcome.pagesText.length;
    final empty = outcome.charCount == 0;
    final words = outcome.charCount == 0
        ? 0
        : (outcome.charCount / 5).round();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Extracted text'),
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
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    _Stat(label: 'Pages', value: '$pageCount'),
                    const _Divider(),
                    _Stat(label: 'Words', value: '~$words'),
                    const _Divider(),
                    _Stat(label: 'Characters', value: '${outcome.charCount}'),
                  ],
                ),
              ),
            ),
            if (outcome.wasMostlyEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 18,
                        color: AppColors.warning,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "This PDF looks like a scan with no embedded text. "
                          "Run the OCR tool first to recognise the words from "
                          "the page images, then come back here.",
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: empty
                  ? const _EmptyResult()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: pageCount,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final text = outcome.pagesText[index].trim();
                        return _PageBlock(
                          pageNumber: index + 1,
                          text: text.isEmpty
                              ? '(no text on this page — likely a scanned '
                                  "image)"
                              : text,
                          isEmpty: text.isEmpty,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: empty ? null : () => _copyAll(context),
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy all'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: empty ? null : () => _exportTxt(context),
                      icon: const Icon(Icons.text_snippet_outlined),
                      label: const Text('Export as .txt'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.border,
    );
  }
}

class _PageBlock extends StatelessWidget {
  final int pageNumber;
  final String text;
  final bool isEmpty;

  const _PageBlock({
    required this.pageNumber,
    required this.text,
    required this.isEmpty,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
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
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Page $pageNumber',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              if (!isEmpty)
                Text(
                  '${text.length} chars',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: isEmpty
                  ? AppColors.textTertiary
                  : AppColors.textPrimary,
              fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.text_fields,
              size: 48,
              color: AppColors.textTertiary,
            ),
            SizedBox(height: 12),
            Text(
              'No text layer found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'This PDF was likely scanned. Once OCR ships you can '
              'recognise text from the page images directly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
