import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../data/services/pdf_rotate_service.dart';
import '../../data/services/pdf_thumbnail_service.dart';
import '../../data/services/scan_pickup_service.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';
import '../merge/merge_result_screen.dart';

class RotateScreen extends ConsumerStatefulWidget {
  const RotateScreen({super.key});

  @override
  ConsumerState<RotateScreen> createState() => _RotateScreenState();
}

class _RotateScreenState extends ConsumerState<RotateScreen> {
  PdfDocument? _doc;
  PdfRotation _rotation = PdfRotation.cw90;
  double? _progress;
  CancellationToken? _cancel;
  Uint8List? _thumb;

  Future<void> _pick() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = res?.paths.firstOrNull;
    if (path == null) return;
    await _loadFile(File(path));
  }

  Future<void> _scanPdf() async {
    HapticsService.instance.tap();
    final res = await ScanPickupService.instance.scanToPdf();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        await _loadFile(value);
      case Err(:final kind, :final message):
        if (kind != FailureKind.cancelled) {
          HapticsService.instance.error();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }

  Future<void> _loadFile(File file) async {
    final outcome = await PdfMetadataService.instance.inspect(file);
    if (!mounted) return;
    switch (outcome) {
      case Ok(:final value):
        final thumb =
            await PdfThumbnailService.instance.firstPage(value, width: 360);
        if (!mounted) return;
        setState(() {
          _doc = value;
          _thumb = thumb;
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

  Future<void> _rotate() async {
    final doc = _doc;
    if (doc == null) return;
    HapticsService.instance.tap();
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
    });

    final result = await PdfRotateService.instance.rotateAll(
      input: doc,
      rotation: _rotation,
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
              sourceCount: 1,
              toolLabel: 'Rotated',
              toolIdForUsage: 'rotate',
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _doc = null;
            _thumb = null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rotate pages'),
        centerTitle: true,
        actions: [
          if (_doc != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(() {
                  _doc = null;
                  _thumb = null;
                });
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: MaxWidthBody(
        child: Stack(
          children: [
            SafeArea(
              child: _doc == null
                  ? _EmptyState(onPick: _pick, onScan: _scanPdf)
                  : Column(
                      children: [
                        Expanded(
                          child: _Picker(
                            doc: _doc!,
                            thumb: _thumb,
                            rotation: _rotation,
                            onRotation: (r) {
                              HapticsService.instance.select();
                              setState(() => _rotation = r);
                            },
                          ),
                        ),
                        if (_progress == null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: ToolPrimaryButton(
                              label: _rotation.label,
                              icon: Icons.rotate_right,
                              onTap: _rotate,
                            ),
                          ),
                      ],
                    ),
            ),
            if (_progress != null)
              ProgressOverlay(
                progress: _progress,
                title: 'Rotating pages',
                subtitle: 'Processing on this device — no upload',
                onCancel: () => _cancel?.cancel(),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  final VoidCallback onScan;
  const _EmptyState({required this.onPick, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return ToolEmptyState(
      heroIcon: Icons.rotate_right,
      title: 'Rotate pages',
      subtitle: 'Fix sideways scans or flip a PDF',
      primaryLabel: 'Pick a PDF',
      onPrimary: onPick,
      altSources: [
        ToolAltSource(
          icon: Icons.camera_alt_outlined,
          label: 'Scan',
          onTap: onScan,
        ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  final PdfDocument doc;
  final Uint8List? thumb;
  final PdfRotation rotation;
  final void Function(PdfRotation) onRotation;

  const _Picker({
    required this.doc,
    required this.thumb,
    required this.rotation,
    required this.onRotation,
  });

  @override
  Widget build(BuildContext context) {
    final preview = _PreviewCard(thumb: thumb, rotation: rotation);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      children: [
        _DocSummary(doc: doc),
        const SizedBox(height: 14),
        const Text(
          'Preview',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 0.78,
          child: preview,
        ),
        const SizedBox(height: 16),
        const Text(
          'Direction',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final r in PdfRotation.values)
          _DirectionOption(
            rotation: r,
            selected: r == rotation,
            onTap: () => onRotation(r),
          ),
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
  final Uint8List? thumb;
  final PdfRotation rotation;

  const _PreviewCard({required this.thumb, required this.rotation});

  double get _angleTurns {
    switch (rotation) {
      case PdfRotation.cw90:
        return 0.25;
      case PdfRotation.rotate180:
        return 0.5;
      case PdfRotation.ccw90:
        return -0.25;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Center(
        child: AnimatedRotation(
          turns: _angleTurns,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: thumb == null
              ? const Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 64,
                  color: AppColors.textTertiary,
                )
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Image.memory(thumb!, fit: BoxFit.contain),
                ),
        ),
      ),
    );
  }
}

class _DirectionOption extends StatelessWidget {
  final PdfRotation rotation;
  final bool selected;
  final VoidCallback onTap;

  const _DirectionOption({
    required this.rotation,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon {
    switch (rotation) {
      case PdfRotation.cw90:
        return Icons.rotate_right;
      case PdfRotation.rotate180:
        return Icons.flip_camera_android;
      case PdfRotation.ccw90:
        return Icons.rotate_left;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 12),
                Icon(
                  _icon,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  rotation.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
