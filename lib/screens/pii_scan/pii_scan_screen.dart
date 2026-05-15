import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../data/services/pdf_pii_scan_service.dart';
import '../../data/services/sample_pdf_service.dart';
import '../../data/services/usage_limits_service.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import 'pii_scan_result_screen.dart';

class PiiScanScreen extends ConsumerStatefulWidget {
  const PiiScanScreen({super.key});

  @override
  ConsumerState<PiiScanScreen> createState() => _PiiScanScreenState();
}

class _PiiScanScreenState extends ConsumerState<PiiScanScreen> {
  PdfDocument? _doc;
  double? _progress;
  String? _status;
  CancellationToken? _cancel;

  Future<void> _pick() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res == null) return;
    final path = res.paths.firstOrNull;
    if (path == null) return;

    final outcome = await PdfMetadataService.instance.inspect(File(path));
    if (!mounted) return;
    switch (outcome) {
      case Ok(:final value):
        setState(() => _doc = value);
        HapticsService.instance.select();
      case Err(:final kind, :final message):
        HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kind == FailureKind.needsPassword
                ? 'This PDF is password-protected — unlock it first.'
                : message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _trySample() async {
    HapticsService.instance.tap();
    final sample = await SamplePdfService.instance.piiSampleDoc();
    final outcome =
        await PdfMetadataService.instance.inspect(sample);
    if (!mounted) return;
    switch (outcome) {
      case Ok(:final value):
        setState(() => _doc = value);
        HapticsService.instance.select();
        // Auto-run the scan so the user lands on the result immediately —
        // the whole point of a sample is to see the tool *do* something.
        await _run();
      case Err(:final message):
        HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _run() async {
    final doc = _doc;
    if (doc == null) return;
    HapticsService.instance.tap();

    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
      _status = 'Starting…';
    });

    final result = await PdfPiiScanService.instance.scan(
      input: doc,
      onProgress: (p, m) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _status = m;
        });
      },
      cancel: cancel,
    );

    if (!mounted) return;
    setState(() {
      _progress = null;
      _status = null;
      _cancel = null;
    });

    switch (result) {
      case Ok(:final value):
        HapticsService.instance.success();
        UsageLimitsService.instance.recordUse('pii_scan');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PiiScanResultScreen(
              outcome: value,
              sourceName: doc.displayName,
              sourceDoc: doc,
            ),
          ),
        );
        if (mounted) setState(() => _doc = null);
      case Err(:final kind, :final message):
        HapticsService.instance.error();
        if (kind != FailureKind.cancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find sensitive data'),
        actions: [
          if (doc != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(() => _doc = null);
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PrivacyBadge(),
                  ),
                ),
                Expanded(
                  child: doc == null
                      ? _EmptyState(onPick: _pick, onTrySample: _trySample)
                      : _DocReady(doc: doc),
                ),
                if (doc != null && _progress == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _run,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Scan ${doc.pageCount} '
                          'page${doc.pageCount == 1 ? '' : 's'} for PII',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_progress != null)
            ProgressOverlay(
              progress: _progress,
              title: 'Scanning for sensitive data',
              subtitle: _status ?? 'On this device — no upload',
              onCancel: () => _cancel?.cancel(),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  final VoidCallback onTrySample;
  const _EmptyState({required this.onPick, required this.onTrySample});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Find PII before you send',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Scans every page for SSNs, EINs, credit cards, IBANs, '
              'emails, and phone numbers — so you know what is in your '
              'document before it goes out.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.add),
              label: const Text('Pick a PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onTrySample,
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('Try with a sample document'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocReady extends StatelessWidget {
  final PdfDocument doc;
  const _DocReady({required this.doc});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${doc.pageCount} pages · ${formatBytes(doc.sizeBytes)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: AppColors.primary, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Scans the PDF's text layer. Born-digital PDFs (Word, "
                  "Pages, web export) work instantly. Scanned PDFs need "
                  "OCR first — run OCR PDF on them, then come back here.",
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const DisclaimerBanner(
          message: 'Detection uses pattern matching with checksum '
              "validation (Luhn, IBAN, TC) — but it isn't perfect. "
              'Review findings by eye before sharing the document.',
        ),
      ],
    );
  }
}
