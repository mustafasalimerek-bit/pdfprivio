import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme/colors.dart';
import '../core/utils/format_bytes.dart';
import '../data/models/recent_file.dart';
import '../data/services/haptics_service.dart';
import '../data/services/recent_files_service.dart';

/// Horizontal-scrolling list of the user's most recent tool outputs.
/// Tapping opens the PDF in the default viewer; long-press offers
/// "Share" and "Remove from recents".
///
/// Rebuilds whenever `RecentFilesService` emits a change event, so a
/// fresh save lands at the front of the carousel without the home
/// screen having to pull-to-refresh.
class RecentFilesCarousel extends StatefulWidget {
  const RecentFilesCarousel({super.key});

  @override
  State<RecentFilesCarousel> createState() => _RecentFilesCarouselState();
}

class _RecentFilesCarouselState extends State<RecentFilesCarousel> {
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
      _files = files.take(8).toList();
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

  void _showActions(BuildContext context, RecentFile f) {
    HapticsService.instance.tap();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _open(f);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _share(context, f);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Remove from recents',
                  style: TextStyle(color: AppColors.error),
                ),
                subtitle: const Text(
                  "The PDF stays on your device — only this shortcut is removed.",
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _remove(f);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 0);
    if (_files.isEmpty) return const SizedBox(height: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          child: Row(
            children: [
              const Text(
                'Recent',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${_files.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _files.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final f = _files[i];
              return _RecentCard(
                file: f,
                onTap: () => _open(f),
                onLongPress: () => _showActions(context, f),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  final RecentFile file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RecentCard({
    required this.file,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                file.toolLabel,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                file.displayName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _ago(file.openedAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  formatBytes(file.sizeBytes),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
}
