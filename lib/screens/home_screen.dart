import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/colors.dart';
import '../core/utils/responsive.dart';
import '../data/services/display_name_service.dart';
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
import 'receipts/receipt_capture_screen.dart';
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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _query = '';

  /// 4 tools that get the "Frequent" rich-card treatment. Default to
  /// the wedge audience's most-used first action surface — Scan +
  /// Sign + OCR + Image-to-PDF. Future: learn this from real usage
  /// data via UsageLimitsService counters.
  static const _frequentToolIds = <String>{
    'scan_to_pdf',
    'sign',
    'ocr_pdf',
    'image_to_pdf',
  };

  @override
  Widget build(BuildContext context) {
    final allSpecs = _specs();
    final q = _query.trim().toLowerCase();
    final frequent = _frequentToolIds
        .map((id) => allSpecs.firstWhere((s) => s.toolId == id))
        .where((s) => q.isEmpty || _matches(s, q))
        .toList();
    final allTools = allSpecs
        .where((s) => !_frequentToolIds.contains(s.toolId))
        .where((s) => q.isEmpty || _matches(s, q))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      // No AppBar — header card below extends edge-to-edge and
      // takes over the top surface.
      body: MaxWidthBody(
        maxWidth: 1200,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const _HomeHeaderCard(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: _SearchBar(
                value: _query,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (q.isNotEmpty && frequent.isEmpty && allTools.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 28, 16, 28),
                child: Center(
                  child: Text(
                    'No tool matches that.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            if (frequent.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 16, 10),
                child: _SectionLabel(
                    q.isEmpty ? 'Frequent' : 'Matching frequent'),
              ),
              for (final spec in frequent)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _FrequentTile(spec: spec),
                ),
            ],
            if (allTools.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 16, 10),
                child: _SectionLabel('All tools'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: _AllToolsListCard(specs: allTools),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _matches(_ToolSpec spec, String q) {
    return spec.title.toLowerCase().contains(q) ||
        spec.subtitle.toLowerCase().contains(q) ||
        spec.toolId.toLowerCase().contains(q);
  }

  List<_ToolSpec> _specs() => const [
        _ToolSpec(
          icon: Icons.document_scanner_outlined,
          title: 'Scan to PDF',
          subtitle: 'Camera → auto-edge → multi-page → one PDF',
          toolId: 'scan_to_pdf',
          builder: _buildScanScreen,
        ),
        _ToolSpec(
          icon: Icons.find_in_page_outlined,
          title: 'OCR PDF',
          subtitle: 'Scanned PDF → searchable text · on-device',
          toolId: 'ocr_pdf',
          builder: _buildOcrScreen,
          gridLabel: 'OCR',
        ),
        _ToolSpec(
          icon: Icons.library_books_outlined,
          title: 'Merge PDFs',
          subtitle: 'Combine multiple PDFs into one',
          toolId: 'merge',
          builder: _buildMergeScreen,
          gridLabel: 'Merge',
        ),
        _ToolSpec(
          icon: Icons.compress_outlined,
          title: 'Compress PDF',
          subtitle: 'Shrink for email — keep quality',
          toolId: 'compress',
          builder: _buildCompressScreen,
          gridLabel: 'Compress',
        ),
        _ToolSpec(
          icon: Icons.content_cut_outlined,
          title: 'Split PDF',
          subtitle: 'Extract range, every N pages, or N parts',
          toolId: 'split',
          builder: _buildSplitScreen,
          gridLabel: 'Split',
        ),
        _ToolSpec(
          icon: Icons.image_outlined,
          title: 'Image to PDF',
          subtitle: 'Photos, receipts, screenshots → one PDF',
          toolId: 'image_to_pdf',
          builder: _buildImageToPdfScreen,
        ),
        _ToolSpec(
          icon: Icons.rotate_right_outlined,
          title: 'Rotate pages',
          subtitle: 'Fix sideways scans or flip a PDF',
          toolId: 'rotate',
          builder: _buildRotateScreen,
        ),
        _ToolSpec(
          icon: Icons.delete_sweep_outlined,
          title: 'Delete pages',
          subtitle: 'Pick the pages to drop, keep the rest',
          toolId: 'delete_pages',
          builder: _buildDeletePagesScreen,
        ),
        _ToolSpec(
          icon: Icons.draw_outlined,
          title: 'Sign PDF',
          subtitle: 'Draw, place, save — audit-trail included',
          toolId: 'sign',
          builder: _buildSignScreen,
          gridLabel: 'Sign',
        ),
        _ToolSpec(
          icon: Icons.edit_document,
          title: 'Fill form',
          subtitle: 'IRS, USCIS, court forms — flatten on save',
          toolId: 'form_fill',
          builder: _buildFormFillScreen,
        ),
        _ToolSpec(
          icon: Icons.format_list_numbered,
          title: 'Page numbers',
          subtitle: 'Page 1 of 20 — pick format and position',
          toolId: 'page_numbers',
          builder: _buildPageNumbersScreen,
        ),
        _ToolSpec(
          icon: Icons.tag,
          title: 'Bates numbering',
          subtitle: 'Sequential page IDs — legal discovery standard',
          toolId: 'bates',
          builder: _buildBatesScreen,
        ),
        _ToolSpec(
          icon: Icons.lock_outline,
          title: 'Password protect',
          subtitle: 'AES-256 encrypt or unlock — pick auto-detects',
          toolId: 'password',
          builder: _buildPasswordScreen,
        ),
        _ToolSpec(
          icon: Icons.water_drop_outlined,
          title: 'Watermark',
          subtitle: 'CONFIDENTIAL / DRAFT — diagonal, center, or tile',
          toolId: 'watermark',
          builder: _buildWatermarkScreen,
        ),
        _ToolSpec(
          icon: Icons.text_snippet_outlined,
          title: 'Extract text',
          subtitle: 'Pull text out — born-digital PDFs only',
          toolId: 'extract_text',
          builder: _buildExtractTextScreen,
        ),
        _ToolSpec(
          icon: Icons.compare_arrows,
          title: 'Compare PDFs',
          subtitle: 'Redline two versions — added & removed text',
          toolId: 'compare',
          builder: _buildCompareScreen,
        ),
        _ToolSpec(
          icon: Icons.menu_book_outlined,
          title: 'Bookmarks / TOC',
          subtitle: 'Jump to a chapter in one tap — long briefs, depositions',
          toolId: 'bookmarks',
          builder: _buildBookmarksScreen,
        ),
        _ToolSpec(
          icon: Icons.auto_awesome,
          title: 'Summarize PDF',
          subtitle: 'On-device Apple Intelligence summary — never uploaded',
          toolId: 'summarize',
          builder: _buildSummarizeScreen,
        ),
        _ToolSpec(
          icon: Icons.center_focus_strong_outlined,
          title: 'Live Text view',
          subtitle: 'Select text from any PDF page — Apple Live Text + Markup',
          toolId: 'quick_look',
          builder: _buildQuickLookScreen,
        ),
        _ToolSpec(
          icon: Icons.dynamic_feed_outlined,
          title: 'Batch operations',
          subtitle: 'Compress / Watermark / Rotate many PDFs at once',
          toolId: 'batch',
          builder: _buildBatchScreen,
        ),
        _ToolSpec(
          icon: Icons.receipt_long_outlined,
          title: 'Receipt scanner',
          subtitle: 'Scan → auto-extract date/vendor/total → CSV for QuickBooks',
          toolId: 'receipt',
          builder: _buildReceiptScreen,
        ),
        _ToolSpec(
          icon: Icons.shield_outlined,
          title: 'Find sensitive data',
          subtitle: 'Auto-detect SSN, EIN, credit cards, emails, phone numbers',
          toolId: 'pii_scan',
          builder: _buildPiiScanScreen,
        ),
        _ToolSpec(
          icon: Icons.format_color_fill,
          title: 'Redact',
          subtitle: 'Search and black out names, account numbers, etc.',
          toolId: 'redact',
          builder: _buildRedactScreen,
        ),
      ];

}

// Static screen builders — needed so _ToolSpec instances can be
// declared `const`. Each is a one-liner that wraps the screen
// constructor.
Widget _buildScanScreen(BuildContext _) => const ScanScreen();
Widget _buildOcrScreen(BuildContext _) => const OcrPdfScreen();
Widget _buildMergeScreen(BuildContext _) => const MergeScreen();
Widget _buildCompressScreen(BuildContext _) => const CompressScreen();
Widget _buildSplitScreen(BuildContext _) => const SplitScreen();
Widget _buildImageToPdfScreen(BuildContext _) => const ImageToPdfScreen();
Widget _buildRotateScreen(BuildContext _) => const RotateScreen();
Widget _buildDeletePagesScreen(BuildContext _) => const DeletePagesScreen();
Widget _buildSignScreen(BuildContext _) => const SignScreen();
Widget _buildFormFillScreen(BuildContext _) => const FormFillScreen();
Widget _buildPageNumbersScreen(BuildContext _) => const PageNumbersScreen();
Widget _buildBatesScreen(BuildContext _) => const BatesScreen();
Widget _buildPasswordScreen(BuildContext _) => const PasswordScreen();
Widget _buildWatermarkScreen(BuildContext _) => const WatermarkScreen();
Widget _buildExtractTextScreen(BuildContext _) => const ExtractTextScreen();
Widget _buildCompareScreen(BuildContext _) => const CompareScreen();
Widget _buildBookmarksScreen(BuildContext _) => const BookmarksScreen();
Widget _buildSummarizeScreen(BuildContext _) => const SummarizeScreen();
Widget _buildQuickLookScreen(BuildContext _) =>
    const QuickLookLauncherScreen();
Widget _buildBatchScreen(BuildContext _) => const BatchScreen();
Widget _buildReceiptScreen(BuildContext _) => const ReceiptCaptureScreen();
Widget _buildPiiScanScreen(BuildContext _) => const PiiScanScreen();
Widget _buildRedactScreen(BuildContext _) => const RedactScreen();

/// Immutable spec for a tool entry. Rendered either as a row
/// (_ToolTile, full-width with subtitle + badges) or as a square
/// grid cell (_CompactToolTile, icon + label only).
class _ToolSpec {
  final IconData icon;
  final String title;
  final String subtitle;
  final String toolId;
  final WidgetBuilder builder;
  /// Shorter label shown in the home-screen grid cell. Grid cells
  /// are ~80 dp wide and a wrapped "Compress PDF" eats the icon
  /// area; we strip the "PDF" / "PDFs" suffix that everyone reading
  /// "Sign" / "Merge" / "Compress" already understands from context.
  final String? gridLabel;
  const _ToolSpec({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.toolId,
    required this.builder,
    this.gridLabel,
  });

  String get displayGridLabel => gridLabel ?? title;
}


// =============================================================================
// Section label
// =============================================================================

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppColors.textSecondary,
        letterSpacing: 0.2,
      ),
    );
  }
}

