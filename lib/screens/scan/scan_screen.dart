import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../../data/services/document_scanner_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/image_to_pdf_service.dart';
import '../../data/services/ocr_service.dart';
import '../../data/services/pdf_ocr_compose_service.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import '../merge/merge_result_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final List<File> _pages = [];
  PdfPaperSize _paperSize = PdfPaperSize.letter;
  bool? _scannerAvailable;
  bool _makeSearchable = true; // OCR by default — biggest user win
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

  Future<void> _scan() async {
    HapticsService.instance.tap();
    final result = await DocumentScannerService.instance.scan();
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        if (value.isEmpty) {
          HapticsService.instance.select();
          return;
        }
        setState(() => _pages.addAll(value.pages));
        HapticsService.instance.success();
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

  Future<void> _pickPhotosFallback() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (res == null) return;
    final files = res.paths.whereType<String>().map((p) => File(p)).toList();
    if (files.isEmpty) return;
    setState(() => _pages.addAll(files));
    HapticsService.instance.select();
  }

  void _remove(int i) {
    HapticsService.instance.select();
    setState(() => _pages.removeAt(i));
  }

  void _reorder(int oldIndex, int newIndex) {
    HapticsService.instance.drop();
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    setState(() {
      final item = _pages.removeAt(oldIndex);
      _pages.insert(adjusted, item);
    });
  }

  Future<void> _savePdf() async {
    if (_pages.isEmpty) return;
    HapticsService.instance.tap();
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
      _status = _makeSearchable ? 'Starting OCR…' : 'Building PDF…';
    });

    final File? output;
    final int sourceCount = _pages.length;

    if (_makeSearchable) {
      output = await _runOcrPipeline(cancel);
    } else {
      final result = await ImageToPdfService.instance.convert(
        images: _pages,
        paperSize: _paperSize,
        outputName: 'scan',
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancel: cancel,
      );
      switch (result) {
        case Ok(:final value):
          output = value;
        case Err(:final kind, :final message):
          _finishWithError(kind, message);
          return;
      }
    }

    if (!mounted) return;
    setState(() {
      _progress = null;
      _status = null;
      _cancel = null;
    });

    if (output == null) return; // pipeline already handled error/cancel

    HapticsService.instance.success();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MergeResultScreen(
          outputFile: output!,
          sourceCount: sourceCount,
          toolLabel: 'Scanned',
          toolIdForUsage: 'scan_to_pdf',
        ),
      ),
    );
    if (mounted) setState(_pages.clear);
  }

  /// OCR each scanned page, then compose a searchable PDF. Returns the
  /// output file on success, null on cancel/error (state already reset).
  Future<File?> _runOcrPipeline(CancellationToken cancel) async {
    final composed = <OcrComposedPage>[];
    for (var i = 0; i < _pages.length; i++) {
      if (cancel.isCancelled) {
        _finishWithError(FailureKind.cancelled, 'Cancelled');
        return null;
      }
      if (mounted) {
        setState(() {
          _progress = 0.85 * (i / _pages.length);
          _status = 'Recognizing page ${i + 1} of ${_pages.length}';
        });
      }
      final ocr = await OcrService.instance.recognize(
        image: _pages[i],
        languages: const ['en-US', 'tr-TR'],
      );
      if (ocr is Err<OcrPageResult>) {
        _finishWithError(ocr.kind, ocr.message);
        return null;
      }
      composed.add(OcrComposedPage(
        image: _pages[i],
        ocr: (ocr as Ok<OcrPageResult>).value,
      ));
    }

    if (mounted) {
      setState(() {
        _progress = 0.86;
        _status = 'Building searchable PDF…';
      });
    }

    final composeRes = await PdfOcrComposeService.instance.compose(
      pages: composed,
      outputName: 'searchable_scan',
      onProgress: (p, msg) {
        if (!mounted) return;
        setState(() {
          _progress = 0.86 + 0.14 * p;
          _status = msg;
        });
      },
      cancel: cancel,
    );

    switch (composeRes) {
      case Ok(:final value):
        return value.outputFile;
      case Err(:final kind, :final message):
        _finishWithError(kind, message);
        return null;
    }
  }

  void _finishWithError(FailureKind kind, String message) {
    if (!mounted) return;
    setState(() {
      _progress = null;
      _status = null;
      _cancel = null;
    });
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

  @override
  Widget build(BuildContext context) {
    final hasPages = _pages.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan to PDF'),
        actions: [
          if (hasPages)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(_pages.clear);
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
                  child: hasPages
                      ? _PagesGrid(
                          pages: _pages,
                          paperSize: _paperSize,
                          onPaperSize: (s) =>
                              setState(() => _paperSize = s),
                          onRemove: _remove,
                          onReorder: _reorder,
                          onAddMore: _scannerAvailable == true
                              ? _scan
                              : _pickPhotosFallback,
                          scannerAvailable: _scannerAvailable == true,
                          makeSearchable: _makeSearchable,
                          onMakeSearchableChanged: (v) {
                            HapticsService.instance.select();
                            setState(() => _makeSearchable = v);
                          },
                        )
                      : _EmptyState(
                          scannerAvailable: _scannerAvailable,
                          onScan: _scan,
                          onPickPhotos: _pickPhotosFallback,
                        ),
                ),
                if (hasPages && _progress == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _savePdf,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _makeSearchable
                              ? 'Save searchable PDF · ${_pages.length} '
                                  'page${_pages.length == 1 ? '' : 's'}'
                              : 'Save as PDF · ${_pages.length} '
                                  'page${_pages.length == 1 ? '' : 's'}',
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
              title: _makeSearchable
                  ? 'OCR + searchable PDF'
                  : 'Building PDF',
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
                Icons.document_scanner_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              ready
                  ? 'Scan paper into a sharp PDF'
                  : noCamera
                      ? 'Scanner needs a camera'
                      : 'Checking camera…',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              ready
                  ? 'Apple VisionKit handles edge detection, perspective '
                      'correction, and multi-page capture. Output is JPEG '
                      'per page, then combined into one PDF.'
                  : noCamera
                      ? "Real scanning needs a rear camera (iPhone or iPad). "
                          "On the simulator you can pick photos instead to "
                          "test the Save-as-PDF flow."
                      : 'One moment.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            if (ready)
              FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Open scanner'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              )
            else if (noCamera)
              OutlinedButton.icon(
                onPressed: onPickPhotos,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Pick photos instead'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              )
            else
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _PagesGrid extends StatelessWidget {
  final List<File> pages;
  final PdfPaperSize paperSize;
  final ValueChanged<PdfPaperSize> onPaperSize;
  final ValueChanged<int> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onAddMore;
  final bool scannerAvailable;
  final bool makeSearchable;
  final ValueChanged<bool> onMakeSearchableChanged;

  const _PagesGrid({
    required this.pages,
    required this.paperSize,
    required this.onPaperSize,
    required this.onRemove,
    required this.onReorder,
    required this.onAddMore,
    required this.scannerAvailable,
    required this.makeSearchable,
    required this.onMakeSearchableChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<PdfPaperSize>(
                  initialValue: paperSize,
                  decoration: InputDecoration(
                    labelText: 'Paper size',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  items: PdfPaperSize.values
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.label),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onPaperSize(v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onAddMore,
                icon: Icon(scannerAvailable
                    ? Icons.add_a_photo_outlined
                    : Icons.add_photo_alternate_outlined),
                label: Text(scannerAvailable ? 'Scan more' : 'Add'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: _SearchableToggle(
            value: makeSearchable,
            onChanged: onMakeSearchableChanged,
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            itemCount: pages.length,
            onReorder: onReorder,
            buildDefaultDragHandles: false,
            itemBuilder: (context, i) {
              final f = pages[i];
              return Padding(
                key: ValueKey('${f.path}#$i'),
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          f,
                          width: 56,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Page ${i + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              f.path.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => onRemove(i),
                        tooltip: 'Remove page',
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.drag_handle,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchableToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SearchableToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: value
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (value ? AppColors.primary : AppColors.textTertiary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.find_in_page_outlined,
                color: value ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Make searchable',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value
                        ? 'Apple Vision OCR each page — Cmd+F finds text'
                        : 'Plain images-to-PDF — faster, not searchable',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
