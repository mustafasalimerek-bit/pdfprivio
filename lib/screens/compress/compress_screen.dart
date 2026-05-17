import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/result.dart';
import '../../data/models/compression_settings.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_compression_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../providers/compress_providers.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';
import 'compress_result_screen.dart';

class CompressScreen extends ConsumerStatefulWidget {
  const CompressScreen({super.key});

  @override
  ConsumerState<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends ConsumerState<CompressScreen> {
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
        ref.read(compressDocumentProvider.notifier).state = value;
        // Smart recommendation based on file size — sets the initial
        // highlighted preset so the user sees a sensible default.
        ref.read(compressLevelProvider.notifier).state =
            recommendedLevelForSize(value.sizeBytes);
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

  Future<void> _compress() async {
    final doc = ref.read(compressDocumentProvider);
    if (doc == null) return;
    HapticsService.instance.tap();

    final level = ref.read(compressLevelProvider);
    final settings = level == CompressionLevel.custom
        ? ref.read(compressSettingsProvider)
        : CompressionSettings.preset(level);

    final cancel = CancellationToken();
    _activeCancel = cancel;
    ref.read(compressProgressProvider.notifier).state = 0;
    ref.read(compressStatusProvider.notifier).state = 'Starting…';

    final result = await PdfCompressionService.instance.compress(
      input: doc,
      settings: settings,
      onProgress: (p, m) {
        if (!mounted) return;
        ref.read(compressProgressProvider.notifier).state = p;
        ref.read(compressStatusProvider.notifier).state = m;
      },
      cancel: cancel,
    );

    if (!mounted) return;
    ref.read(compressProgressProvider.notifier).state = null;
    ref.read(compressStatusProvider.notifier).state = null;
    _activeCancel = null;

    switch (result) {
      case Ok(:final value):
        HapticsService.instance.success();
        ref.read(compressOutcomeProvider.notifier).state = value;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CompressResultScreen(),
          ),
        );
        if (mounted) {
          ref.read(compressDocumentProvider.notifier).state = null;
          ref.read(compressOutcomeProvider.notifier).state = null;
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
    final doc = ref.watch(compressDocumentProvider);
    final level = ref.watch(compressLevelProvider);
    final progress = ref.watch(compressProgressProvider);
    final status = ref.watch(compressStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compress PDF'),
        centerTitle: true,
        actions: [
          if (doc != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                ref.read(compressDocumentProvider.notifier).state = null;
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: doc == null
                ? _EmptyState(onPick: _pickFile)
                : Column(
                    children: [
                      Expanded(
                        child: _Picker(
                          doc: doc,
                          selectedLevel: level,
                          onSelect: (lvl) {
                            HapticsService.instance.select();
                            ref.read(compressLevelProvider.notifier).state =
                                lvl;
                          },
                        ),
                      ),
                      if (progress == null)
                        _CompressButton(
                          estimatedBytes:
                              (doc.sizeBytes * level.heuristicRatio).round(),
                          onTap: _compress,
                        ),
                    ],
                  ),
          ),
          if (progress != null)
            ProgressOverlay(
              progress: progress,
              title: 'Compressing PDF',
              subtitle: status ?? 'Processing on this device — no upload',
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
    return ToolEmptyState(
      heroIcon: Icons.compress,
      title: 'Compress a PDF',
      subtitle: 'Shrink for email — quality kept',
      primaryLabel: 'Pick a PDF',
      onPrimary: onPick,
      altSources: [
        ToolAltSource(icon: Icons.history, label: 'Recent', onTap: onPick),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  final dynamic doc; // PdfDocument
  final CompressionLevel selectedLevel;
  final void Function(CompressionLevel) onSelect;

  const _Picker({
    required this.doc,
    required this.selectedLevel,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final recommended = recommendedLevelForSize(doc.sizeBytes as int);
    final levels = [
      CompressionLevel.high,
      CompressionLevel.medium,
      CompressionLevel.low,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      children: [
        _DocSummary(name: doc.displayName, sizeBytes: doc.sizeBytes),
        const SizedBox(height: 12),
        const Text(
          'Compression level',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final lvl in levels)
          _LevelCard(
            level: lvl,
            selected: lvl == selectedLevel,
            recommended: lvl == recommended,
            onTap: () => onSelect(lvl),
            estimatedBytes: (doc.sizeBytes * lvl.heuristicRatio).round(),
          ),
      ],
    );
  }
}

class _DocSummary extends StatelessWidget {
  final String name;
  final int sizeBytes;

  const _DocSummary({required this.name, required this.sizeBytes});

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
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  formatBytes(sizeBytes),
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

class _LevelCard extends StatelessWidget {
  final CompressionLevel level;
  final bool selected;
  final bool recommended;
  final int estimatedBytes;
  final VoidCallback onTap;

  const _LevelCard({
    required this.level,
    required this.selected,
    required this.recommended,
    required this.estimatedBytes,
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
                      Row(
                        children: [
                          Text(
                            level.label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (recommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text(
                                'Recommended',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        level.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '~${formatBytes(estimatedBytes)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'estimated',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompressButton extends StatelessWidget {
  final int estimatedBytes;
  final VoidCallback onTap;

  const _CompressButton({
    required this.estimatedBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ToolPrimaryButton(
        label: 'Compress to ~${formatBytes(estimatedBytes)}',
        icon: Icons.compress,
        onTap: onTap,
      ),
    );
  }
}
