import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../core/theme/colors.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_outline_service.dart';
import '../../data/services/share_intent_service.dart';
import '../../widgets/privacy_badge.dart';

/// Bookmarks / Table of Contents viewer.
///
/// Pick a PDF, get its outline tree as a tappable list. Tap an entry,
/// jump straight to that page in an embedded pdfx viewer — no scrolling
/// 200 pages to find chapter 7. Useful for legal briefs, depositions,
/// audit reports with structured TOCs.
class BookmarksScreen extends ConsumerStatefulWidget {
  const BookmarksScreen({super.key});

  @override
  ConsumerState<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends ConsumerState<BookmarksScreen> {
  File? _file;
  List<PdfOutlineEntry>? _outline;
  bool _busy = false;
  bool _noOutline = false;

  @override
  void initState() {
    super.initState();
    final pending = PendingSharedFile.consume();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFromFile(pending);
      });
    }
  }

  Future<void> _pickPdf() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = res?.paths.firstOrNull;
    if (path == null) return;
    await _loadFromFile(File(path));
  }

  Future<void> _loadFromFile(File file) async {
    setState(() {
      _busy = true;
      _noOutline = false;
      _file = file;
      _outline = null;
    });
    final outline = await PdfOutlineService.instance.parse(file);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outline = outline;
      _noOutline = outline == null;
    });
    if (outline != null) HapticsService.instance.select();
  }

  void _openAtPage(PdfOutlineEntry entry) {
    final file = _file;
    if (file == null || entry.pageIndex < 0) return;
    HapticsService.instance.tap();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PageViewerScreen(
          file: file,
          initialPage: entry.pageIndex,
          title: entry.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks / TOC'),
        actions: [
          if (_file != null)
            IconButton(
              icon: const Icon(Icons.file_open_outlined),
              onPressed: _pickPdf,
              tooltip: 'Pick another PDF',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Center(child: PrivacyBadge()),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_file == null) {
      return _EmptyState(onPick: _pickPdf);
    }
    if (_noOutline) {
      return _NoOutlineState(filename: _file!.path.split('/').last, onPick: _pickPdf);
    }
    final outline = _outline;
    if (outline == null || outline.isEmpty) {
      return _NoOutlineState(filename: _file!.path.split('/').last, onPick: _pickPdf);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      children: outline.map((e) => _entryTile(e)).toList(),
    );
  }

  Widget _entryTile(PdfOutlineEntry entry) {
    final pageLabel = entry.pageIndex >= 0 ? 'p. ${entry.pageIndex + 1}' : '—';
    if (entry.hasChildren) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.only(left: 16.0 + entry.level * 12, right: 8),
          childrenPadding: EdgeInsets.zero,
          initiallyExpanded: entry.level == 0,
          title: Text(
            entry.title,
            style: TextStyle(
              fontSize: 14 - (entry.level * 0.5).clamp(0, 2),
              fontWeight: entry.level == 0
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
          subtitle: Text(
            pageLabel,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 14),
            onPressed: () => _openAtPage(entry),
            tooltip: 'Open at page ${entry.pageIndex + 1}',
          ),
          children: entry.children.map(_entryTile).toList(),
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.only(left: 16.0 + entry.level * 12, right: 16),
      dense: true,
      title: Text(
        entry.title,
        style: TextStyle(
          fontSize: 14 - (entry.level * 0.5).clamp(0, 2),
          fontWeight: entry.level == 0
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
      trailing: Text(
        pageLabel,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => _openAtPage(entry),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyState({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined,
              size: 64, color: AppColors.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Browse a PDF by its built-in outline',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Legal briefs, depositions, audit reports — jump to a '
              'chapter in one tap instead of scrolling 200 pages.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.add),
            label: const Text('Pick a PDF'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoOutlineState extends StatelessWidget {
  final String filename;
  final VoidCallback onPick;
  const _NoOutlineState({required this.filename, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_remove_outlined,
              size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '$filename has no bookmarks',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'This PDF was generated without a table of contents. Most '
              'auto-export tools (browser print, Word save-as-PDF) skip '
              'bookmarks. Try a PDF from a publisher or court system.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Try another PDF'),
          ),
        ],
      ),
    );
  }
}

/// Lightweight viewer used when a bookmark is tapped. Renders the PDF
/// with pdfx + jumps to the bookmark's page on open.
class _PageViewerScreen extends StatefulWidget {
  final File file;
  final int initialPage;
  final String title;

  const _PageViewerScreen({
    required this.file,
    required this.initialPage,
    required this.title,
  });

  @override
  State<_PageViewerScreen> createState() => _PageViewerScreenState();
}

class _PageViewerScreenState extends State<_PageViewerScreen> {
  late final pdfx.PdfController _controller;

  @override
  void initState() {
    super.initState();
    _controller = pdfx.PdfController(
      document: pdfx.PdfDocument.openFile(widget.file.path),
      initialPage: widget.initialPage + 1, // pdfx is 1-based
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: pdfx.PdfView(controller: _controller),
    );
  }
}
