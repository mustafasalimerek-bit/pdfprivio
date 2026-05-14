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
import '../../data/services/pdf_split_service.dart';
import '../../providers/split_providers.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import 'split_result_screen.dart';

class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key});

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  CancellationToken? _activeCancel;

  Future<void> _pickFile() async {
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
        ref.read(splitDocumentProvider.notifier).state = value;
        ref.read(splitRangeStartProvider.notifier).state = 1;
        ref.read(splitRangeEndProvider.notifier).state = value.pageCount;
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

  Future<void> _split() async {
    final doc = ref.read(splitDocumentProvider);
    if (doc == null) return;
    HapticsService.instance.tap();

    final mode = ref.read(splitModeProvider);
    final cancel = CancellationToken();
    _activeCancel = cancel;
    ref.read(splitProgressProvider.notifier).state = 0;

    Result<List<File>> outputs;
    switch (mode) {
      case SplitMode.range:
        final start = ref.read(splitRangeStartProvider);
        final end = ref.read(splitRangeEndProvider);
        final single = await PdfSplitService.instance.extractRange(
          input: doc,
          startPage: start,
          endPage: end,
          onProgress: (p) {
            if (mounted) {
              ref.read(splitProgressProvider.notifier).state = p;
            }
          },
          cancel: cancel,
        );
        outputs = switch (single) {
          Ok(:final value) => Ok([value]),
          Err(:final kind, :final message, :final cause) =>
            Err(kind, message, cause: cause),
        };
      case SplitMode.everyN:
        final n = ref.read(splitEveryNProvider);
        outputs = await PdfSplitService.instance.splitEveryNPages(
          input: doc,
          n: n,
          onProgress: (p) {
            if (mounted) {
              ref.read(splitProgressProvider.notifier).state = p;
            }
          },
          cancel: cancel,
        );
      case SplitMode.parts:
        final parts = ref.read(splitPartsProvider);
        outputs = await PdfSplitService.instance.splitIntoNParts(
          input: doc,
          count: parts,
          onProgress: (p) {
            if (mounted) {
              ref.read(splitProgressProvider.notifier).state = p;
            }
          },
          cancel: cancel,
        );
    }

    if (!mounted) return;
    ref.read(splitProgressProvider.notifier).state = null;
    _activeCancel = null;

    switch (outputs) {
      case Ok(:final value):
        HapticsService.instance.success();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SplitResultScreen(files: value),
          ),
        );
        if (mounted) {
          ref.read(splitDocumentProvider.notifier).state = null;
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
    final doc = ref.watch(splitDocumentProvider);
    final mode = ref.watch(splitModeProvider);
    final progress = ref.watch(splitProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Split PDF'),
        actions: [
          if (doc != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                ref.read(splitDocumentProvider.notifier).state = null;
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
                      ? _EmptyState(onPick: _pickFile)
                      : _Picker(doc: doc, mode: mode),
                ),
                if (doc != null && progress == null)
                  _SplitButton(mode: mode, onTap: _split),
              ],
            ),
          ),
          if (progress != null)
            ProgressOverlay(
              progress: progress,
              title: 'Splitting PDF',
              subtitle: 'Processing on this device — no upload',
              onCancel: () => _activeCancel?.cancel(),
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
                Icons.content_cut_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Split a PDF',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Extract a page range, split every N pages, '
              'or divide into equal parts.',
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

class _Picker extends ConsumerWidget {
  final PdfDocument doc;
  final SplitMode mode;

  const _Picker({required this.doc, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      children: [
        _DocSummary(doc: doc),
        const SizedBox(height: 16),
        const Text(
          'How do you want to split it?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final m in SplitMode.values)
          _ModeCard(
            mode: m,
            selected: m == mode,
            onTap: () {
              HapticsService.instance.select();
              ref.read(splitModeProvider.notifier).state = m;
            },
          ),
        const SizedBox(height: 12),
        _ModeInput(mode: mode, doc: doc),
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
            child: const Icon(Icons.picture_as_pdf_outlined,
                color: AppColors.primary),
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

class _ModeCard extends StatelessWidget {
  final SplitMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mode.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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

class _ModeInput extends ConsumerWidget {
  final SplitMode mode;
  final PdfDocument doc;
  const _ModeInput({required this.mode, required this.doc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (mode) {
      case SplitMode.range:
        final start = ref.watch(splitRangeStartProvider);
        final end = ref.watch(splitRangeEndProvider);
        return _RangeInput(
          start: start,
          end: end,
          maxPage: doc.pageCount,
          onChanged: (s, e) {
            ref.read(splitRangeStartProvider.notifier).state = s;
            ref.read(splitRangeEndProvider.notifier).state = e;
          },
        );
      case SplitMode.everyN:
        final n = ref.watch(splitEveryNProvider);
        return _StepperRow(
          label: 'Pages per part',
          value: n,
          min: 1,
          max: doc.pageCount - 1,
          onChanged: (v) =>
              ref.read(splitEveryNProvider.notifier).state = v,
          summary: '${(doc.pageCount / n).ceil()} output files',
        );
      case SplitMode.parts:
        final parts = ref.watch(splitPartsProvider);
        return _StepperRow(
          label: 'Number of parts',
          value: parts,
          min: 2,
          max: doc.pageCount,
          onChanged: (v) =>
              ref.read(splitPartsProvider.notifier).state = v,
          summary: '~${(doc.pageCount / parts).ceil()} pages per part',
        );
    }
  }
}

class _RangeInput extends StatelessWidget {
  final int start;
  final int end;
  final int maxPage;
  final void Function(int, int) onChanged;

  const _RangeInput({
    required this.start,
    required this.end,
    required this.maxPage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Page range (1–$maxPage)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumberStepper(
                  label: 'Start',
                  value: start,
                  min: 1,
                  max: end,
                  onChanged: (v) => onChanged(v, end),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumberStepper(
                  label: 'End',
                  value: end,
                  min: start,
                  max: maxPage,
                  onChanged: (v) => onChanged(start, v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${end - start + 1} page${end - start == 0 ? '' : 's'} '
            'will be extracted into a new PDF.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;
  final String summary;

  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NumberStepper(
            label: label,
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          Text(
            summary,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;

  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _IconStepperButton(
              icon: Icons.remove,
              enabled: value > min,
              onTap: () => onChanged(value - 1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _IconStepperButton(
              icon: Icons.add,
              enabled: value < max,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _IconStepperButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _IconStepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: IconButton(
        icon: Icon(icon),
        onPressed: enabled
            ? () {
                HapticsService.instance.tap();
                onTap();
              }
            : null,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

class _SplitButton extends ConsumerWidget {
  final SplitMode mode;
  final VoidCallback onTap;

  const _SplitButton({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(splitDocumentProvider);
    if (doc == null) return const SizedBox.shrink();

    String label;
    switch (mode) {
      case SplitMode.range:
        final start = ref.watch(splitRangeStartProvider);
        final end = ref.watch(splitRangeEndProvider);
        label = 'Extract pages $start–$end';
      case SplitMode.everyN:
        final n = ref.watch(splitEveryNProvider);
        final count = (doc.pageCount / n).ceil();
        label = 'Split into $count files';
      case SplitMode.parts:
        final parts = ref.watch(splitPartsProvider);
        label = 'Split into $parts files';
    }
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
