import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/recent_file.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/quick_look_service.dart';
import '../../data/services/recent_files_service.dart';
import '../scan/scan_screen.dart';

/// Full-screen list of recent tool outputs. Editorial design: large
/// title + privacy pill, paper-glyph hero in the empty state, search
/// + filter chips + date-grouped sections in the populated state.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const _RecentHeader(),
        const Spacer(),
        const Center(child: _PaperStackHero()),
        const SizedBox(height: 28),
        const Text(
          'Nothing here yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            'Every PDF you scan, sign, or edit lands here for quick access.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.camera_alt_outlined, size: 20),
              label: const Text(
                'Scan your first PDF',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onOpenFromFiles,
          icon: const Icon(Icons.folder_outlined, size: 18),
          label: const Text(
            'Open from Files',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _RecentHeader extends StatelessWidget {
  const _RecentHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Stays on your iPhone',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
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

class _PaperStackHero extends StatelessWidget {
  const _PaperStackHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 12,
            top: 26,
            child: Transform.rotate(
              angle: -0.12,
              child: _PaperGlyph(opacity: 0.55, width: 68, height: 84),
            ),
          ),
          Positioned(
            right: 12,
            top: 14,
            child: Transform.rotate(
              angle: 0.10,
              child: _PaperGlyph(opacity: 1, width: 68, height: 84),
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
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in [44.0, 36.0, 28.0])
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'Recent',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: onClearAll,
                  child: Text(
                    '$totalCount ${totalCount == 1 ? 'file' : 'files'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: _SearchBar(
            controller: searchController,
            onChanged: onSearch,
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final label = filters[i];
              return _FilterChip(
                label: label,
                selected: label == activeFilter,
                onTap: () => onFilter(label),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: files.isEmpty
              ? const _NoResultsState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: grouped.length,
                  itemBuilder: (context, i) {
                    final section = grouped[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                          child: Text(
                            section.label.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textTertiary,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              for (var j = 0; j < section.files.length; j++) ...[
                                _RecentRow(
                                  file: section.files[j],
                                  onTap: () => onTap(section.files[j]),
                                  onShare: () => onShare(section.files[j]),
                                  onDelete: () =>
                                      onDelete(section.files[j]),
                                ),
                                if (j != section.files.length - 1)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: AppColors.border
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    );
                  },
                ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(99),
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
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: AppColors.textTertiary,
            size: 20,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No matches.',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final RecentFile file;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  const _RecentRow({
    required this.file,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
          children: [
            _MiniPaper(),
            const SizedBox(width: 12),
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
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
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
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_horiz,
                color: AppColors.textTertiary,
                size: 22,
              ),
              tooltip: 'More',
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
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPaper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 46,
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
