import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/utils/format_bytes.dart';
import '../data/models/pdf_document.dart';
import '../data/services/pdf_thumbnail_service.dart';

/// Visual representation of one PDF in a workspace list.
///
/// Loads its own thumbnail asynchronously so the parent list doesn't have
/// to pre-render every page before showing anything. While the thumbnail
/// loads, a placeholder keeps the row from jumping in size.
class PdfDocTile extends StatefulWidget {
  final PdfDocument document;
  final VoidCallback? onRemove;

  /// Reorder drag handle from ReorderableListView. Pass through so the row
  /// can put it on the trailing side at the right size.
  final Widget? reorderHandle;

  const PdfDocTile({
    super.key,
    required this.document,
    this.onRemove,
    this.reorderHandle,
  });

  @override
  State<PdfDocTile> createState() => _PdfDocTileState();
}

class _PdfDocTileState extends State<PdfDocTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final bytes =
        await PdfThumbnailService.instance.firstPage(widget.document);
    if (!mounted) return;
    setState(() => _thumb = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _Thumbnail(bytes: _thumb),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'} · ${formatBytes(doc.sizeBytes)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onRemove != null)
            IconButton(
              icon: const Icon(
                Icons.close,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onPressed: widget.onRemove,
              tooltip: 'Remove',
            ),
          if (widget.reorderHandle != null) widget.reorderHandle!,
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final Uint8List? bytes;
  const _Thumbnail({this.bytes});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: bytes == null
          ? const Icon(
              Icons.picture_as_pdf_outlined,
              color: AppColors.textTertiary,
              size: 20,
            )
          : Image.memory(bytes!, fit: BoxFit.cover),
    );
  }
}
