import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../../data/models/receipt.dart';
import '../../data/services/document_scanner_service.dart';
import '../../data/services/expense_ledger_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/image_to_pdf_service.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';
import '../merge/merge_result_screen.dart';

/// Scan → PDF entry point.
///
/// The native iOS scanner ([DocumentScannerService]) owns the capture
/// UI, the multi-page review, the perspective correction, the
/// enhancement modes, and the PDF assembly. This screen is now a thin
/// trigger: tap "Open scanner" → wait → push the finished PDF into the
/// shared Recent / share / save pipeline via [MergeResultScreen].
///
/// The simulator (and any device without a back camera) falls back to
/// picking photos and assembling them into a PDF via [ImageToPdfService]
/// so developers can still exercise the downstream flow without hardware.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool? _scannerAvailable;
  double? _progress;
  String? _status;
  CancellationToken? _cancel;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final avail = await DocumentScannerService.instance.isAvailable();
    if (!mounted) return;
    setState(() => _scannerAvailable = avail);
  }

  Future<void> _scan({ScanMode mode = ScanMode.doc}) async {
    HapticsService.instance.tap();
    final result =
        await DocumentScannerService.instance.scan(mode: mode);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        if (value.isEmpty || value.pdfFile == null) {
          HapticsService.instance.select();
          return;
        }
        HapticsService.instance.success();

        // Receipt mode with an extracted amount → offer the Expense
        // Ledger pre-fill before pushing the result screen. The PDF
        // gets saved either way.
        if (value.mode == ScanMode.receipt &&
            value.metadata?.extractedAmount != null) {
          await _maybePromptExpenseLedger(value);
          return;
        }

        await _pushResult(
          value.pdfFile!,
          sourceCount: _estimatePageCount(value.pdfFile!),
        );
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

  /// Receipt mode flow: shows a dialog with the extracted merchant /
  /// amount / date and asks the user whether to log it in the Expense
  /// Ledger. The actual ledger write lives in ExpenseLedgerService —
  /// wired in a follow-up task. For now we confirm intent and continue
  /// the normal save flow.
  Future<void> _maybePromptExpenseLedger(ScanOutcome outcome) async {
    final meta = outcome.metadata!;
    final amount = meta.extractedAmount;
    final date = meta.extractedDate ?? DateTime.now();
    final merchant = meta.extractedMerchant ?? 'Receipt';
    final currency = meta.extractedCurrency ?? 'USD';

    final addToLedger = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add to Expense Ledger?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Merchant: $merchant'),
            Text(
              'Amount: $currency ${amount?.toStringAsFixed(2) ?? '—'}',
            ),
            Text(
              'Date: ${date.toLocal().toString().split(' ').first}',
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap Add to track this in Expense Ledger. The receipt PDF '
              'is saved either way.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (addToLedger == true) {
      // Persist to the on-device ledger. Total stored as string to
      // dodge floating-point rounding. Currency falls back to USD if
      // the receipt parser couldn't pin it down.
      final receipt = Receipt(
        id: ExpenseLedgerService.instance.nextId(),
        capturedAt: DateTime.now(),
        date: meta.extractedDate,
        vendor: meta.extractedMerchant,
        total: amount?.toStringAsFixed(2),
        currency: meta.extractedCurrency ?? 'USD',
        sourcePath: outcome.pdfFile!.path,
        rawText: meta.ocrText ?? '',
      );
      await ExpenseLedgerService.instance.save(receipt);

      if (mounted) {
        HapticsService.instance.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to Expense Ledger'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    await _pushResult(
      outcome.pdfFile!,
      sourceCount: _estimatePageCount(outcome.pdfFile!),
    );
  }

  /// Cheap heuristic — we don't crack the PDF open here just for the
  /// page count, MergeResultScreen reads it properly. The "source count"
  /// is only used for the "X pages scanned" label.
  int _estimatePageCount(File pdf) => 1;

  Future<void> _pickPhotosFallback() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (res == null) return;
    final files = res.paths.whereType<String>().map((p) => File(p)).toList();
    if (files.isEmpty) return;
    await _buildPdfFromImages(files);
  }

  Future<void> _buildPdfFromImages(List<File> images) async {
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
      _status = 'Building PDF…';
    });

    final result = await ImageToPdfService.instance.convert(
      images: images,
      paperSize: PdfPaperSize.letter,
      outputName: 'scan',
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
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
        await _pushResult(value, sourceCount: images.length);
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

  Future<void> _pushResult(File pdf, {required int sourceCount}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MergeResultScreen(
          outputFile: pdf,
          sourceCount: sourceCount,
          toolLabel: 'Scanned',
          toolIdForUsage: 'scan_to_pdf',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan to PDF'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: _EmptyState(
              scannerAvailable: _scannerAvailable,
              onScan: _scan,
              onPickPhotos: _pickPhotosFallback,
            ),
          ),
          if (_progress != null)
            ProgressOverlay(
              progress: _progress,
              title: 'Building PDF',
              subtitle: _status ?? 'On this device — no upload',
              onCancel: () => _cancel?.cancel(),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool? scannerAvailable;
  final VoidCallback onScan;
  final VoidCallback onPickPhotos;
  const _EmptyState({
    required this.scannerAvailable,
    required this.onScan,
    required this.onPickPhotos,
  });

  @override
  Widget build(BuildContext context) {
    final ready = scannerAvailable == true;
    final noCamera = scannerAvailable == false;

    if (scannerAvailable == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ToolEmptyState(
      heroIcon: Icons.document_scanner_outlined,
      title: ready ? 'Scan to PDF' : 'Scanner needs a camera',
      subtitle: ready
          ? 'Auto-edge, auto-capture, 5 enhancement modes — on-device'
          : 'Use Photos to test the flow on simulator',
      primaryLabel: ready ? 'Open scanner' : 'Pick photos',
      primaryIcon: ready
          ? Icons.document_scanner_outlined
          : Icons.image_outlined,
      onPrimary: ready ? onScan : onPickPhotos,
      altSources: noCamera
          ? const []
          : [
              ToolAltSource(
                icon: Icons.image_outlined,
                label: 'Photos',
                onTap: onPickPhotos,
              ),
            ],
    );
  }
}
