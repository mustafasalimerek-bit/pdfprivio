import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/recent_file.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/recent_files_service.dart';

/// Full-screen list of recent tool outputs. Differs from the home
/// carousel in that we list every recent (up to 30), show file size +
/// path detail, and offer swipe-to-delete.
class RecentScreen extends StatefulWidget {
  const RecentScreen({super.key});

  @override
  State<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends State<RecentScreen> {
  List<RecentFile> _files = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    RecentFilesService.instance.changes.listen((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final files = await RecentFilesService.instance.getAll();
    if (!mounted) return;
    setState(() {
      _files = files;
      _loaded = true;
    });
  }

  Future<void> _open(RecentFile f) async {
    HapticsService.instance.tap();
    await OpenFilex.open(f.path);
  }

  Future<void> _share(BuildContext context, RecentFile f) async {
    HapticsService.instance.tap();
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path)],
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _remove(RecentFile f) async {
    HapticsService.instance.select();
    await RecentFilesService.instance.remove(f.id);
  }

  Future<void> _confirmClearAll() async {
    HapticsService.instance.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear recents?'),
        content: const Text(
          "This removes the shortcuts only — the PDF files stay on your "
          'device. You can find them again via Files.app or by re-opening '
          'them in the relevant tool.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await RecentFilesService.instance.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Recent',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_files.isNotEmpty)
            TextButton(
              onPressed: _confirmClearAll,
              child: const Text('Clear'),
            ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthBody(
          child: !_loaded
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _files.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _files.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final f = _files[i];
                      return Dismissible(
                        key: ValueKey(f.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                        onDismissed: (_) => _remove(f),
                        child: _RecentRow(
                          file: f,
                          onTap: () => _open(f),
                          onShare: () => _share(context, f),
                        ),
                      );
                    },
                  ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
                Icons.history_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No recent files yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Every PDF you produce with a tool — redacted, signed, '
              'scanned, OCR-d — lands here. Tap to re-open or share.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final RecentFile file;
  final VoidCallback onTap;
  final VoidCallback onShare;
  const _RecentRow({
    required this.file,
    required this.onTap,
    required this.onShare,
  });

  String _ago(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    final weeks = (delta.inDays / 7).floor();
    if (weeks < 4) return '${weeks}w ago';
    return '${(delta.inDays / 30).floor()}mo ago';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            file.toolLabel,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _ago(file.openedAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.displayName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      formatBytes(file.sizeBytes),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onShare,
                tooltip: 'Share',
                icon: const Icon(
                  Icons.ios_share,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
