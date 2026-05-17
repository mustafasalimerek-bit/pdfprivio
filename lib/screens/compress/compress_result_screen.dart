
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format_bytes.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/recent_files_service.dart';
import '../../data/services/usage_limits_service.dart';
import '../../providers/compress_providers.dart';
import '../../widgets/privacy_badge.dart';

class CompressResultScreen extends ConsumerStatefulWidget {
  const CompressResultScreen({super.key});

  @override
  ConsumerState<CompressResultScreen> createState() =>
      _CompressResultScreenState();
}

class _CompressResultScreenState extends ConsumerState<CompressResultScreen> {
  bool _recorded = false;

  Future<void> _share(BuildContext context, String path) async {
    HapticsService.instance.tap();
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _open(String path) async {
    HapticsService.instance.tap();
    await OpenFilex.open(path);
  }

  @override
  Widget build(BuildContext context) {
    final outcome = ref.watch(compressOutcomeProvider);
    if (outcome != null && !_recorded) {
      _recorded = true;
      // Fire-and-forget — best-effort surfacing on the home carousel.
      RecentFilesService.instance.record(
        file: outcome.compressed,
        toolLabel: 'Compressed',
      );
      UsageLimitsService.instance.recordUse('compress');
    }
    if (outcome == null) {
      // Defensive fallback — shouldn't happen because we set the provider
      // immediately before pushing this route, but bail gracefully if it does.
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Result is no longer available.')),
      );
    }

    final saved = outcome.originalBytes - outcome.compressedBytes;
    final pct = (outcome.savingRatio * 100).clamp(0, 100).toStringAsFixed(0);
    final noSavings = saved <= 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text('Done'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 52,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  noSavings ? 'Already optimized' : '$pct% smaller',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  noSavings
                      ? "This PDF was already well-compressed."
                      : 'Saved ${formatBytes(saved)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              _BeforeAfter(
                before: outcome.originalBytes,
                after: outcome.compressedBytes,
              ),
              const SizedBox(height: 16),
              const Center(child: PrivacyBadge()),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _share(context, outcome.compressed.path),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _open(outcome.compressed.path),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BeforeAfter extends StatelessWidget {
  final int before;
  final int after;

  const _BeforeAfter({required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Side(
              label: 'Before',
              size: before,
              color: AppColors.textSecondary,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.arrow_forward, color: AppColors.primary),
          ),
          Expanded(
            child: _Side(
              label: 'After',
              size: after,
              color: AppColors.primary,
              highlight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  final String label;
  final int size;
  final Color color;
  final bool highlight;

  const _Side({
    required this.label,
    required this.size,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatBytes(size),
          style: TextStyle(
            fontSize: highlight ? 22 : 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
