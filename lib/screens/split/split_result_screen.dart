import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format_bytes.dart';
import '../../data/services/ads_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/recent_files_service.dart';
import '../../data/services/usage_limits_service.dart';
import '../../widgets/privacy_badge.dart';

class SplitResultScreen extends StatefulWidget {
  final List<File> files;
  const SplitResultScreen({super.key, required this.files});

  @override
  State<SplitResultScreen> createState() => _SplitResultScreenState();
}

class _SplitResultScreenState extends State<SplitResultScreen> {
  @override
  void initState() {
    super.initState();
    // Record each split output to the recents carousel. Even if the user
    // produced 20 parts, we cap to the most recent N inside the service.
    for (final f in widget.files) {
      RecentFilesService.instance.record(
        file: f,
        toolLabel: 'Split',
      );
    }
    UsageLimitsService.instance.recordUse('split');
  }

  Future<void> _shareAll(BuildContext context) async {
    HapticsService.instance.tap();
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await SharePlus.instance.share(
      ShareParams(
        files: widget.files.map((f) => XFile(f.path)).toList(),
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _shareOne(BuildContext context, File file) async {
    HapticsService.instance.tap();
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(AdsService.instance.maybeShowInterstitial());
          },
        ),
        title: const Text('Done'),
        actions: [
          if (widget.files.length > 1)
            TextButton.icon(
              onPressed: () => _shareAll(context),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Share all'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
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
            const SizedBox(height: 14),
            Center(
              child: Text(
                widget.files.length == 1
                    ? '1 file ready'
                    : '${widget.files.length} files ready',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(child: PrivacyBadge()),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.files.length,
                itemBuilder: (context, index) {
                  final f = widget.files[index];
                  return _OutputTile(
                    file: f,
                    onShare: () => _shareOne(context, f),
                    onOpen: () {
                      HapticsService.instance.tap();
                      OpenFilex.open(f.path);
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(AdsService.instance.maybeShowInterstitial());
                  },
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutputTile extends StatelessWidget {
  final File file;
  final VoidCallback onShare;
  final VoidCallback onOpen;

  const _OutputTile({
    required this.file,
    required this.onShare,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final size = file.statSync().size;
    final name = file.uri.pathSegments.last;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.picture_as_pdf_outlined,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatBytes(size),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 20),
            tooltip: 'Open',
            onPressed: onOpen,
            color: AppColors.textSecondary,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            tooltip: 'Share',
            onPressed: onShare,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
