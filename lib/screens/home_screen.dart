import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/colors.dart';
import '../data/services/haptics_service.dart';
import '../data/services/purchase_service.dart';
import '../data/services/usage_limits_service.dart';
import '../widgets/paywall_sheet.dart';
import 'bates/bates_screen.dart';
import 'batch/batch_screen.dart';
import 'compare/compare_screen.dart';
import 'compress/compress_screen.dart';
import 'delete_pages/delete_pages_screen.dart';
import 'bookmarks/bookmarks_screen.dart';
import 'extract_text/extract_text_screen.dart';
import 'form_fill/form_fill_screen.dart';
import 'quick_look/quick_look_launcher_screen.dart';
import 'summarize/summarize_screen.dart';
import 'image_to_pdf/image_to_pdf_screen.dart';
import 'merge/merge_screen.dart';
import 'ocr_pdf/ocr_pdf_screen.dart';
import 'page_numbers/page_numbers_screen.dart';
import 'password/password_screen.dart';
import 'pii_scan/pii_scan_screen.dart';
import 'redact/redact_screen.dart';
import 'rotate/rotate_screen.dart';
import 'scan/scan_screen.dart';
import 'sign/sign_screen.dart';
import 'split/split_screen.dart';
import 'watermark/watermark_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PDFPrivio',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 4),
            const Text(
              'Offline PDF tools',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _ToolTile(
              icon: Icons.document_scanner_outlined,
              title: 'Scan to PDF',
              subtitle: 'Camera → auto-edge → multi-page → one PDF',
              toolId: 'scan_to_pdf',
              builder: (_) => const ScanScreen(),
            ),
            _ToolTile(
              icon: Icons.find_in_page_outlined,
              title: 'OCR PDF',
              subtitle: 'Scanned PDF → searchable text (Apple Vision)',
              toolId: 'ocr_pdf',
              builder: (_) => const OcrPdfScreen(),
            ),
            _ToolTile(
              icon: Icons.library_books_outlined,
              title: 'Merge PDFs',
              subtitle: 'Combine multiple PDFs into one',
              toolId: 'merge',
              builder: (_) => const MergeScreen(),
            ),
            _ToolTile(
              icon: Icons.compress_outlined,
              title: 'Compress PDF',
              subtitle: 'Shrink for email — keep quality',
              toolId: 'compress',
              builder: (_) => const CompressScreen(),
            ),
            _ToolTile(
              icon: Icons.content_cut_outlined,
              title: 'Split PDF',
              subtitle: 'Extract range, every N pages, or N parts',
              toolId: 'split',
              builder: (_) => const SplitScreen(),
            ),
            _ToolTile(
              icon: Icons.image_outlined,
              title: 'Image to PDF',
              subtitle: 'Photos, receipts, screenshots → one PDF',
              toolId: 'image_to_pdf',
              builder: (_) => const ImageToPdfScreen(),
            ),
            _ToolTile(
              icon: Icons.rotate_right_outlined,
              title: 'Rotate pages',
              subtitle: 'Fix sideways scans or flip a PDF',
              toolId: 'rotate',
              builder: (_) => const RotateScreen(),
            ),
            _ToolTile(
              icon: Icons.delete_sweep_outlined,
              title: 'Delete pages',
              subtitle: 'Pick the pages to drop, keep the rest',
              toolId: 'delete_pages',
              builder: (_) => const DeletePagesScreen(),
            ),
            _ToolTile(
              icon: Icons.draw_outlined,
              title: 'Sign PDF',
              subtitle: 'Draw, place, save — audit-trail included',
              toolId: 'sign',
              builder: (_) => const SignScreen(),
            ),
            _ToolTile(
              icon: Icons.edit_document,
              title: 'Fill form',
              subtitle: 'IRS, USCIS, court forms — flatten on save',
              toolId: 'form_fill',
              builder: (_) => const FormFillScreen(),
            ),
            _ToolTile(
              icon: Icons.format_list_numbered,
              title: 'Page numbers',
              subtitle: 'Page 1 of 20 — pick format and position',
              toolId: 'page_numbers',
              builder: (_) => const PageNumbersScreen(),
            ),
            _ToolTile(
              icon: Icons.tag,
              title: 'Bates numbering',
              subtitle: 'Sequential page IDs — legal discovery standard',
              toolId: 'bates',
              builder: (_) => const BatesScreen(),
            ),
            _ToolTile(
              icon: Icons.lock_outline,
              title: 'Password protect',
              subtitle: 'AES-256 encrypt or unlock — pick auto-detects',
              toolId: 'password',
              builder: (_) => const PasswordScreen(),
            ),
            _ToolTile(
              icon: Icons.water_drop_outlined,
              title: 'Watermark',
              subtitle: 'CONFIDENTIAL / DRAFT — diagonal, center, or tile',
              toolId: 'watermark',
              builder: (_) => const WatermarkScreen(),
            ),
            _ToolTile(
              icon: Icons.text_snippet_outlined,
              title: 'Extract text',
              subtitle: 'Pull text out — born-digital PDFs only',
              toolId: 'extract_text',
              builder: (_) => const ExtractTextScreen(),
            ),
            _ToolTile(
              icon: Icons.compare_arrows,
              title: 'Compare PDFs',
              subtitle: 'Redline two versions — added & removed text',
              toolId: 'compare',
              builder: (_) => const CompareScreen(),
            ),
            _ToolTile(
              icon: Icons.menu_book_outlined,
              title: 'Bookmarks / TOC',
              subtitle: 'Jump to a chapter in one tap — long briefs, depositions',
              toolId: 'bookmarks',
              builder: (_) => const BookmarksScreen(),
            ),
            _ToolTile(
              icon: Icons.auto_awesome,
              title: 'Summarize PDF',
              subtitle: 'On-device Apple Intelligence summary — never uploaded',
              toolId: 'summarize',
              builder: (_) => const SummarizeScreen(),
            ),
            _ToolTile(
              icon: Icons.center_focus_strong_outlined,
              title: 'Live Text view',
              subtitle: 'Select text from any PDF page — Apple Live Text + Markup',
              toolId: 'quick_look',
              builder: (_) => const QuickLookLauncherScreen(),
            ),
            _ToolTile(
              icon: Icons.dynamic_feed_outlined,
              title: 'Batch operations',
              subtitle: 'Compress / Watermark / Rotate many PDFs at once',
              toolId: 'batch',
              builder: (_) => const BatchScreen(),
            ),
            _ToolTile(
              icon: Icons.shield_outlined,
              title: 'Find sensitive data',
              subtitle: 'Auto-detect SSN, EIN, credit cards, emails, phone numbers',
              toolId: 'pii_scan',
              builder: (_) => const PiiScanScreen(),
            ),
            _ToolTile(
              icon: Icons.format_color_fill,
              title: 'Redact',
              subtitle: 'Search and black out names, account numbers, etc.',
              toolId: 'redact',
              builder: (_) => const RedactScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row in the tool grid that knows about Pro entitlement and daily
/// usage caps:
///   * Pro user → unlimited; clean tile, no badge
///   * Free user on a Pro-only tool → "PRO" badge + lock icon, tap
///     opens the paywall
///   * Free user on a limited tool with quota remaining → "N / Day"
///     counter chip, tap navigates and the tool screen itself records
///     the use on success
///   * Free user on a limited tool over quota → "Used today" chip in
///     warning colour, tap opens the paywall with quota context
class _ToolTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String toolId;
  final WidgetBuilder builder;

  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.toolId,
    required this.builder,
  });

  @override
  State<_ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<_ToolTile> {
  UsageState? _usage;
  bool _hasPro = PurchaseService.instance.hasPro;
  StreamSubscription<void>? _usageSub;
  StreamSubscription<EntitlementTier>? _entitleSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _usageSub = UsageLimitsService.instance.changes.listen((_) => _refresh());
    _entitleSub =
        PurchaseService.instance.entitlementChanges.listen((tier) {
      if (!mounted) return;
      setState(() => _hasPro = tier == EntitlementTier.pro);
    });
  }

  Future<void> _refresh() async {
    final usage = await UsageLimitsService.instance.stateFor(widget.toolId);
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  @override
  void dispose() {
    _usageSub?.cancel();
    _entitleSub?.cancel();
    super.dispose();
  }

  bool get _isProOnly => ToolLimits.proOnly.contains(widget.toolId);

  Future<void> _onTap() async {
    if (_hasPro) {
      _navigate();
      return;
    }

    HapticsService.instance.tap();
    if (_isProOnly) {
      final purchased = await PaywallSheet.show(
        context,
        quotaContext: widget.title,
      );
      if (purchased && mounted) _navigate();
      return;
    }

    final usage = _usage;
    if (usage != null && !usage.canUse) {
      final purchased = await PaywallSheet.show(
        context,
        quotaContext: widget.title,
      );
      if (purchased && mounted) _navigate();
      return;
    }

    _navigate();
  }

  void _navigate() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: widget.builder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    final label = _isProOnly
        ? '${widget.title}. ${widget.subtitle}. Pro only.'
        : _hasPro
            ? '${widget.title}. ${widget.subtitle}.'
            : usage == null
                ? '${widget.title}. ${widget.subtitle}.'
                : usage.canUse
                    ? '${widget.title}. ${widget.subtitle}. '
                        '${usage.remaining} free uses today.'
                    : '${widget.title}. ${widget.subtitle}. '
                        'Daily limit reached.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _onTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  _IconBubble(icon: widget.icon, locked: !_hasPro && _isProOnly),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _TileBadge(
                              hasPro: _hasPro,
                              isProOnly: _isProOnly,
                              usage: usage,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final bool locked;
  const _IconBubble({required this.icon, required this.locked});

  @override
  Widget build(BuildContext context) {
    final color = locked ? AppColors.warning : AppColors.primary;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          if (locked)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.surface,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.lock,
                  size: 9,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TileBadge extends StatelessWidget {
  final bool hasPro;
  final bool isProOnly;
  final UsageState? usage;
  const _TileBadge({
    required this.hasPro,
    required this.isProOnly,
    required this.usage,
  });

  @override
  Widget build(BuildContext context) {
    if (isProOnly) {
      return _Pill(
        label: hasPro ? 'PRO' : 'PRO',
        color: hasPro ? AppColors.success : AppColors.warning,
      );
    }
    if (hasPro) {
      // Free tiles for Pro users — no badge clutter, just clean tile.
      return const SizedBox.shrink();
    }
    if (usage == null) {
      return const SizedBox.shrink();
    }
    if (!usage!.canUse) {
      return const _Pill(label: 'USED TODAY', color: AppColors.warning);
    }
    return _Pill(
      label: '${usage!.remaining}/day',
      color: AppColors.freeBadge,
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
