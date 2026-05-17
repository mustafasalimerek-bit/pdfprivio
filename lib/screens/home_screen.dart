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
import '../widgets/recent_files_carousel.dart';
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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroes = _heroSpecs();
    return Scaffold(
      // No AppBar — the greeting + status pill below replaces the
      // "giant PDFPrivio title" that ate 1/8 of the screen. iOS HIG
      // pattern: brand lives in the launcher icon, the app surface
      // belongs to the user's content.
      body: SafeArea(
        child: MaxWidthBody(
          maxWidth: 1200,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // iPad gets a slightly roomier grid (5 cols vs 4) but the
              // structure is identical — header + status + hero + recent
              // + 4×2 (or 5×2) tool grid + "More" cell.
              final w = constraints.maxWidth;
              final gridColumns = w >= Breakpoints.iPadRegular
                  ? 6
                  : w >= Breakpoints.iPadCompact
                      ? 5
                      : 4;
              // Recent row spans the full row width — same left edge
              // as grid cell 1, same right edge as the last grid
              // cell. With 3 cards (Scan / Sign / Edit slots) and
              // the same inter-card spacing as the grid, each card
              // is wider than a single grid cell. This keeps the
              // home column-aligned edge-to-edge instead of leaving
              // a hole above the 4th grid cell.
              const horizontalPadding = 16.0;
              const gridSpacing = 12.0;
              const recentCardCount = 3;
              final available =
                  (w - horizontalPadding * 2).clamp(0, double.infinity);
              final recentCardWidth = (available -
                      gridSpacing * (recentCardCount - 1)) /
                  recentCardCount;
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                    horizontalPadding, 8, horizontalPadding, 24),
                children: [
                  const _HomeHeader(),
                  const SizedBox(height: 14),
                  const _OfflineStatusPill(),
                  const SizedBox(height: 14),
                  _HeroScanCard(onTap: () => _openScan(context)),
                  const SizedBox(height: 18),
                  RecentFilesCarousel(
                    cardWidth: recentCardWidth,
                    cardSpacing: gridSpacing,
                  ),
                  const _SectionLabel('All tools'),
                  const SizedBox(height: 10),
                  _HeroToolGrid(
                    heroes: heroes,
                    columns: gridColumns,
                    onMoreTap: () => _showMoreSheet(context),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _openScan(BuildContext context) {
    HapticsService.instance.tap();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
  }

  /// The 7 tools that earn home-screen real estate. Chosen for the
  /// lawyer/CPA wedge: OCR + Sign + Fill form + Redact = legal/tax
  /// daily ops; Merge + Compress + Split = universal PDF utility.
  /// Everything else lives one tap deeper behind "More" — same
  /// discovery hop as iOS Settings sub-pages, which Apple sees as a
  /// premium pattern rather than a friction.
  static const _heroToolIds = <String>{
    'ocr_pdf',
    'sign',
    'form_fill',
    'redact',
    'merge',
    'compress',
    'split',
  };

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

  /// Build heroes in hero-id order, plus a "More" cell at the end —
  /// what shows in the 4×2 grid on the home screen.
  List<_ToolSpec> _heroSpecs() {
    final all = _specs();
    return _heroToolIds
        .map((id) => all.firstWhere((s) => s.toolId == id))
        .toList();
  }

  void _showMoreSheet(BuildContext context) {
    HapticsService.instance.tap();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        // Pass the full catalog so the sheet can show Frequent +
        // All tools per the mockup; heroes are repeated intentionally
        // so a user who taps More can still reach any tool from there.
        return _MoreToolsSheet(specs: _specs());
      },
    );
  }
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

/// 4×2 hero grid of the 7 wedge-critical tools plus a "More" cell
/// that opens the rest in a bottom sheet. Each cell is icon + label,
/// with a tiny "PRO" or quota indicator in the corner — the heavier
/// subtitle + chevron of the full row tile gets dropped because the
/// row's purpose here is recognition, not discovery.
class _HeroToolGrid extends StatelessWidget {
  final List<_ToolSpec> heroes;
  final int columns;
  final VoidCallback onMoreTap;

  const _HeroToolGrid({
    required this.heroes,
    required this.columns,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    // heroes.length + 1 for the More cell. We size each cell square-ish
    // so on iPhone 6 wide the icons sit comfortably above their labels.
    final cells = <Widget>[
      ...heroes.map((spec) => _CompactToolTile(spec: spec)),
      _MoreTile(onTap: onMoreTap),
    ];
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Slightly taller than wide so two-line labels like
        // "Compress PDF" don't clip on narrow iPhone width.
        childAspectRatio: 0.82,
      ),
      itemCount: cells.length,
      itemBuilder: (_, i) => cells[i],
    );
  }
}

/// Compact grid-cell variant of the tool tile. Pulls Pro / usage
/// state from the same services as the full row, but renders only
/// icon + label + a minimal corner indicator. Pure-tile UI; the
/// long-form description lives in the More sheet (_ToolTile) for
/// users who tap through.
class _CompactToolTile extends StatefulWidget {
  final _ToolSpec spec;
  const _CompactToolTile({required this.spec});

  @override
  State<_CompactToolTile> createState() => _CompactToolTileState();
}

class _CompactToolTileState extends State<_CompactToolTile> {
  UsageState? _usage;
  bool _hasPro = PurchaseService.instance.hasPro;
  StreamSubscription<void>? _usageSub;
  StreamSubscription<EntitlementTier>? _entitleSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _usageSub =
        UsageLimitsService.instance.changes.listen((_) => _refresh());
    _entitleSub =
        PurchaseService.instance.entitlementChanges.listen((tier) {
      if (!mounted) return;
      setState(() => _hasPro = tier == EntitlementTier.pro);
    });
  }

  Future<void> _refresh() async {
    final usage =
        await UsageLimitsService.instance.stateFor(widget.spec.toolId);
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  @override
  void dispose() {
    _usageSub?.cancel();
    _entitleSub?.cancel();
    super.dispose();
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
    return _TileShell(
      icon: widget.spec.icon,
      label: widget.spec.displayGridLabel,
      onTap: _onTap,
      showProBadge: _isProOnly && !_hasPro,
      semanticsLabel: '${widget.spec.title}. ${widget.spec.subtitle}.',
    );
  }
}

/// 8th cell of the home grid — opens the bottom sheet with every
/// tool not already in the hero set. Renders through the exact same
/// shell as every other tile so the visual is guaranteed identical.
class _MoreTile extends StatelessWidget {
  final VoidCallback onTap;
  const _MoreTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      icon: Icons.apps_outlined,
      label: 'More',
      onTap: onTap,
      semanticsLabel: 'More tools — opens the full list',
    );
  }
}

