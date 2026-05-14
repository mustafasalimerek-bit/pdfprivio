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
import '../../data/services/pdf_bates_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import '../merge/merge_result_screen.dart';

class BatesScreen extends ConsumerStatefulWidget {
  const BatesScreen({super.key});

  @override
  ConsumerState<BatesScreen> createState() => _BatesScreenState();
}

class _BatesScreenState extends ConsumerState<BatesScreen> {
  PdfDocument? _doc;
  final TextEditingController _prefix =
      TextEditingController(text: 'ACME');
  final TextEditingController _start = TextEditingController(text: '1');
  int _padding = 5;
  String _separator = '-';
  BatesPosition _position = BatesPosition.bottomRight;
  double? _progress;
  CancellationToken? _cancel;

  @override
  void dispose() {
    _prefix.dispose();
    _start.dispose();
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

    final start = int.tryParse(_start.text.trim()) ?? 1;
    final settings = BatesSettings(
      prefix: _prefix.text.trim(),
      startNumber: start < 0 ? 0 : start,
      padding: _padding,
      separator: _separator,
      position: _position,
    );

    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
    });

    final result = await PdfBatesService.instance.stamp(
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
    final start = int.tryParse(_start.text.trim()) ?? 1;
    final preview = BatesSettings(
      prefix: _prefix.text.trim(),
      startNumber: start < 0 ? 0 : start,
      padding: _padding,
      separator: _separator,
      position: _position,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bates numbering'),
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
                      ? _EmptyState(onPick: _pick)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          children: [
                            _DocSummary(doc: doc),
                            const SizedBox(height: 14),
                            _PreviewCard(
                              first: preview.stampFor(0),
                              last: preview.stampFor(doc.pageCount - 1),
                              pageCount: doc.pageCount,
                            ),
                            const SizedBox(height: 14),
                            _PrefixField(controller: _prefix),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _StartField(controller: _start),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _PaddingPicker(
                                    value: _padding,
                                    onChanged: (v) {
                                      HapticsService.instance.select();
                                      setState(() => _padding = v);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _SeparatorPicker(
                              value: _separator,
                              onChanged: (s) {
                                HapticsService.instance.select();
                                setState(() => _separator = s);
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
                                for (final p in BatesPosition.values)
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
                          ],
                        ),
                ),
                if (doc != null && _progress == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _stamp,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Stamp ${doc.pageCount} '
                          'page${doc.pageCount == 1 ? '' : 's'}',
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
              title: 'Adding Bates numbers',
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
                Icons.tag,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Bates numbering',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Stamp every page with a sequential identifier — '
              'standard practice for legal discovery, depositions, '
              'and exhibit prep.',
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
          ],
        ),
      ),
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
  final int pageCount;

  const _PreviewCard({
    required this.first,
    required this.last,
    required this.pageCount,
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
              _PreviewLabel(label: 'First page', stamp: first),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward, color: AppColors.textTertiary),
              const SizedBox(width: 12),
              _PreviewLabel(
                label: 'Page $pageCount',
                stamp: last,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  final String label;
  final String stamp;
  const _PreviewLabel({required this.label, required this.stamp});

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
            stamp,
            style: const TextStyle(
              fontFamily: 'Courier',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PrefixField extends StatelessWidget {
  final TextEditingController controller;
  const _PrefixField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: 'Prefix (optional)',
        hintText: 'ACME, EXHIBIT, DEF — leave blank for numbers only',
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _StartField extends StatelessWidget {
  final TextEditingController controller;
  const _StartField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: 'Start at',
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _PaddingPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _PaddingPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Padding',
        helperText: '00001 → ${'9' * value}',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 3, child: Text('3 digits')),
            DropdownMenuItem(value: 4, child: Text('4 digits')),
            DropdownMenuItem(value: 5, child: Text('5 digits')),
            DropdownMenuItem(value: 6, child: Text('6 digits')),
            DropdownMenuItem(value: 7, child: Text('7 digits')),
          ],
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}

class _SeparatorPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SeparatorPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = const ['-', '_', ' ', '.'];
    final labels = const {
      '-': 'Dash · ACME-00001',
      '_': 'Underscore · ACME_00001',
      ' ': 'Space · ACME 00001',
      '.': 'Dot · ACME.00001',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Separator',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in options)
              ChoiceChip(
                label: Text(labels[s] ?? s),
                selected: s == value,
                onSelected: (_) => onChanged(s),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: s == value ? Colors.white : AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: AppColors.surface,
                side: BorderSide(
                  color: s == value ? AppColors.primary : AppColors.border,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
