import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../data/services/pdf_sign_service.dart';
import '../../data/services/pdf_thumbnail_service.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/signature_pad_dialog.dart';
import '../merge/merge_result_screen.dart';

/// One-doc Sign tool: pick PDF → choose page → draw signature → choose
/// position → stamp + write a new file with a basic ESIGN audit footer.
///
/// Free tier: a single signature, one page at a time. Pro tier (later) will
/// expose saved signature profiles, bulk sign across many docs, and the
/// extended audit chain (signer email, IP, certificate).
class SignScreen extends ConsumerStatefulWidget {
  const SignScreen({super.key});

  @override
  ConsumerState<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends ConsumerState<SignScreen> {
  PdfDocument? _doc;
  Uint8List? _signature;
  int _pageIndex = 0;
  SignaturePosition _position = SignaturePosition.bottomRight;
  final TextEditingController _signerName = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _signerName.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res == null) return;
    final path = res.paths.firstOrNull;
    if (path == null) return;

    final outcome = await PdfMetadataService.instance.inspect(File(path));
    if (!mounted) return;
    switch (outcome) {
      case Ok(:final value):
        setState(() {
          _doc = value;
          // Default to last page — the common case for "I just need to
          // sign the contract" is signing the signature page at the end.
          _pageIndex = value.pageCount - 1;
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

  Future<void> _drawSignature() async {
    HapticsService.instance.tap();
    final result = await SignaturePadDialog.show(context);
    if (!mounted || result == null) return;
    setState(() => _signature = result);
  }

  Future<void> _sign() async {
    final doc = _doc;
    final sig = _signature;
    if (doc == null || sig == null) return;

    HapticsService.instance.tap();
    setState(() => _busy = true);

    final result = await PdfSignService.instance.sign(
      input: doc,
      signaturePng: sig,
      pageIndex: _pageIndex,
      position: _position,
      signerName: _signerName.text.trim().isEmpty
          ? null
          : _signerName.text.trim(),
    );

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok(:final value):
        HapticsService.instance.success();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MergeResultScreen(
              outputFile: value,
              toolLabel: 'Signed',
              toolIdForUsage: 'sign',
              sourceCount: 1,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _doc = null;
            _signature = null;
            _signerName.clear();
          });
        }
      case Err(:final message):
        HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final canSign = doc != null && _signature != null && !_busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign PDF'),
        actions: [
          if (doc != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(() {
                  _doc = null;
                  _signature = null;
                  _signerName.clear();
                });
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PrivacyBadge(),
                  ),
                ),
                Expanded(
                  child: doc == null
                      ? _EmptyState(onPick: _pickPdf)
                      : _SignSetup(
                          doc: doc,
                          signature: _signature,
                          pageIndex: _pageIndex,
                          position: _position,
                          signerName: _signerName,
                          onPageIndex: (i) {
                            HapticsService.instance.select();
                            setState(() => _pageIndex = i);
                          },
                          onPosition: (p) {
                            HapticsService.instance.select();
                            setState(() => _position = p);
                          },
                          onDrawSignature: _drawSignature,
                        ),
                ),
                if (doc != null && !_busy)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: canSign ? _sign : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _signature == null
                              ? 'Draw signature first'
                              : 'Sign page ${_pageIndex + 1}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy)
            const ProgressOverlay(
              title: 'Adding signature',
              subtitle: 'Processing on this device — no upload',
              progress: null,
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyState({required this.onPick});

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
                Icons.draw_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sign a PDF',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              "Draw your signature with your finger or stylus, "
              'place it on any page, and save. Original is untouched.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.add),
              label: const Text('Pick a PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignSetup extends StatelessWidget {
  final PdfDocument doc;
  final Uint8List? signature;
  final int pageIndex;
  final SignaturePosition position;
  final TextEditingController signerName;
  final void Function(int) onPageIndex;
  final void Function(SignaturePosition) onPosition;
  final VoidCallback onDrawSignature;

  const _SignSetup({
    required this.doc,
    required this.signature,
    required this.pageIndex,
    required this.position,
    required this.signerName,
    required this.onPageIndex,
    required this.onPosition,
    required this.onDrawSignature,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      children: [
        _DocSummary(doc: doc),
        const SizedBox(height: 16),
        const Text(
          'Page',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _PageStrip(
          doc: doc,
          selected: pageIndex,
          onSelect: onPageIndex,
        ),
        const SizedBox(height: 16),
        _SignatureSection(
          signature: signature,
          onDraw: onDrawSignature,
        ),
        const SizedBox(height: 16),
        const Text(
          'Position',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _PositionGrid(selected: position, onSelect: onPosition),
        const SizedBox(height: 16),
        const Text(
          'Your name (optional)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Embedded into the audit footer alongside the timestamp.',
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: signerName,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'e.g. Jordan Carter',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const DisclaimerBanner(
          message: 'PDFWork embeds a SHA-256 hash + UTC timestamp as an '
              "audit footer, but it isn't a certified e-signature "
              'service. Legal binding depends on jurisdiction, the '
              'transaction type, and recipient acceptance. For '
              'high-stakes contracts, also use a service like DocuSign.',
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _DocSummary extends StatelessWidget {
  final PdfDocument doc;
  const _DocSummary({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.picture_as_pdf_outlined,
              color: AppColors.primary,
            ),
          ),
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
                const SizedBox(height: 2),
                Text(
                  '${doc.pageCount} pages · ${formatBytes(doc.sizeBytes)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
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

class _PageStrip extends StatelessWidget {
  final PdfDocument doc;
  final int selected;
  final void Function(int) onSelect;

  const _PageStrip({
    required this.doc,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // For very long PDFs we cap the visible strip to 30 and the user can
    // type a page number — but for the typical 1-30 page contract the
    // strip is enough.
    final visibleCount = doc.pageCount.clamp(0, 30);
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        itemCount: visibleCount,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return _PageThumb(
            doc: doc,
            pageIndex: index,
            isSelected: index == selected,
            onTap: () => onSelect(index),
          );
        },
      ),
    );
  }
}

class _PageThumb extends StatefulWidget {
  final PdfDocument doc;
  final int pageIndex;
  final bool isSelected;
  final VoidCallback onTap;

  const _PageThumb({
    required this.doc,
    required this.pageIndex,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends State<_PageThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The page strip reuses our single-page thumb cache; for now we render
    // the first page bitmap as a stand-in until we wire per-page thumbs.
    final bytes = await PdfThumbnailService.instance.firstPage(
      widget.doc,
      width: 160,
    );
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 80,
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(
            color:
                widget.isSelected ? AppColors.primary : AppColors.border,
            width: widget.isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _bytes == null
                ? const Center(
                    child: Icon(
                      Icons.picture_as_pdf_outlined,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                  )
                : Image.memory(_bytes!, fit: BoxFit.cover),
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'p.${widget.pageIndex + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
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

class _SignatureSection extends StatelessWidget {
  final Uint8List? signature;
  final VoidCallback onDraw;

  const _SignatureSection({required this.signature, required this.onDraw});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your signature',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (signature == null)
            SizedBox(
              width: double.infinity,
              height: 90,
              child: OutlinedButton.icon(
                onPressed: onDraw,
                icon: const Icon(Icons.draw),
                label: const Text('Draw signature'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: AppColors.primary,
                    width: 1.2,
                  ),
                  foregroundColor: AppColors.primary,
                ),
              ),
            )
          else
            Column(
              children: [
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Center(
                    child: Image.memory(
                      signature!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onDraw,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Redraw'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PositionGrid extends StatelessWidget {
  final SignaturePosition selected;
  final void Function(SignaturePosition) onSelect;

  const _PositionGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final items = SignaturePosition.values;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in items)
          ChoiceChip(
            label: Text(p.label),
            selected: p == selected,
            onSelected: (_) => onSelect(p),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: p == selected ? Colors.white : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: p == selected ? AppColors.primary : AppColors.border,
            ),
          ),
      ],
    );
  }
}