/// One shared shell so every grid cell renders identically — same
/// 64×64 iconTint container, same icon size, same gap, same label
/// text style, same InkWell radius, same Stack-clip-none for the
/// optional corner PRO badge. Drives _CompactToolTile and _MoreTile.
/// If they diverged in any per-widget detail (Stack vs raw Column,
/// material vs no material), the More cell would visually break
/// rank with the rest. This forces parity.
class _TileShell extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showProBadge;
  final String semanticsLabel;

  const _TileShell({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.semanticsLabel,
    this.showProBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.iconTint,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            if (showProBadge)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.4,
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

/// Time-of-day greeting + small day-of-week subtitle. Replaces the
/// "giant PDFPrivio" title that ate the top of the screen. Brand
/// stays on the launcher icon; this surface belongs to the user.
///
/// Time bands (per design spec):
///   * 5-11  → Good morning
///   * 12-17 → Good afternoon
///   * 18-21 → Good evening
///   * 22-4  → Burning the midnight oil
///
/// If the user has set a display name (Settings → Personalization),
/// the morning/afternoon/evening greetings append ", \<Name\>". The
/// midnight-oil line is an idiom and stays unpersonalised — adding
/// a name to it reads awkward.
class _HomeHeader extends StatefulWidget {
  const _HomeHeader();

  @override
  State<_HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<_HomeHeader> {
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
      base = 'Good morning';
    } else if (hour >= 12 && hour < 18) {
      base = 'Good afternoon';
    } else if (hour >= 18 && hour < 22) {
      base = 'Good evening';
    } else {
      // Idiomatic — doesn't take a comma-name appendage.
      return 'Burning the midnight oil';
    }
    if (name == null || name.isEmpty) return base;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$day · $time',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _greeting(hour, _name),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

/// Always-visible "this app runs offline" pill. This is the single
/// most important brand signal — repeat it on every home open so the
/// privacy promise stays top of mind. Also reads beautifully in App
/// Store screenshots, which is half the reason it lives here.
class _OfflineStatusPill extends StatelessWidget {
  const _OfflineStatusPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Working offline — nothing leaves your iPhone',
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

/// Big teal CTA at the top of the home screen — the hero "action this
/// app exists for." Scan is the most likely first action and the most
/// distinctive feature, so it gets the prime visual real estate
/// instead of being one tile among 23.
class _HeroScanCard extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroScanCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick action',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.78),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Scan a document',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Camera → auto-edge → searchable PDF',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Start scanning',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
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
    if (usage == null || usage!.unlimited) {
      // No usage state yet, or tool is free-unlimited (Bookmarks,
      // Summarize, Live Text view) — show no badge.
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

// =============================================================================
// More tools sheet — opens from the 8th grid cell
// =============================================================================

/// Bottom sheet that lists every tool not promoted to the home
/// grid. Layout borrowed from the App-Store-editorial "All tools"
/// pattern: drag handle + title + live search + one rounded card
/// holding compact icon-title-badge-chevron rows separated by hair
/// dividers. Replaces the older sheet that just dumped full-row
/// _ToolTile widgets in a ListView.
class _MoreToolsSheet extends StatefulWidget {
  final List<_ToolSpec> specs;
  const _MoreToolsSheet({required this.specs});

  @override
  State<_MoreToolsSheet> createState() => _MoreToolsSheetState();
}

class _MoreToolsSheetState extends State<_MoreToolsSheet> {
  String _query = '';
  Map<String, int> _lifetime = const {};

  /// Fallback ordering for users with zero history — these four are
  /// the highest-leverage tools per the wedge, so they make the best
  /// "first impression" set in the Frequent panel.
  static const List<String> _frequentSeed = [
    'scan_to_pdf',
    'sign',
    'ocr_pdf',
    'image_to_pdf',
  ];

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final ids = widget.specs.map((s) => s.toolId).toList();
    final counts = await UsageLimitsService.instance.lifetimeCountsFor(ids);
    if (!mounted) return;
    setState(() => _lifetime = counts);
  }

  List<_ToolSpec> _frequentSpecs() {
    final used = widget.specs
        .where((s) => (_lifetime[s.toolId] ?? 0) > 0)
        .toList()
      ..sort((a, b) =>
          (_lifetime[b.toolId] ?? 0).compareTo(_lifetime[a.toolId] ?? 0));
    if (used.length >= 4) return used.take(4).toList();
    // Backfill from the seed list, skipping anything already chosen
    // and anything missing from the catalog.
    final chosen = used.map((s) => s.toolId).toSet();
    final byId = {for (final s in widget.specs) s.toolId: s};
    for (final id in _frequentSeed) {
      if (used.length == 4) break;
      if (chosen.contains(id)) continue;
      final spec = byId[id];
      if (spec == null) continue;
      used.add(spec);
      chosen.add(id);
    }
    return used.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final filtered =
        searching ? widget.specs.where(_matches).toList() : widget.specs;
    final frequent = searching ? const <_ToolSpec>[] : _frequentSpecs();
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: _MoreSheetSearchBar(
                value: _query,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'No tool matches that.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        if (frequent.isNotEmpty) ...[
                          const _SectionHeader('Frequent'),
                          for (final spec in frequent) ...[
                            _FrequentCard(spec: spec),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 8),
                        ],
                        const _SectionHeader('All tools'),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < filtered.length; i++) ...[
                                _MoreSheetRow(spec: filtered[i]),
                                if (i != filtered.length - 1)
                                  Padding(
                                    padding: const EdgeInsets
                                        .symmetric(horizontal: 14),
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
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  bool _matches(_ToolSpec spec) {
    final q = _query.trim().toLowerCase();
    return spec.title.toLowerCase().contains(q) ||
        spec.subtitle.toLowerCase().contains(q) ||
        spec.toolId.toLowerCase().contains(q);
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Frequent-section card: same data as a row, but its own bordered
/// surface so the four cards stack as discrete tap targets per the
/// mockup. Reuses [_MoreSheetRow] state-handling indirectly via the
/// stateful _FrequentCardState below.
class _FrequentCard extends StatefulWidget {
  final _ToolSpec spec;
  const _FrequentCard({required this.spec});

  @override
  State<_FrequentCard> createState() => _FrequentCardState();
}

class _FrequentCardState extends State<_FrequentCard> {
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
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: widget.spec.builder),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.iconTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.spec.icon,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.spec.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _MoreSheetBadge(
                          isProOnly: _isProOnly,
                          hasPro: _hasPro,
                          usage: _usage,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.spec.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreSheetSearchBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _MoreSheetSearchBar({
    required this.value,
    required this.onChanged,
  });

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
          const Icon(
            Icons.search,
            size: 18,
            color: AppColors.textSecondary,
          ),
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
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

class _MoreSheetRow extends StatefulWidget {
  final _ToolSpec spec;
  const _MoreSheetRow({required this.spec});

  @override
  State<_MoreSheetRow> createState() => _MoreSheetRowState();
}

class _MoreSheetRowState extends State<_MoreSheetRow> {
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
    // Pop the sheet so the tool screen opens on top of the home
    // (not on top of the sheet).
    Navigator.of(context).pop();
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
            _MoreSheetBadge(
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

class _MoreSheetBadge extends StatelessWidget {
  final bool isProOnly;
  final bool hasPro;
  final UsageState? usage;
  const _MoreSheetBadge({
    required this.isProOnly,
    required this.hasPro,
    required this.usage,
  });

  Widget _pill(String label, Color color) {
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

  @override
  Widget build(BuildContext context) {
    if (isProOnly && !hasPro) return _pill('Pro', AppColors.warning);
    if (hasPro) return const SizedBox.shrink();
    if (usage == null || usage!.unlimited) {
      return const SizedBox.shrink();
    }
    if (!usage!.canUse) {
      return _pill('Used today', AppColors.warning);
    }
    return _pill('${usage!.remaining}/day', AppColors.success);
  }
}
