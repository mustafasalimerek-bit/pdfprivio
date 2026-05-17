import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/consent_service.dart';
import '../../data/services/display_name_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/promo_code_service.dart';
import '../../data/services/purchase_service.dart';
import '../../data/services/widget_data_service.dart';
import '../../widgets/redeem_promo_dialog.dart';
import '../audit_log/audit_log_screen.dart';
import '../receipts/expense_ledger_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PackageInfo? _info;
  bool _promoUsed = false;
  bool _widgetShowsNames = true;
  String? _displayName;
  int _auditCount = 0;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    _loadPromoState();
    _loadWidgetPref();
    _loadDisplayName();
    _loadAuditCount();
  }

  Future<void> _loadAuditCount() async {
    final count = await AuditService.instance.entryCount;
    if (mounted) setState(() => _auditCount = count);
  }

  Future<void> _openAppearance() async {
    HapticsService.instance.tap();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Appearance'),
        content: const Text(
          "PDFPrivio currently matches your iPhone's system "
          'appearance — light or dark. A per-app override (always '
          'light / always dark) is coming in v1.1.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  String _proPlanLabel() {
    if (!PurchaseService.instance.hasPro) return 'Free tier';
    final sku = PurchaseService.instance.activeSku;
    switch (sku) {
      case ProSku.monthly:
        return 'Pro · Monthly';
      case ProSku.yearly:
        return 'Pro · Yearly';
      case ProSku.lifetime:
        return 'Pro · Lifetime';
      case null:
        // Promo or sandbox edge case — still Pro, just no SKU info.
        return 'Pro · active';
    }
  }

  String _proPlanSubtitle() {
    if (!PurchaseService.instance.hasPro) {
      return 'Tap to see pricing and unlock everything';
    }
    final sku = PurchaseService.instance.activeSku;
    if (sku == ProSku.lifetime) return 'One-time purchase · no renewal';
    return 'Manages in App Store · Apple ID';
  }

  Future<void> _loadDisplayName() async {
    final name = await DisplayNameService.instance.get();
    if (mounted) setState(() => _displayName = name);
  }

  Future<void> _editDisplayName() async {
    HapticsService.instance.tap();
    final controller = TextEditingController(text: _displayName ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Used only to personalise the home-screen greeting. '
              'Stays on this device, never uploaded, never logged.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 24,
              decoration: const InputDecoration(
                hintText: 'e.g. Mustafa',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          if (_displayName != null && _displayName!.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text(
                'Clear',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelled
    final trimmed = result.trim();
    await DisplayNameService.instance
        .set(trimmed.isEmpty ? null : trimmed);
    if (mounted) {
      setState(() => _displayName = trimmed.isEmpty ? null : trimmed);
    }
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _info = info);
  }

  Future<void> _loadPromoState() async {
    final used = await PromoCodeService.instance.hasAnyRedemption();
    if (mounted) setState(() => _promoUsed = used);
  }

  Future<void> _loadWidgetPref() async {
    final show = await WidgetDataService.instance.showFileNames();
    if (mounted) setState(() => _widgetShowsNames = show);
  }

  Future<void> _toggleWidgetNames() async {
    HapticsService.instance.tap();
    final next = !_widgetShowsNames;
    await WidgetDataService.instance.setShowFileNames(next);
    if (!mounted) return;
    setState(() => _widgetShowsNames = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Home Screen widget will show file names.'
              : 'Home Screen widget will hide file names. '
                  'Tool labels still show.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _open(String url) async {
    HapticsService.instance.tap();
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $url'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Subscription management deep link. iOS opens the App Store
  /// directly when this resolves; on simulator / signed-out devices
  /// it doesn't, so fall back to a dialog with the URL the user can
  /// copy + open manually.
  Future<void> _openSubscriptions() async {
    HapticsService.instance.tap();
    const url = 'https://apps.apple.com/account/subscriptions';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manage subscription'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open Settings → Apple ID → Subscriptions on your '
              'iPhone, or visit:',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 10),
            SelectableText(
              'apps.apple.com/account/subscriptions',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: url));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Copy link'),
          ),
        ],
      ),
    );
  }

  /// Email-the-developer link. iOS Mail / Outlook handle mailto if
  /// configured; if not, fall back to a copyable address dialog so
  /// the user can still get in touch.
  Future<void> _emailSupport() async {
    HapticsService.instance.tap();
    const email = 'mustafasalimerek@gmail.com';
    final uri = Uri.parse('mailto:$email');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contact support'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "No mail app set up. Copy the address and send a "
              'message from your usual email:',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 10),
            SelectableText(
              email,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: email));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Copy address'),
          ),
        ],
      ),
    );
  }

  Future<void> _resurfaceConsent() async {
    HapticsService.instance.tap();
    await ConsentService.instance.resurfaceConsentForm();
    // The UMP SDK is silent if the consent form isn't required for the
    // current region / state — the user taps and sees nothing. Always
    // surface a follow-up so the tap doesn't feel broken.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Consent preferences refreshed. If a form was needed, it '
          "just showed; otherwise you're already in sync.",
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _restorePurchases() async {
    HapticsService.instance.tap();
    await PurchaseService.instance.restorePurchases();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          PurchaseService.instance.hasPro
              ? 'Purchases restored — Pro is active.'
              : 'No previous purchase found for this Apple ID.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openRedeemDialog() async {
    HapticsService.instance.tap();
    await RedeemPromoDialog.show(context);
    await _loadPromoState();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      backgroundColor: AppColors.background,
      // No AppBar — title is inline below.
      body: SafeArea(
        child: MaxWidthBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 8, 0, 18),
                child: Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const _PrivacyHero(),
              const SizedBox(height: 24),

              // ACCOUNT -----------------------------------------------------
              const _SectionLabel('Account'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.auto_awesome,
                    title: _proPlanLabel(),
                    subtitle: _proPlanSubtitle(),
                    trailing: PurchaseService.instance.hasPro
                        ? const _TextLink('Manage')
                        : null,
                    onTap: _openSubscriptions,
                  ),
                  _SettingsRow(
                    icon: Icons.restart_alt_outlined,
                    title: 'Restore purchases',
                    subtitle: 'Recover a previous purchase on this Apple ID',
                    onTap: _restorePurchases,
                  ),
                  _buildPromoRow(),
                  if (kDebugMode)
                    _SettingsRow(
                      icon: Icons.bug_report_outlined,
                      title: PurchaseService.instance.hasPro
                          ? 'DEBUG: turn Pro OFF'
                          : 'DEBUG: turn Pro ON',
                      subtitle: 'Debug builds only — bypasses StoreKit',
                      onTap: () async {
                        HapticsService.instance.tap();
                        await PurchaseService.instance.setProForTesting(
                          !PurchaseService.instance.hasPro,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  if (kDebugMode &&
                      (PromoCodeService.instance.hasActivePromo ||
                          _promoUsed))
                    _SettingsRow(
                      icon: Icons.delete_sweep_outlined,
                      title: 'DEBUG: clear promo redemptions',
                      subtitle: 'Wipe redemption history — debug only',
                      onTap: () async {
                        HapticsService.instance.tap();
                        await PromoCodeService.instance.clearForTesting();
                        await _loadPromoState();
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // PERSONALIZATION --------------------------------------------
              const _SectionLabel('Personalization'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.person_outline,
                    title: 'Display name',
                    subtitle: 'For your home screen greeting',
                    trailing: _displayName == null || _displayName!.isEmpty
                        ? const _TrailingValue('Not set')
                        : _TrailingValue(_displayName!),
                    onTap: _editDisplayName,
                  ),
                  _SettingsRow(
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                    subtitle: 'Match system',
                    onTap: _openAppearance,
                  ),
                  _SettingsRow(
                    icon: Icons.widgets_outlined,
                    title: 'Widget privacy',
                    subtitle: _widgetShowsNames
                        ? 'Show file names on home screen'
                        : 'Hide file names on home screen',
                    trailing: Switch.adaptive(
                      value: _widgetShowsNames,
                      onChanged: (_) => _toggleWidgetNames(),
                      activeThumbColor: AppColors.primary,
                    ),
                    onTap: _toggleWidgetNames,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // PRIVACY & DATA ---------------------------------------------
              const _SectionLabel('Privacy & data'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.receipt_long_outlined,
                    title: 'Audit log',
                    subtitle: _auditCount == 0
                        ? 'No events yet · export or clear'
                        : '$_auditCount event${_auditCount == 1 ? '' : 's'} · export or clear',
                    onTap: () {
                      HapticsService.instance.tap();
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => const AuditLogScreen(),
                            ),
                          )
                          .then((_) => _loadAuditCount());
                    },
                  ),
                  _SettingsRow(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Expense ledger',
                    subtitle: 'Receipts → QuickBooks-friendly CSV',
                    onTap: () {
                      HapticsService.instance.tap();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ExpenseLedgerScreen(),
                        ),
                      );
                    },
                  ),
                  _SettingsRow(
                    icon: Icons.shield_outlined,
                    title: 'Data preferences',
                    subtitle: 'Analytics, ads, California opt-out',
                    onTap: _resurfaceConsent,
                  ),
                  _SettingsRow(
                    icon: Icons.description_outlined,
                    title: 'Privacy Policy',
                    subtitle: 'What we collect — and what we never collect',
                    onTap: () => _open(
                      'https://mustafasalimerek-bit.github.io/pdfprivio/privacy/',
                    ),
                  ),
                  _SettingsRow(
                    icon: Icons.gavel_outlined,
                    title: 'Terms of Service',
                    subtitle: 'The rules of using PDFPrivio',
                    onTap: () => _open(
                      'https://mustafasalimerek-bit.github.io/pdfprivio/terms/',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // iOS INTEGRATIONS -------------------------------------------
              const _SectionLabel('iOS integrations'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.bolt_outlined,
                    title: 'Action Button',
                    subtitle: 'Bind Scan to PDF on iPhone 15 Pro+',
                    onTap: _showActionButtonDialog,
                  ),
                  _SettingsRow(
                    icon: Icons.tune_outlined,
                    title: 'Control Center',
                    subtitle: 'iOS 18+ Lock Screen quick scan',
                    onTap: _showControlCenterDialog,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ABOUT ------------------------------------------------------
              const _SectionLabel('About'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.info_outline,
                    title: 'About PDFPrivio',
                    subtitle: 'On-device PDF toolkit by Erek Studio',
                    onTap: () => _open(
                      'https://mustafasalimerek-bit.github.io/pdfprivio/',
                    ),
                  ),
                  _SettingsRow(
                    icon: Icons.mail_outline,
                    title: 'Contact support',
                    subtitle: 'Questions, bugs, feature requests',
                    onTap: _emailSupport,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Disclaimer + version footer (kept terse) -------------------
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'PDFPrivio is a tool, not legal, medical, financial, '
                  'or tax advice. Outputs are aids — not substitutes for '
                  'human review.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  info == null
                      ? ''
                      : 'PDFPrivio ${info.version} (${info.buildNumber})',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Made by Erek Studio · Istanbul',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromoRow() {
    final timeLeft = PromoCodeService.instance.timeLeft;
    final hasActive = timeLeft != null;
    final daysLeft = hasActive ? timeLeft.inDays : 0;

    final String title;
    final String subtitle;
    if (hasActive) {
      title = 'Promo · $daysLeft ${daysLeft == 1 ? "day" : "days"} left';
      subtitle = 'Drops back to free tier when it ends';
    } else if (_promoUsed) {
      title = 'Promo used';
      subtitle = 'Upgrade to Pro to unlock everything again';
    } else {
      title = 'Redeem a promo code';
      subtitle = '14 days of Pro, no purchase';
    }
    return _SettingsRow(
      icon: Icons.card_giftcard_outlined,
      title: title,
      subtitle: subtitle,
      onTap: _openRedeemDialog,
    );
  }

  void _showActionButtonDialog() {
    HapticsService.instance.tap();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bind to Action Button'),
        content: const SingleChildScrollView(
          child: Text(
            'iPhone 15 Pro and later — the silent switch is '
            'replaced by a configurable Action Button.\n\n'
            '1. Open the iOS Settings app.\n'
            '2. Action Button → swipe to "Shortcut".\n'
            '3. Tap "Choose a Shortcut" → PDFPrivio → '
            '"Scan to PDF".\n\n'
            'A press-and-hold now opens the scanner. Other PDFPrivio '
            'shortcuts (Sign, Redact, OCR, Find sensitive data, '
            'Open Recent) are also available.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showControlCenterDialog() {
    HapticsService.instance.tap();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lock Screen quick scan'),
        content: const SingleChildScrollView(
          child: Text(
            'iOS 18 lets you put PDFPrivio\'s scanner on the Lock '
            'Screen or in Control Center.\n\n'
            'Control Center:\n'
            '1. Swipe down from the top-right.\n'
            '2. Long-press a blank area → "+" → search "Scan to PDF".\n'
            '3. Tap to add. Drag to reposition.\n\n'
            'Lock Screen:\n'
            '1. Long-press the Lock Screen → Customize → Lock Screen.\n'
            '2. Tap a control slot → search "Scan to PDF".\n\n'
            'On iOS 17 or earlier, use Action Button binding or the '
            'home screen widget.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Layout primitives
// ============================================================================

/// Privacy hero card — dark teal, full-width, rounded. Shield glyph
/// + "Working offline" / "No cloud uploads…" + a small pulse dot.
/// Sits between the screen title and the first section as the one
/// piece of decorative real estate, anchoring the on-device promise.
class _PrivacyHero extends StatelessWidget {
  const _PrivacyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Working offline',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No cloud uploads. No tracking. Powered by Apple '
                  'on-device AI.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.86),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Uppercase grey label that sits above each [_SettingsCard].
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// White rounded card that groups multiple [_SettingsRow]s with
/// hair dividers between them. Replaces the older per-row bordered
/// cards — cleaner visual when 5 rows stack vertically.
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

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
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 62),
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

/// Single row inside a [_SettingsCard]. Round mint icon bubble +
/// title + 1-line subtitle on the left, optional trailing widget
/// (current value text, "Manage" link, Switch, etc.) on the right,
/// chevron when no trailing.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  bool get _showChevron =>
      onTap != null && trailing is! Switch && trailing is! _TrailingValue;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (_showChevron) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Right-aligned grey value (e.g. "Mustafa", "Match system") shown
/// inside a row. The wrapper is a marker type so [_SettingsRow]
/// knows to skip the chevron when the row has a current value.
class _TrailingValue extends StatelessWidget {
  final String text;
  const _TrailingValue(this.text);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Teal text "Manage" / "Open" link shown trailing in a row when
/// the row's action is meaningfully named (vs. a generic chevron).
class _TextLink extends StatelessWidget {
  final String label;
  const _TextLink(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