// =============================================================================
// Header card — greyed-cream sheet with date + greeting + offline pill
// =============================================================================

/// Full-width header at the top of the home screen. Edge-to-edge
/// background in [AppColors.headerCard] (one shade darker than the
/// scaffold cream), no rounded corners — reads as a sheet that
/// dropped down from the status bar. Holds the date strip, the
/// "Hi, \<name\>" greeting, and a compact Offline pill.
class _HomeHeaderCard extends StatefulWidget {
  const _HomeHeaderCard();

  @override
  State<_HomeHeaderCard> createState() => _HomeHeaderCardState();
}

class _HomeHeaderCardState extends State<_HomeHeaderCard> {
  String? _name;

  @override
  void initState() {
    super.initState();
    _loadName();
    DisplayNameService.instance.changes.listen((_) => _loadName());
  }

  Future<void> _loadName() async {
    final name = await DisplayNameService.instance.get();
    if (!mounted) return;
    setState(() => _name = name);
  }

  String _greeting(int hour, String? name) {
    String base;
    if (hour >= 5 && hour < 12) {
      base = 'Hi';
    } else if (hour >= 12 && hour < 18) {
      base = 'Good afternoon';
    } else if (hour >= 18 && hour < 22) {
      base = 'Good evening';
    } else {
      return 'Burning the midnight oil';
    }
    if (name == null || name.isEmpty) {
      // Morning greeting "Hi" stays terse without a comma form.
      if (base == 'Hi') return 'Hi';
      return base;
    }
    return '$base, $name';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour;
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final day = days[now.weekday - 1];
    final time =
        '${hour % 12 == 0 ? 12 : hour % 12}:${now.minute.toString().padLeft(2, '0')} '
        '${hour < 12 ? 'AM' : 'PM'}';

    return Container(
      width: double.infinity,
      color: AppColors.headerCard,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 14,
        20,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$day · $time',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _greeting(hour, _name),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 12),
          const _OfflineMiniPill(),
        ],
      ),
    );
  }
}

