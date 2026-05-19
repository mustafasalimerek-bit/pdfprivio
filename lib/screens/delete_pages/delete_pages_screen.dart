import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_delete_pages_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../data/services/pdf_thumbnail_service.dart';
import '../../data/services/scan_pickup_service.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';
import '../merge/merge_result_screen.dart';

/// Single-PDF page grid with multi-select. The selected pages are the ones
/// that will be removed. Selection is the safer interaction than swipe-to-
/// dismiss because the user can take their time, review, and bail.
class DeletePagesScreen extends ConsumerStatefulWidget {
  const DeletePagesScreen({super.key});

  @override
  ConsumerState<DeletePagesScreen> createState() => _DeletePagesScreenState();
}

class _DeletePagesScreenState extends ConsumerState<DeletePagesScreen> {
  PdfDocument? _doc;
  final Set<int> _selected = {};
  double? _progress;
  CancellationToken? _cancel;

  Future<void> _pick() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = res?.paths.firstOrNull;
    if (path == null) return;
    await _loadFile(File(path));
  }

  Future<void> _scanPdf() async {
    HapticsService.instance.tap();
    final res = await ScanPickupService.instance.scanToPdf();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        await _loadFile(value);
      case Err(:final kind, :final message):
        if (kind != FailureKind.cancelled) {
          HapticsService.instance.error();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }

  Future<void> _loadFile(File file) async {
    final outcome = await PdfMetadataService.instance.inspect(file);
    if (!mounted) return;
    switch (outcome) {
      case Ok(:final value):
        setState(() {
          _doc = value;
          _selected.clear();
        });
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

  Future<void> _delete() async {
    final doc = _doc;
    if (doc == null || _selected.isEmpty) return;
    HapticsService.instance.tap();
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
    });

    final result = await PdfDeletePagesService.instance.deletePages(
      input: doc,
      pageIndicesToDelete: _selected,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      cancel: cancel,
    );

    if (!mounted) return;
    setState(() {
      _progress = null;
      _cancel = null;
    });

    switch (result) {
      case Ok(:final value):
        HapticsService.instance.success();
        final keptCount = doc.pageCount - _selected.length;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MergeResultScreen(
              outputFile: value,
              toolLabel: 'Pages deleted',
              toolIdForUsage: 'delete_pages',
              sourceCount: 1,
              pageCount: keptCount,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _doc = null;
            _selected.clear();
          });
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
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete pages'),
        centerTitle: true,
        actions: [
          if (doc != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(() {
                  _doc = null;
                  _selected.clear();
                });
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: MaxWidthBody(
        child: Stack(
          children: [
            SafeArea(
              child: doc == null
                  ? _EmptyState(onPick: _pick, onScan: _scanPdf)
                  : Column(
                      children: [
                        Expanded(
                          child: _Picker(
                            doc: doc,
                            selected: _selected,
                            onToggle: (index) {
                              HapticsService.instance.select();
                              setState(() {
                                if (_selected.contains(index)) {
                                  _selected.remove(index);
                                } else {
                                  _selected.add(index);
                                }
                              });
                            },
                            onSelectAll: () {
                              HapticsService.instance.tap();
                              setState(() {
                                if (_selected.length == doc.pageCount) {
                                  _selected.clear();
                                } else {
                                  _selected
                                    ..clear()
                                    ..addAll(
                                      List.generate(doc.pageCount, (i) => i),
                                    );
                                }
                              });
                            },
                          ),
                        ),
                        if (_progress == null && _selected.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _selected.length >= doc.pageCount
                                    ? null
                                    : _delete,
                                icon: const Icon(Icons.delete_sweep, size: 20),
                                label: Text(
                                  _selected.length >= doc.pageCount
                                      ? "Can't delete every page"
                                      : 'Delete ${_selected.length} '
                                          'page${_selected.length == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                  disabledBackgroundColor:
                                      AppColors.error.withValues(alpha: 0.35),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            if (_progress != null)
              ProgressOverlay(
                progress: _progress,
                title: 'Rebuilding PDF',
                subtitle: 'Processing on this device — no upload',
                onCancel: () => _cancel?.cancel(),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  final VoidCallback onScan;
  const _EmptyState({required this.onPick, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return ToolEmptyState(
      heroIcon: Icons.delete_sweep_outlined,
      title: 'Delete pages',
      subtitle: 'Pick the pages to drop, keep the rest',
      primaryLabel: 'Pick a PDF',
      onPrimary: onPick,
      altSources: [
        ToolAltSource(
          icon: Icons.camera_alt_outlined,
          label: 'Scan',
          onTap: onScan,
        ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  final PdfDocument doc;
  final Set<int> selected;
  final void Function(int) onToggle;
  final VoidCallback onSelectAll;

  const _Picker({
    required this.doc,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = selected.length == doc.pageCount;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected.isEmpty
                      ? '${doc.pageCount} pages · tap to select'
                      : '${selected.length} of ${doc.pageCount} selected',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSelectAll,
                child: Text(allSelected ? 'Clear' : 'Select all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.72,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: doc.pageCount,
            itemBuilder: (context, index) {
              return _PageCell(
                doc: doc,
                pageIndex: index,
                isSelected: selected.contains(index),
                onTap: () => onToggle(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PageCell extends StatefulWidget {
  final PdfDocument doc;
  final int pageIndex;
  final bool isSelected;
  final VoidCallback onTap;

  const _PageCell({
    required this.doc,
    required this.pageIndex,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_PageCell> createState() => _PageCellState();
}

class _PageCellState extends State<_PageCell> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Render via the global thumbnail cache so neighbours don't fight for
    // PDFKit handles when the user is scrolling fast.
    final bytes = await PdfThumbnailService.instance.firstPage(
      widget.doc,
      width: 280,
    );
    if (!mounted) return;
    setState(() => _thumb = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(
            color: widget.isSelected ? AppColors.error : AppColors.border,
            width: widget.isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumb != null)
              ColorFiltered(
                colorFilter: widget.isSelected
                    ? ColorFilter.mode(
                        AppColors.error.withValues(alpha: 0.25),
                        BlendMode.srcATop,
                      )
                    : const ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.dst,
                      ),
                child: Image.memory(_thumb!, fit: BoxFit.cover),
              )
            else
              const Center(
                child: Icon(
                  Icons.picture_as_pdf_outlined,
                  color: AppColors.textTertiary,
                  size: 24,
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'p.${widget.pageIndex + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: AnimatedScale(
                scale: widget.isSelected ? 1 : 0.8,
                duration: const Duration(milliseconds: 140),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color:
                        widget.isSelected ? AppColors.error : Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isSelected
                        ? Icons.delete_outline
                        : Icons.radio_button_unchecked,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
