import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme/colors.dart';
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
  /// Optional explicit card width. When the carousel sits above the
  /// home's 4×2 All-tools grid the caller passes the grid column
  /// width here so the recent cards align with the grid columns
  /// (no jaggy edge). Default 102 stays for any standalone use.
  final double cardWidth;
  final double cardSpacing;

  /// Tapping the "See all" link routes here. Host typically switches
  /// to the Recent tab in [RootScaffold] via `selectedTabProvider`.
  final VoidCallback onSeeAll;

  /// Tapping a "Scan / Sign / Edit Empty" placeholder routes here.
  /// Host typically pushes the Scan flow so the first card actually
  /// shows up in the carousel.
  final VoidCallback onScanShortcut;

  const RecentFilesCarousel({
    super.key,
    required this.onSeeAll,
    required this.onScanShortcut,
    this.cardWidth = 102,
    this.cardSpacing = 10,
  });

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

  void _seeAll() {
    HapticsService.instance.tap();
    widget.onSeeAll();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 0);

    final isEmpty = _files.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
          child: Row(
            children: [
              const Text(
                'Recent',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (!isEmpty)
                GestureDetector(
                  onTap: _seeAll,
                  child: const Text(
                    'See all',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 116,
          child: isEmpty
              ? _PlaceholderRow(
                  onScan: _routeToScan,
                  cardWidth: widget.cardWidth,
                  cardSpacing: widget.cardSpacing,
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _files.length,
                  separatorBuilder: (_, _) =>
                      SizedBox(width: widget.cardSpacing),
                  itemBuilder: (context, i) {
                    final f = _files[i];
                    return _RecentCard(
                      file: f,
                      width: widget.cardWidth,
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

  void _routeToScan() {
    HapticsService.instance.tap();
    widget.onScanShortcut();
  }
}

/// Empty-state strip shown when the user has no recent files yet —
/// three muted placeholder cards so the home screen always has its
/// "Recent" surface present (matches the App Store editorial mockup
/// where the section is always visible). The cards aren't fake data
/// — they read as ghost slots labelled "Scan / Sign / Edit" so the
/// user understands what kind of thing will land here.
class _PlaceholderRow extends StatelessWidget {
  final VoidCallback onScan;
  final double cardWidth;
  final double cardSpacing;
  const _PlaceholderRow({
    required this.onScan,
    required this.cardWidth,
    required this.cardSpacing,
  });

  static const _slots = <(IconData, String)>[
    (Icons.document_scanner_outlined, 'Scan'),
    (Icons.draw_outlined, 'Sign'),
    (Icons.edit_document, 'Edit'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _slots.length,
      separatorBuilder: (_, _) => SizedBox(width: cardSpacing),
      itemBuilder: (context, i) {
        final (icon, label) = _slots[i];
        return InkWell(
          onTap: onScan,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: cardWidth,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.textTertiary,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Empty',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentCard extends StatelessWidget {
  final RecentFile file;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RecentCard({
    required this.file,
    required this.width,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Compact mockup-style card: square-ish thumbnail tile up top
    // (file-type glyph in a cream/tinted square), filename + age
    // below. Tool label moves out of the card — the editorial
    // mockup leans on file identity (Lease draft / Receipts Apr)
    // not how-was-it-touched.
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: width,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.iconTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.description_outlined,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              file.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _ago(file.openedAt),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
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
