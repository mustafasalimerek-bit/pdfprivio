import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/compression_settings.dart';
import '../../data/services/batch_operations_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_rotate_service.dart';
import '../../data/services/pdf_watermark_service.dart';
import '../../data/services/share_service.dart';
import '../../widgets/tool_chrome.dart';

/// Batch tool — pick an operation, drop a stack of PDFs in, get a
/// folder full of processed files at the end. Sequential processing
/// only (Syncfusion is single-threaded per doc + parallel runs OOM
/// the iPhone on big legal exhibits).
class BatchScreen extends ConsumerStatefulWidget {
  const BatchScreen({super.key});

  @override
  ConsumerState<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends ConsumerState<BatchScreen> {
  BatchOperation _operation = BatchOperation.compress;
  final List<File> _files = [];

  // Per-op params
  CompressionLevel _compressionLevel = CompressionLevel.medium;
  final TextEditingController _watermarkText =
      TextEditingController(text: 'CONFIDENTIAL');
  WatermarkOpacity _watermarkOpacity = WatermarkOpacity.medium;
  WatermarkLayout _watermarkLayout = WatermarkLayout.diagonal;
  PdfRotation _rotation = PdfRotation.cw90;

  bool _busy = false;
  int _currentIndex = 0;
  String _currentFile = '';
  CancellationToken? _cancel;
  BatchOutcome? _outcome;

  @override
  void dispose() {
    _watermarkText.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (res == null) return;
    final picked =
        res.paths.whereType<String>().map((p) => File(p)).toList();
    if (picked.isEmpty) return;
    setState(() {
      _files.addAll(picked);
    });
    HapticsService.instance.select();
  }

  void _removeFile(int i) {
    HapticsService.instance.select();
    setState(() => _files.removeAt(i));
  }

  Future<void> _run() async {
    if (_files.isEmpty) return;
    if (_operation == BatchOperation.watermark &&
        _watermarkText.text.trim().isEmpty) {
      _snack('Watermark text cannot be empty.');
      return;
    }
    HapticsService.instance.tap();
    final cancel = CancellationToken();
    setState(() {
      _busy = true;
      _currentIndex = 0;
      _currentFile = '';
      _cancel = cancel;
      _outcome = null;
    });

    final params = BatchParams(
      compressionLevel: _compressionLevel,
      watermarkSettings: WatermarkSettings(
        text: _watermarkText.text.trim(),
        layout: _watermarkLayout,
        opacity: _watermarkOpacity,
      ),
      rotation: _rotation,
    );

    final outcome = await BatchOperationsService.instance.runBatch(
      operation: _operation,
      files: List.from(_files),
      params: params,
      cancel: cancel,
      onProgress: (i, total, name) {
        if (!mounted) return;
        setState(() {
          _currentIndex = i;
          _currentFile = name;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
      _cancel = null;
    });
    if (outcome.failureCount == 0) {
      HapticsService.instance.success();
    } else {
      HapticsService.instance.error();
    }
  }

  void _cancelRun() {
    HapticsService.instance.tap();
    _cancel?.cancel();
  }

  Future<void> _shareOutputs() async {
    final outcome = _outcome;
    if (outcome == null) return;
    final successFiles = outcome.items
        .where((i) => i.success)
        .map((i) => XFile(i.outputFile!.path))
        .toList();
    if (successFiles.isEmpty) return;
    HapticsService.instance.tap();
    await ShareService.shareWithFeedback(
      context,
      ShareParams(
        files: successFiles,
        text: 'Privio batch — ${outcome.operation.label}',
        sharePositionOrigin: ShareService.originFromContext(context),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _files.isEmpty && _outcome == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch operations'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: MaxWidthBody(
          child: _busy
              ? _busyView()
              : isEmpty
                  ? ToolEmptyState(
                      heroIcon: Icons.layers_outlined,
                      title: 'Batch operations',
                      subtitle:
                          'Compress, watermark, rotate — many PDFs at once',
                      primaryLabel: 'Add files',
                      onPrimary: _pickFiles,
                    )
                  : _editorView(),
        ),
      ),
    );
  }

  Widget _busyView() {
    final total = _files.length;
    final pct = total == 0 ? 0.0 : (_currentIndex + 1) / total;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cached, color: AppColors.primary, size: 48),
            const SizedBox(height: 14),
            Text(
              'Processing file ${_currentIndex + 1} of $total',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _currentFile,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              color: AppColors.primary,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: _cancelRun,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorView() {
    final outcome = _outcome;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (outcome != null) ...[
          _ResultCard(outcome: outcome, onShare: _shareOutputs),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Run another batch',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          'Operation',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        SegmentedButton<BatchOperation>(
          segments: const [
            ButtonSegment(
              value: BatchOperation.compress,
              icon: Icon(Icons.compress, size: 16),
              label: Text('Compress'),
            ),
            ButtonSegment(
              value: BatchOperation.watermark,
              icon: Icon(Icons.text_fields, size: 16),
              label: Text('Watermark'),
            ),
            ButtonSegment(
              value: BatchOperation.rotate,
              icon: Icon(Icons.rotate_right, size: 16),
              label: Text('Rotate'),
            ),
          ],
          selected: {_operation},
          onSelectionChanged: (s) => setState(() => _operation = s.first),
        ),
        const SizedBox(height: 8),
        Text(
          _operation.description,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _paramsCard(),
        const SizedBox(height: 16),
        _filesCard(),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _files.isEmpty ? null : _run,
          icon: const Icon(Icons.play_arrow),
          label: Text('Run on ${_files.length} '
              '${_files.length == 1 ? "file" : "files"}'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _paramsCard() {
    Widget body;
    switch (_operation) {
      case BatchOperation.compress:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Compression level',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<CompressionLevel>(
              segments: const [
                ButtonSegment(
                    value: CompressionLevel.high, label: Text('High quality')),
                ButtonSegment(
                    value: CompressionLevel.medium, label: Text('Balanced')),
                ButtonSegment(
                    value: CompressionLevel.low, label: Text('Small size')),
              ],
              selected: {_compressionLevel},
              onSelectionChanged: (s) =>
                  setState(() => _compressionLevel = s.first),
            ),
          ],
        );
      case BatchOperation.watermark:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Text',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _watermarkText,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            const Text('Layout',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<WatermarkLayout>(
              segments: WatermarkLayout.values
                  .map((l) =>
                      ButtonSegment(value: l, label: Text(l.label)))
                  .toList(),
              selected: {_watermarkLayout},
              onSelectionChanged: (s) =>
                  setState(() => _watermarkLayout = s.first),
            ),
            const SizedBox(height: 10),
            const Text('Opacity',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<WatermarkOpacity>(
              segments: WatermarkOpacity.values
                  .map((o) =>
                      ButtonSegment(value: o, label: Text(o.label)))
                  .toList(),
              selected: {_watermarkOpacity},
              onSelectionChanged: (s) =>
                  setState(() => _watermarkOpacity = s.first),
            ),
          ],
        );
      case BatchOperation.rotate:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Rotation',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<PdfRotation>(
              segments: PdfRotation.values
                  .map((r) => ButtonSegment(value: r, label: Text(r.label)))
                  .toList(),
              selected: {_rotation},
              onSelectionChanged: (s) => setState(() => _rotation = s.first),
            ),
          ],
        );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: body,
    );
  }

  Widget _filesCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Files (${_files.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_files.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No files yet. Tap Add to pick multiple PDFs at once.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            ..._files.asMap().entries.map(
                  (e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.picture_as_pdf,
                        color: AppColors.primary, size: 18),
                    title: Text(
                      e.value.path.split('/').last,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => _removeFile(e.key),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final BatchOutcome outcome;
  final VoidCallback onShare;
  const _ResultCard({required this.outcome, required this.onShare});

  @override
  Widget build(BuildContext context) {
    final total = outcome.items.length;
    final success = outcome.successCount;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Batch complete · ${outcome.operation.label}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$success of $total files succeeded · '
            '${outcome.elapsed.inSeconds}s',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (outcome.failureCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${outcome.failureCount} failed — likely '
              'password-protected or damaged PDFs.',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.warning,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Output: ${outcome.outputDirectory.path.split('/').last}',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
              fontFamily: 'Menlo',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: success == 0 ? null : onShare,
            icon: const Icon(Icons.ios_share),
            label: Text('Share $success ${success == 1 ? "file" : "files"}'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
