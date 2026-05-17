import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/layout.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/recent_file.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/quick_look_service.dart';
import '../../data/services/recent_files_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/privacy_pill.dart';
import '../../widgets/screen_container.dart';
import '../../widgets/section_header.dart';
import '../scan/scan_screen.dart';

/// Full-screen list of recent tool outputs.
///
/// Empty state uses [CenteredScreenContainer] so the hero illustration
/// lands at the optical center on iPhone 17 Pro Max instead of
/// floating in negative space at the top. Populated state uses
/// [ScreenContainer] — same horizontal padding and title font, so
/// the user feels the same layout grammar across nav tabs.
class RecentScreen extends StatefulWidget {
  const RecentScreen({super.key});

  @override
  State<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends State<RecentScreen> {
  List<RecentFile> _files = const [];
  bool _loaded = false;
  String _query = '';
  String _filter = 'All';
  final TextEditingController _searchController = TextEditingController();

  static const List<String> _filterChips = [
    'All',
    'Scanned',
    'Signed',
    'Merged',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    RecentFilesService.instance.changes.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _scanFirst() async {
    HapticsService.instance.tap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
  }

  Future<void> _openFromFiles() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = res?.paths.firstOrNull;
    if (path == null) return;
    await QuickLookService.instance.show(File(path));
  }

  List<RecentFile> get _filtered {
    return _files.where((f) {
      if (_filter != 'All' && f.toolLabel != _filter) return false;
      if (_query.isEmpty) return true;
      return f.displayName.toLowerCase().contains(_query.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                  ? _EmptyState(
                      onScan: _scanFirst,
                      onOpenFromFiles: _openFromFiles,
                    )
                  : _Populated(
                      files: _filtered,
                      totalCount: _files.length,
                      searchController: _searchController,
                      onSearch: (v) => setState(() => _query = v),
                      activeFilter: _filter,
                      onFilter: (f) {
                        HapticsService.instance.select();
                        setState(() => _filter = f);
                      },
                      filters: _filterChips,
                      onTap: _open,
                      onShare: (f) => _share(context, f),
                      onDelete: _remove,
                      onClearAll: _confirmClearAll,
                    ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onOpenFromFiles;
  const _EmptyState({required this.onScan, required this.onOpenFromFiles});

  @override
  Widget build(BuildContext context) {
    return CenteredScreenContainer(
      topBar: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text(
            'Recent',
            style: TextStyle(
              fontSize: Layout.titleFontSize,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
              height: 1.1,
            ),
          ),
          SizedBox(height: 8),
          PrivacyPill(),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _PaperStackHero(),
          const SizedBox(height: 22),
          const Text(
            'Nothing here yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Every PDF you scan, sign, or edit lands here for quick access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            title: 'Scan your first PDF',
            icon: Icons.camera_alt_outlined,
            onPressed: onScan,
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onOpenFromFiles,
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: const Text(
              'Open from Files',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperStackHero extends StatelessWidget {
  const _PaperStackHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: Layout.emptyStateIllustrationSize,
      height: Layout.emptyStateIllustrationSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 10,
            top: 22,
            child: Transform.rotate(
              angle: -0.12,
              child: const _PaperGlyph(opacity: 0.55, width: 62, height: 78),
            ),
          ),
          Positioned(
            right: 10,
            top: 12,
            child: Transform.rotate(
              angle: 0.10,
              child: const _PaperGlyph(opacity: 1, width: 62, height: 78),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperGlyph extends StatelessWidget {
  final double opacity;
  final double width;
  final double height;
  const _PaperGlyph({
    required this.opacity,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.fromLTRB(9, 14, 9, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in [40.0, 32.0, 24.0])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  width: w,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.iconTint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Populated extends StatelessWidget {
  final List<RecentFile> files;
  final int totalCount;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final String activeFilter;
  final ValueChanged<String> onFilter;
  final List<String> filters;
  final ValueChanged<RecentFile> onTap;
  final ValueChanged<RecentFile> onShare;
  final ValueChanged<RecentFile> onDelete;
  final VoidCallback onClearAll;

  const _Populated({
    required this.files,
    required this.totalCount,
    required this.searchController,
    required this.onSearch,
    required this.activeFilter,
    required this.onFilter,
    required this.filters,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(files);
    return ScreenContainer(
      title: 'Recent',
      titleTrailing: GestureDetector(
        onTap: onClearAll,
        behavior: HitTestBehavior.opaque,
        child: Text(
          '$totalCount ${totalCount == 1 ? 'file' : 'files'}',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PrivacyPill(),
          const SizedBox(height: 14),
          _SearchBar(
            controller: searchController,
            onChanged: onSearch,
          ),
          const SizedBox(height: 10),
          _FilterRow(
            filters: filters,
            activeFilter: activeFilter,
            onFilter: onFilter,
          ),
          const SizedBox(height: 14),
          if (files.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No matches.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            for (final section in grouped) ...[
              SectionHeader(section.label),
              AppCard(
                children: [
                  for (var i = 0; i < section.files.length; i++)
                    CardRow(
                      isLast: i == section.files.length - 1,
                      onTap: () => onTap(section.files[i]),
                      leading: _RecentRowLeading(file: section.files[i]),
                      trailing: _RecentRowMenu(
                        onShare: () => onShare(section.files[i]),
                        onDelete: () => onDelete(section.files[i]),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Layout.sectionSpacing),
            ],
        ],
      ),
    );
  }

  List<_Section> _groupByDate(List<RecentFile> files) {
    if (files.isEmpty) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));
    final byBucket = <String, List<RecentFile>>{};
    for (final f in files) {
      final d = DateTime(f.openedAt.year, f.openedAt.month, f.openedAt.day);
      final String bucket;
      if (d == today) {
        bucket = 'Today';
      } else if (d == yesterday) {
        bucket = 'Yesterday';
      } else if (d.isAfter(weekAgo)) {
        bucket = 'This Week';
      } else {
        bucket = 'Earlier';
      }
      byBucket.putIfAbsent(bucket, () => []).add(f);
    }
    const order = ['Today', 'Yesterday', 'This Week', 'Earlier'];
    return [
      for (final label in order)
        if (byBucket[label] != null) _Section(label, byBucket[label]!),
    ];
  }
}

class _Section {
  final String label;
  final List<RecentFile> files;
  const _Section(this.label, this.files);
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: const InputDecoration(
          hintText: 'Search by name or content',
          hintStyle: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: AppColors.textTertiary,
            size: 18,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          isDense: true,
        ),
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final List<String> filters;
  final String activeFilter;
  final ValueChanged<String> onFilter;

  const _FilterRow({
    required this.filters,
    required this.activeFilter,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final label = filters[i];
          return _FilterChip(
            label: label,
            selected: label == activeFilter,
            onTap: () => onFilter(label),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRowLeading extends StatelessWidget {
  final RecentFile file;
  const _RecentRowLeading({required this.file});

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

  IconData _toolIcon() {
    switch (file.toolLabel) {
      case 'Signed':
        return Icons.draw_outlined;
      case 'Merged':
        return Icons.content_copy_outlined;
      case 'Scanned':
        return Icons.document_scanner_outlined;
      case 'Compressed':
        return Icons.compress;
      case 'Rotated':
        return Icons.rotate_right;
      case 'Redacted':
        return Icons.format_color_fill;
      case 'Watermarked':
        return Icons.water_drop_outlined;
      case 'Searchable':
        return Icons.find_in_page_outlined;
      case 'Image to PDF':
        return Icons.image_outlined;
      case 'Form filled':
        return Icons.edit_document;
      case 'Password':
        return Icons.lock_outline;
      case 'Bates':
        return Icons.tag;
      case 'Numbered':
        return Icons.format_list_numbered;
      case 'Pages deleted':
        return Icons.delete_sweep_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _MiniPaper(),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                file.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    _toolIcon(),
                    size: 12,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '${file.toolLabel} · ${_ago(file.openedAt)} · '
                      '${formatBytes(file.sizeBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentRowMenu extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onDelete;
  const _RecentRowMenu({required this.onShare, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_horiz,
        color: AppColors.textTertiary,
        size: 20,
      ),
      tooltip: 'More',
      padding: EdgeInsets.zero,
      onSelected: (v) {
        switch (v) {
          case 'share':
            onShare();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.ios_share, size: 18),
              SizedBox(width: 10),
              Text('Share'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.error,
              ),
              SizedBox(width: 10),
              Text(
                'Remove from recents',
                style: TextStyle(color: AppColors.error),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniPaper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 44,
      padding: const EdgeInsets.fromLTRB(6, 9, 6, 0),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in const [22.0, 18.0, 14.0])
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Container(
                width: w,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.iconTint,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
