import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../data/models/pdf_page_ref.dart';
import '../data/services/pdf_thumbnail_service.dart';

/// A single page thumbnail used in the page-level grid view.
///
/// Each tile loads its own thumbnail asynchronously and shows a doc-name
/// chip so the user can tell at a glance which source the page came from
/// without color-coding (which doesn't scale past ~6 documents).
class PdfPageTile extends StatefulWidget {
  final PdfPageRef pageRef;
  final VoidCallback? onRemove;

  const PdfPageTile({
    super.key,
    required this.pageRef,
    this.onRemove,
  });

  @override
  State<PdfPageTile> createState() => _PdfPageTileState();
}

class _PdfPageTileState extends State<PdfPageTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PdfPageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageRef != widget.pageRef) {
      _thumb = null;
      _load();
    }
  }

  Future<void> _load() async {
    final bytes = await PdfThumbnailService.instance
        .page(widget.pageRef, width: 280);
    if (!mounted) return;
    setState(() => _thumb = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _thumb == null
                ? const Center(
                    child: Icon(
                      Icons.picture_as_pdf_outlined,
                      color: AppColors.textTertiary,
                      size: 24,
                    ),
                  )
                : Image.memory(_thumb!, fit: BoxFit.cover),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: _Pill(
              text: '${widget.pageRef.document.displayName} · '
                  'p.${widget.pageRef.pageNumber}',
            ),
          ),
          if (widget.onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
