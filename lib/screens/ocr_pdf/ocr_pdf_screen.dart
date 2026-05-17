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
import '../../data/services/ocr_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../data/services/pdf_ocr_compose_service.dart';
import '../../data/services/pdf_to_images_service.dart';
import '../../data/services/share_intent_service.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';
import '../merge/merge_result_screen.dart';

class OcrPdfScreen extends ConsumerStatefulWidget {
  const OcrPdfScreen({super.key});

  @override
  ConsumerState<OcrPdfScreen> createState() => _OcrPdfScreenState();
}

class _OcrPdfScreenState extends ConsumerState<OcrPdfScreen> {
  PdfDocument? _doc;
  double? _progress;
  String? _status;
  CancellationToken? _cancel;
  final _languages = ['en-US', 'tr-TR'];
  OcrLevel _level = OcrLevel.accurate;

  @override
  void initState() {
    super.initState();
    final pending = PendingSharedFile.consume();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFromFile(pending);
      });
    }
  }

  Future<void> _loadFromFile(File file) async {
    final outcome = await PdfMetadataService.instance.inspect(file);
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

  Future<void> _pick() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res == null) return;
    final path = res.paths.firstOrNull;
    if (path == null) return;
    await _loadFromFile(File(path));
  }

  Future<void> _run() async {
    final doc = _doc;
    if (doc == null) return;
    HapticsService.instance.tap();

    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
      _status = 'Rendering pages…';
    });

    final renderRes = await PdfToImagesService.instance.render(
      input: doc,
      onProgress: (p, msg) {
        if (!mounted) return;
        setState(() {
          _progress = p * 0.35;
          _status = msg;
        });
      },
      cancel: cancel,
    );

    if (!mounted) return;
    if (renderRes is Err<List<File>>) {
      _finishWithError(renderRes.kind, renderRes.message);
      return;
    }
    final images = (renderRes as Ok<List<File>>).value;
    if (images.isEmpty) {
      _finishWithError(FailureKind.unknown, 'No pages rendered.');
      return;
    }

    setState(() {
      _progress = 0.35;
      _status = 'Recognizing text…';
    });

    final composedPages = <OcrComposedPage>[];
    for (var i = 0; i < images.length; i++) {
      if (cancel.isCancelled) {
        _finishWithError(FailureKind.cancelled, 'Cancelled');
        return;
      }
      final ocr = await OcrService.instance.recognize(
        image: images[i],
        languages: _languages,
        level: _level,
      );
      if (ocr is Err<OcrPageResult>) {
        _finishWithError(ocr.kind, ocr.message);
        return;
      }
      composedPages.add(OcrComposedPage(
        image: images[i],
        ocr: (ocr as Ok<OcrPageResult>).value,
      ));
      if (mounted) {
        setState(() {
          _progress = 0.35 + 0.5 * ((i + 1) / images.length);
          _status = 'Recognized page ${i + 1} of ${images.length}';
        });
      }
    }

    setState(() {
      _progress = 0.85;
      _status = 'Building searchable PDF…';
    });

    final composeRes = await PdfOcrComposeService.instance.compose(
      pages: composedPages,
      outputName: '${doc.displayName.replaceAll('.pdf', '')}_searchable',
      onProgress: (p, msg) {
        if (!mounted) return;
        setState(() {
          _progress = 0.85 + 0.15 * p;
          _status = msg;
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

    switch (composeRes) {
      case Ok(:final value):
        HapticsService.instance.success();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MergeResultScreen(
              outputFile: value.outputFile,
              sourceCount: value.pageCount,
              toolLabel: 'Searchable',
              toolIdForUsage: 'ocr_pdf',
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
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR PDF'),
        centerTitle: true,
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
            child: doc == null
                ? _EmptyState(onPick: _pick)
                : Column(
                    children: [
                      Expanded(
                        child: _DocReady(
                          doc: doc,
                          level: _level,
                          onLevel: (l) => setState(() => _level = l),
                        ),
                      ),
                      if (_progress == null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: ToolPrimaryButton(
                            label: 'Make searchable · ${doc.pageCount} '
                                'page${doc.pageCount == 1 ? '' : 's'}',
                            icon: Icons.find_in_page_outlined,
                            onTap: _run,
                          ),
                        ),
                    ],
                  ),
          ),
          if (_progress != null)
            ProgressOverlay(
              progress: _progress,
              title: 'OCR running',
              subtitle: _status ?? 'On-device — no upload',
              onCancel: () => _cancel?.cancel(),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyState({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ToolEmptyState(
      heroIcon: Icons.find_in_page_outlined,
      title: 'Make scans searchable',
      subtitle: 'Apple Vision adds a text layer on-device',
      primaryLabel: 'Pick a PDF',
      onPrimary: onPick,
      altSources: [
        ToolAltSource(icon: Icons.camera_alt_outlined, label: 'Scan', onTap: onPick),
      ],
    );
  }
}

class _DocReady extends StatelessWidget {
  final PdfDocument doc;
  final OcrLevel level;
  final ValueChanged<OcrLevel> onLevel;
  const _DocReady({
    required this.doc,
    required this.level,
    required this.onLevel,
  });

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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recognition quality',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _LevelTile(
                level: OcrLevel.accurate,
                title: 'Accurate',
                subtitle:
                    'Best for legal/financial docs. Slower but precise.',
                selected: level == OcrLevel.accurate,
                onTap: () => onLevel(OcrLevel.accurate),
              ),
              const SizedBox(height: 8),
              _LevelTile(
                level: OcrLevel.fast,
                title: 'Fast',
                subtitle: 'Quick draft pass. Trade accuracy for speed.',
                selected: level == OcrLevel.fast,
                onTap: () => onLevel(OcrLevel.fast),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LevelTile extends StatelessWidget {
  final OcrLevel level;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _LevelTile({
    required this.level,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticsService.instance.select();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? AppColors.primary
                  : AppColors.textTertiary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