class _OfflineMiniPill extends StatelessWidget {
  const _OfflineMiniPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            'Offline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Search bar — filters tools live as user types
// =============================================================================

class _SearchBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search tools',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              onChanged: onChanged,
            ),
          ),
          // Decorative "Pro" pill — visual cue that some tools in the
          // filtered list are Pro-locked. Not a filter button; tap
          // does nothing today. Lets the user know the search covers
          // the whole Pro surface.
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.iconTint,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: AppColors.primary,
                ),
                SizedBox(width: 4),
                Text(
                  'Pro',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
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

// =============================================================================
// Frequent tile — full-width rich card with icon + title + badge + subtitle
// =============================================================================

class _FrequentTile extends StatefulWidget {
  final _ToolSpec spec;
  const _FrequentTile({required this.spec});

  @override
  State<_FrequentTile> createState() => _FrequentTileState();
}

class _FrequentTileState extends State<_FrequentTile> {
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

  @override
  void dispose() {
    _usageSub?.cancel();
    _entitleSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final usage =
        await UsageLimitsService.instance.stateFor(widget.spec.toolId);
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  bool get _isProOnly =>
      ToolLimits.proOnly.contains(widget.spec.toolId);

  Future<void> _onTap() async {
    HapticsService.instance.tap();
    if (_hasPro) {
      _navigate();
      return;
    }
    if (_isProOnly) {
      final purchased = await PaywallSheet.show(
        context,
        quotaContext: widget.spec.title,
      );
      if (purchased && mounted) _navigate();
      return;
    }
    final usage = _usage;
    if (usage != null && !usage.canUse) {
      final purchased = await PaywallSheet.show(
        context,
        quotaContext: widget.spec.title,
      );
      if (purchased && mounted) _navigate();
      return;
    }
    _navigate();
  }

  void _navigate() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: widget.spec.builder),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.iconTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  widget.spec.icon,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.spec.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ToolBadge(
                          isProOnly: _isProOnly,
                          hasPro: _hasPro,
                          usage: _usage,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.spec.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// All tools list — compact rows in a divided card
// =============================================================================

/// White rounded container that holds the compact "All tools" rows
/// with a thin divider between each. The container shape replaces
/// the per-row borders of the older _ToolTile design — cleaner read
/// when 19 rows stack vertically.
class _AllToolsListCard extends StatelessWidget {
  final List<_ToolSpec> specs;
  const _AllToolsListCard({required this.specs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < specs.length; i++) ...[
            _AllToolsRow(spec: specs[i]),
            if (i != specs.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.border.withValues(alpha: 0.6),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AllToolsRow extends StatefulWidget {
  final _ToolSpec spec;
  const _AllToolsRow({required this.spec});

  @override
  State<_AllToolsRow> createState() => _AllToolsRowState();
}

class _AllToolsRowState extends State<_AllToolsRow> {
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

  @override
  void dispose() {
    _usageSub?.cancel();
    _entitleSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final usage =
        await UsageLimitsService.instance.stateFor(widget.spec.toolId);
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  bool get _isProOnly =>
      ToolLimits.proOnly.contains(widget.spec.toolId);

  Future<void> _onTap() async {
    HapticsService.instance.tap();
    if (_hasPro) {
      _navigate();
      return;
    }
    if (_isProOnly) {
      final purchased = await PaywallSheet.show(
        context,
        quotaContext: widget.spec.title,
      );
      if (purchased && mounted) _navigate();
      return;
    }
    final usage = _usage;
    if (usage != null && !usage.canUse) {
      final purchased = await PaywallSheet.show(
        context,
        quotaContext: widget.spec.title,
      );
      if (purchased && mounted) _navigate();
      return;
    }
    _navigate();
  }

  void _navigate() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: widget.spec.builder),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.iconTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                widget.spec.icon,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.spec.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _ToolBadge(
              isProOnly: _isProOnly,
              hasPro: _hasPro,
              usage: _usage,
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Pro / quota badge — shared between Frequent and All-tools rows
// =============================================================================

class _ToolBadge extends StatelessWidget {
  final bool isProOnly;
  final bool hasPro;
  final UsageState? usage;
  const _ToolBadge({
    required this.isProOnly,
    required this.hasPro,
    required this.usage,
  });

  @override
  Widget build(BuildContext context) {
    if (isProOnly && !hasPro) {
      return _BadgePill(label: 'Pro', color: AppColors.warning);
    }
    if (hasPro) {
      return const SizedBox.shrink();
    }
    if (usage == null || usage!.unlimited) {
      return const SizedBox.shrink();
    }
    if (!usage!.canUse) {
      return _BadgePill(
        label: 'Used today',
        color: AppColors.warning,
      );
    }
    return _BadgePill(
      label: '${usage!.remaining}/day',
      color: AppColors.success,
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String label;
  final Color color;
  const _BadgePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
