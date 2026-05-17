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
import '../../data/services/pdf_watermark_service.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';
import '../merge/merge_result_screen.dart';

class WatermarkScreen extends ConsumerStatefulWidget {
  const WatermarkScreen({super.key});

  @override
  ConsumerState<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends ConsumerState<WatermarkScreen> {
  PdfDocument? _doc;
  final TextEditingController _text =
      TextEditingController(text: 'CONFIDENTIAL');
  WatermarkLayout _layout = WatermarkLayout.diagonal;
  WatermarkOpacity _opacity = WatermarkOpacity.medium;
  double? _progress;
  CancellationToken? _cancel;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
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
                ? 'This PDF is password-protected — open it elsewhere first.'
                : message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _stamp() async {
    final doc = _doc;
    if (doc == null) return;
    HapticsService.instance.tap();

    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
    });

    final result = await PdfWatermarkService.instance.stamp(
      input: doc,
      settings: WatermarkSettings(
        text: _text.text,
        layout: _layout,
        opacity: _opacity,
      ),
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      cancel: cancel,
    );

    if (!mounted) return;
    setState(() {
      _progress = null;
      _cancel = null;
    });

    switch (result) {
      case Ok(:final value):
        HapticsService.instance.success();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MergeResultScreen(
              outputFile: value,
              toolLabel: 'Watermarked',
              toolIdForUsage: 'watermark',
              sourceCount: 1,
              pageCount: doc.pageCount,
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
        title: const Text('Watermark'),
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
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          children: [
                            _DocSummary(doc: doc),
                            const SizedBox(height: 14),
                            _PreviewCard(
                              text: _text.text.toUpperCase(),
                              opacity: _opacity,
                              layout: _layout,
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _text,
                              onChanged: (_) => setState(() {}),
                              textCapitalization:
                                  TextCapitalization.characters,
                              decoration: InputDecoration(
                                labelText: 'Watermark text',
                                hintText: 'CONFIDENTIAL · DRAFT · '
                                    'INTERNAL USE',
                                filled: true,
                                fillColor: AppColors.surface,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.border,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.border,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Layout',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final l in WatermarkLayout.values)
                                  ChoiceChip(
                                    label: Text(l.label),
                                    selected: l == _layout,
                                    onSelected: (_) {
                                      HapticsService.instance.select();
                                      setState(() => _layout = l);
                                    },
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: l == _layout
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    backgroundColor: AppColors.surface,
                                    side: BorderSide(
                                      color: l == _layout
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Opacity',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final o in WatermarkOpacity.values)
                                  ChoiceChip(
                                    label: Text(o.label),
                                    selected: o == _opacity,
                                    onSelected: (_) {
                                      HapticsService.instance.select();
                                      setState(() => _opacity = o);
                                    },
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: o == _opacity
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    backgroundColor: AppColors.surface,
                                    side: BorderSide(
                                      color: o == _opacity
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_progress == null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: ToolPrimaryButton(
                            label: 'Watermark ${doc.pageCount} '
                                'page${doc.pageCount == 1 ? '' : 's'}',
                            icon: Icons.water_drop,
                            enabled: _text.text.trim().isNotEmpty,
                            onTap: _stamp,
                          ),
                        ),
                    ],
                  ),
          ),
          if (_progress != null)
            ProgressOverlay(
              progress: _progress,
              title: 'Adding watermark',
              subtitle: 'Processing on this device — no upload',
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
      heroIcon: Icons.water_drop_outlined,
      title: 'Add a watermark',
      subtitle: 'Stamp CONFIDENTIAL, DRAFT, or custom text',
      primaryLabel: 'Pick a PDF',
      onPrimary: onPick,
      altSources: [
        ToolAltSource(icon: Icons.camera_alt_outlined, label: 'Scan', onTap: onPick),
      ],
    );
  }
}

class _DocSummary extends StatelessWidget {
  final PdfDocument doc;
  const _DocSummary({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String text;
  final WatermarkOpacity opacity;
  final WatermarkLayout layout;

  const _PreviewCard({
    required this.text,
    required this.opacity,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.4,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Faint document content sketch lines
            CustomPaint(painter: _DocLinesPainter()),
            _PreviewOverlay(
              text: text.isEmpty ? 'WATERMARK' : text,
              opacity: opacity.alpha,
              layout: layout,
            ),
          ],
        ),
      ),
    );
  }
}

class _DocLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    const padding = 16.0;
    final lineCount = ((size.height - padding * 2) / 18).floor();
    for (var i = 0; i < lineCount; i++) {
      final y = padding + 12 + i * 18.0;
      // Slight length variation so it looks like text, not a grid.
      final length = i % 4 == 3
          ? size.width - padding * 2 - 60
          : size.width - padding * 2;
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + length, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PreviewOverlay extends StatelessWidget {
  final String text;
  final double opacity;
  final WatermarkLayout layout;

  const _PreviewOverlay({
    required this.text,
    required this.opacity,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) {
    switch (layout) {
      case WatermarkLayout.diagonal:
        return Center(
          child: Transform.rotate(
            angle: -0.52, // ~-30°
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  color: Colors.black.withValues(alpha: opacity),
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        );
      case WatermarkLayout.horizontalCenter:
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: Colors.black.withValues(alpha: opacity),
                letterSpacing: 2,
              ),
            ),
          ),
        );
      case WatermarkLayout.tile:
        return Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          children: List.generate(20, (_) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Transform.rotate(
                angle: -0.43,
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withValues(alpha: opacity),
                  ),
                ),
              ),
            );
          }),
        );
    }
  }
}
