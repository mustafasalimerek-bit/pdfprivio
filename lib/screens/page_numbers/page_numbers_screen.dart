import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../data/services/pdf_page_number_service.dart';
import '../../data/services/scan_pickup_service.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';
import '../merge/merge_result_screen.dart';

class PageNumbersScreen extends ConsumerStatefulWidget {
  const PageNumbersScreen({super.key});

  @override
  ConsumerState<PageNumbersScreen> createState() =>
      _PageNumbersScreenState();
}

class _PageNumbersScreenState extends ConsumerState<PageNumbersScreen> {
  PdfDocument? _doc;
  PageNumberFormat _format = PageNumberFormat.pageOfTotal;
  PageNumberPosition _position = PageNumberPosition.bottomCenter;
  bool _skipCover = false;
  final TextEditingController _startNumber =
      TextEditingController(text: '1');
  double? _progress;
  CancellationToken? _cancel;

  @override
  void dispose() {
    _startNumber.dispose();
    super.dispose();
  }

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

    final start = int.tryParse(_startNumber.text.trim()) ?? 1;
    final settings = PageNumberSettings(
      format: _format,
      position: _position,
      startNumber: start < 1 ? 1 : start,
      skipFirst: _skipCover ? 1 : 0,
    );

    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
    });

    final result = await PdfPageNumberService.instance.stamp(
      input: doc,
      settings: settings,
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
              toolLabel: 'Numbered',
              toolIdForUsage: 'page_numbers',
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
    final start = int.tryParse(_startNumber.text.trim()) ?? 1;
    final skip = _skipCover ? 1 : 0;
    final totalNumbered =
        doc == null ? 0 : (doc.pageCount - skip).clamp(0, 1 << 20);
    final firstExample = _format.example(start, start + totalNumbered - 1);
    final lastExample = _format.example(
      start + totalNumbered - 1,
      start + totalNumbered - 1,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Page numbers'),
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
                ? _EmptyState(onPick: _pick, onScan: _scanPdf)
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          children: [
                            _DocSummary(doc: doc),
                            const SizedBox(height: 14),
                            _PreviewCard(
                              first: firstExample,
                              last: lastExample,
                              total: doc.pageCount,
                              skip: skip,
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Format',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final f in PageNumberFormat.values)
                              _RadioCard<PageNumberFormat>(
                                value: f,
                                groupValue: _format,
                                label: f.label,
                                onTap: () {
                                  HapticsService.instance.select();
                                  setState(() => _format = f);
                                },
                              ),
                            const SizedBox(height: 14),
                            const Text(
                              'Position',
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
                                for (final p in PageNumberPosition.values)
                                  ChoiceChip(
                                    label: Text(p.label),
                                    selected: p == _position,
                                    onSelected: (_) {
                                      HapticsService.instance.select();
                                      setState(() => _position = p);
                                    },
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: p == _position
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    backgroundColor: AppColors.surface,
                                    side: BorderSide(
                                      color: p == _position
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _startNumber,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      labelText: 'Start at',
                                      filled: true,
                                      fillColor: AppColors.surface,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SwitchListTile(
                                    title: const Text(
                                      'Skip cover',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'First page stays blank',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                    value: _skipCover,
                                    onChanged: doc.pageCount > 1
                                        ? (v) {
                                            HapticsService.instance.select();
                                            setState(() => _skipCover = v);
                                          }
                                        : null,
                                    activeThumbColor: AppColors.primary,
                                    contentPadding: EdgeInsets.zero,
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
                            label: 'Number $totalNumbered '
                                'page${totalNumbered == 1 ? '' : 's'}',
                            icon: Icons.format_list_numbered,
                            enabled: totalNumbered > 0,
                            onTap: _stamp,
                          ),
                        ),
                    ],
                  ),
          ),
          if (_progress != null)
            ProgressOverlay(
              progress: _progress,
              title: 'Numbering pages',
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
  final VoidCallback onScan;
  const _EmptyState({required this.onPick, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return ToolEmptyState(
      heroIcon: Icons.format_list_numbered,
      title: 'Add page numbers',
      subtitle: 'Four formats, five positions',
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
  final String first;
  final String last;
  final int total;
  final int skip;

  const _PreviewCard({
    required this.first,
    required this.last,
    required this.total,
    required this.skip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preview',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Sample(
                label: skip == 0 ? 'First page' : 'After cover',
                text: first,
              ),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward, color: AppColors.textTertiary),
              const SizedBox(width: 12),
              _Sample(
                label: 'Last page',
                text: last,
              ),
            ],
          ),
          if (skip > 0)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Cover page stays unnumbered.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Sample extends StatelessWidget {
  final String label;
  final String text;
  const _Sample({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _RadioCard<T> extends StatelessWidget {
  final T value;
  final T groupValue;
  final String label;
  final VoidCallback onTap;

  const _RadioCard({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
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
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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
