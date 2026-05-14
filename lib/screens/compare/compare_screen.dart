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
import '../../data/services/pdf_compare_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import 'compare_result_screen.dart';

class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  PdfDocument? _left;
  PdfDocument? _right;
  double? _progress;
  String? _status;
  CancellationToken? _cancel;

  Future<void> _pick(bool isLeft) async {
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
        setState(() {
          if (isLeft) {
            _left = value;
          } else {
            _right = value;
          }
        });
        HapticsService.instance.select();
      case Err(:final kind, :final message):
        HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kind == FailureKind.needsPassword
                ? 'This PDF is password-protected — open it elsewhere first.'
                : message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _run() async {
    final left = _left;
    final right = _right;
    if (left == null || right == null) return;
    HapticsService.instance.tap();

    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
      _status = 'Starting…';
    });

    final result = await PdfCompareService.instance.compare(
      left: left,
      right: right,
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
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CompareResultScreen(
              outcome: value,
              leftName: left.displayName,
              rightName: right.displayName,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _left = null;
            _right = null;
          });
        }
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

  void _swap() {
    HapticsService.instance.tap();
    setState(() {
      final tmp = _left;
      _left = _right;
      _right = tmp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canRun = _left != null && _right != null && _progress == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare PDFs'),
        actions: [
          if (_left != null || _right != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(() {
                  _left = null;
                  _right = null;
                });
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
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    children: [
                      _Slot(
                        label: 'Left (original)',
                        doc: _left,
                        onPick: () => _pick(true),
                        onClear: () =>
                            setState(() => _left = null),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton.icon(
                          onPressed: _left != null && _right != null
                              ? _swap
                              : null,
                          icon: const Icon(Icons.swap_vert, size: 16),
                          label: const Text('Swap'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _Slot(
                        label: 'Right (compared to)',
                        doc: _right,
                        onPick: () => _pick(false),
                        onClear: () =>
                            setState(() => _right = null),
                      ),
                      if (_left != null && _right != null) ...[
                        const SizedBox(height: 16),
                        _Hint(
                          left: _left!,
                          right: _right!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_progress == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: canRun ? _run : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          canRun
                              ? 'Compare text'
                              : _left == null && _right == null
                                  ? 'Pick two PDFs to start'
                                  : 'Pick the other PDF',
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
              title: 'Comparing PDFs',
              subtitle:
                  _status ?? 'Processing on this device — no upload',
              onCancel: () => _cancel?.cancel(),
            ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  final String label;
  final PdfDocument? doc;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _Slot({
    required this.label,
    required this.doc,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: doc == null
              ? AppColors.border
              : AppColors.primary.withValues(alpha: 0.5),
          width: doc == null ? 1 : 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
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
            const SizedBox(height: 8),
            if (doc == null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.add),
                  label: const Text('Pick a PDF'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc!.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${doc!.pageCount} pages · '
                          '${formatBytes(doc!.sizeBytes)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary,
                    onPressed: onClear,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final PdfDocument left;
  final PdfDocument right;

  const _Hint({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final pageDelta = (left.pageCount - right.pageCount).abs();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pageDelta == 0
                      ? "We'll align pages 1-to-1 and diff text on each."
                      : "Documents differ by $pageDelta page${pageDelta == 1 ? '' : 's'}. "
                          "Extra pages on one side will show as full additions or "
                          "deletions on that side.",
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Visual / layout changes are not compared yet — text only.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
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
