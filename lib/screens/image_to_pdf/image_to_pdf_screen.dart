import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/image_to_pdf_service.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import '../merge/merge_result_screen.dart';

class ImageToPdfScreen extends ConsumerStatefulWidget {
  const ImageToPdfScreen({super.key});

  @override
  ConsumerState<ImageToPdfScreen> createState() => _ImageToPdfScreenState();
}

class _ImageToPdfScreenState extends ConsumerState<ImageToPdfScreen> {
  final List<File> _images = [];
  PdfPaperSize _paperSize = PdfPaperSize.letter; // US default
  double? _progress;
  CancellationToken? _cancel;

  Future<void> _pickImages() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (res == null) return;
    final files =
        res.paths.whereType<String>().map((p) => File(p)).toList();
    if (files.isEmpty) return;
    setState(() => _images.addAll(files));
    HapticsService.instance.select();
  }

  void _reorder(int oldIndex, int newIndex) {
    HapticsService.instance.drop();
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    setState(() {
      final item = _images.removeAt(oldIndex);
      _images.insert(adjusted, item);
    });
  }

  void _remove(int index) {
    HapticsService.instance.select();
    setState(() => _images.removeAt(index));
  }

  Future<void> _convert() async {
    if (_images.isEmpty) return;
    HapticsService.instance.tap();
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
    });

    final result = await ImageToPdfService.instance.convert(
      images: _images,
      paperSize: _paperSize,
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
              sourceCount: _images.length,
              toolLabel: 'Image to PDF',
              toolIdForUsage: 'image_to_pdf',
            ),
          ),
        );
        if (mounted) setState(_images.clear);
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
        title: const Text('Image to PDF'),
        actions: [
          if (_images.isNotEmpty)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(_images.clear);
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
                  child: _images.isEmpty
                      ? _EmptyState(onPick: _pickImages)
                      : _Picker(
                          images: _images,
                          paperSize: _paperSize,
                          onPaperSize: (s) {
                            HapticsService.instance.select();
                            setState(() => _paperSize = s);
                          },
                          onAddMore: _pickImages,
                          onReorder: _reorder,
                          onRemove: _remove,
                        ),
                ),
                if (_images.isNotEmpty && _progress == null)
                  _Button(
                    label: 'Build PDF from ${_images.length} '
                        'image${_images.length == 1 ? '' : 's'}',
                    onTap: _convert,
                  ),
              ],
            ),
          ),
          if (_progress != null)
            ProgressOverlay(
              progress: _progress,
              title: 'Building PDF',
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
                Icons.image_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Turn images into a PDF',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pick photos, receipts, or screenshots. '
              'Drag to reorder before exporting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Pick images'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  final List<File> images;
  final PdfPaperSize paperSize;
  final void Function(PdfPaperSize) onPaperSize;
  final VoidCallback onAddMore;
  final void Function(int, int) onReorder;
  final void Function(int) onRemove;

  const _Picker({
    required this.images,
    required this.paperSize,
    required this.onPaperSize,
    required this.onAddMore,
    required this.onReorder,
    required this.onRemove,
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
                child: Text(
                  '${images.length} image${images.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAddMore,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add more'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final size in PdfPaperSize.values)
                ChoiceChip(
                  label: Text(size.label),
                  selected: paperSize == size,
                  onSelected: (_) => onPaperSize(size),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: paperSize == size
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: images.length,
            buildDefaultDragHandles: false,
            onReorder: onReorder,
            itemBuilder: (context, index) {
              final f = images[index];
              return _ImageTile(
                key: ValueKey(f.path),
                file: f,
                index: index,
                onRemove: () => onRemove(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ImageTile extends StatelessWidget {
  final File file;
  final int index;
  final VoidCallback onRemove;

  const _ImageTile({
    super.key,
    required this.file,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              file.uri.pathSegments.last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove image',
            onPressed: onRemove,
            color: AppColors.textSecondary,
          ),
          ReorderableDragStartListener(
            index: index,
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
    );
  }
}

class _Button extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _Button({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
