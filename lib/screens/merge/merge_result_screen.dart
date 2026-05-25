import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/recent_files_service.dart';
import '../../data/services/share_service.dart';
import '../../data/services/usage_limits_service.dart';
import '../../widgets/privacy_badge.dart';

class MergeResultScreen extends StatefulWidget {
  final File outputFile;
  final int sourceCount;

  /// Set when the user hand-picked pages instead of using doc-level merge —
  /// changes the subheader from "N PDFs combined" to "N pages combined".
  final int? pageCount;

  /// Short label that goes on the recent-files chip. Defaults to "Merged"
  /// for backwards compat with the original caller; every new caller
  /// (Image to PDF, Scan, OCR, Form Fill, etc.) passes its own.
  final String toolLabel;

  /// Optional UsageLimitsService tool id. When set, mounting this
  /// screen records one daily use against the free-tier quota. Pro
  /// users are bypassed inside the service. Pro-only tools (Form Fill,
  /// Bates) intentionally pass null — they never count against quota
  /// because their gate is the paywall, not a counter.
  final String? toolIdForUsage;

  const MergeResultScreen({
    super.key,
    required this.outputFile,
    required this.sourceCount,
    this.pageCount,
    this.toolLabel = 'Merged',
    this.toolIdForUsage,
  });

  @override
  State<MergeResultScreen> createState() => _MergeResultScreenState();
}

class _MergeResultScreenState extends State<MergeResultScreen> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget: surfacing this on the home screen is best-effort.
    RecentFilesService.instance.record(
      file: widget.outputFile,
      toolLabel: widget.toolLabel,
    );
    final usageId = widget.toolIdForUsage;
    if (usageId != null) {
      UsageLimitsService.instance.recordUse(usageId);
    }
  }

  Future<void> _share(BuildContext context) async {
    HapticsService.instance.tap();
    await ShareService.shareWithFeedback(
      context,
      ShareParams(
        files: [XFile(widget.outputFile.path)],
        sharePositionOrigin: ShareService.originFromContext(context),
      ),
    );
  }

  Future<void> _open() async {
    HapticsService.instance.tap();
    await OpenFilex.open(widget.outputFile.path);
  }

  void _closeWithAd() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.outputFile.statSync().size;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: _closeWithAd,
        ),
        title: const Text('Merged'),
      ),
      body: SafeArea(
        child: MaxWidthBody(
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
              const Center(
                child: Text(
                  'Merge complete',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  widget.pageCount != null
                      ? '${widget.pageCount} pages · ${formatBytes(size)}'
                      : '${widget.sourceCount} PDFs combined · ${formatBytes(size)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(child: PrivacyBadge()),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _share(context),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _closeWithAd,
                child: const Text('Done'),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
