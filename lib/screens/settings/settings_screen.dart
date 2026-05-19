import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/layout.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/display_name_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/promo_code_service.dart';
import '../../data/services/purchase_service.dart';
import '../../data/services/widget_data_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/redeem_promo_dialog.dart';
import '../../widgets/screen_container.dart';
import '../../widgets/section_header.dart';
import '../audit_log/audit_log_screen.dart';
import '../pro/pro_screen.dart';
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
  bool _hasPro = false;
  StreamSubscription<void>? _auditChangesSub;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    _loadPromoState();
    _loadWidgetPref();
    _loadDisplayName();
    _loadAuditCount();
    // Cache hasPro locally so _ProTopCard sees a stable parameter
    // across unrelated setState() calls — without this, every
    // setState (display name change, audit count refresh, etc.)
    // rebuilds the hero card and resets its Material ripple state
    // mid-tap.
    _hasPro = PurchaseService.instance.hasPro;
    // Keep the Audit log subtitle ("$n events · export or clear") in
    // sync if the user runs a tool from another tab while Settings is
    // still mounted. AuditService already broadcasts a void event on
    // every record / clear — we just re-fetch the count.
    _auditChangesSub = AuditService.instance.changes.listen((_) {
      _loadAuditCount();
    });
  }

  @override
  void dispose() {
    _auditChangesSub?.cancel();
    super.dispose();
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
          "Privio currently matches your device's system "
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
    if (!_hasPro) return 'Free tier';
    final sku = PurchaseService.instance.activeSku;
    switch (sku) {
      case ProSku.monthly:
        return 'Pro · Monthly';
      case ProSku.yearly:
        return 'Pro · Yearly';
      case ProSku.lifetime:
        return 'Pro · Lifetime';
      case null:
        return 'Pro · active';
    }
  }

  String _proPlanSubtitle() {
    if (!_hasPro) {
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
              maxLength: 24,
              decoration: const InputDecoration(
                hintText: 'Your name',
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
    if (result == null) return;
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

  Future<void> _openProScreen() async {
    HapticsService.instance.tap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProScreen()),
    );
    if (mounted) {
      setState(() => _hasPro = PurchaseService.instance.hasPro);
    }
  }

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
              'device, or visit:',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 10),
            SelectableText(
              'apps.apple.com/account/subscriptions',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
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

  Future<void> _emailSupport() async {
    HapticsService.instance.tap();
    const email = 'mustafasalimerek@gmail.com';
    // Pre-fill subject + a tiny diagnostic footer so support replies
    // arrive with enough context (app version, build) to act on
    // without an extra back-and-forth. Body uses a blank prompt area
    // followed by the diagnostic block; the user types above the
    // dashes, the dev reads below for context.
    final info = _info;
    final version = info != null
        ? '${info.version} (${info.buildNumber})'
        : 'unknown';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': 'Privio support · v$version',
        'body': '\n\n---\nPrivio $version\niOS',
      },
    );
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
                fontWeight: FontWeight.w700,
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

  Future<void> _restorePurchases() async {
    HapticsService.instance.tap();
    await PurchaseService.instance.restorePurchases();
    if (!mounted) return;
    setState(() => _hasPro = PurchaseService.instance.hasPro);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _hasPro
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
    if (mounted) {
      setState(() => _hasPro = PurchaseService.instance.hasPro);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: MaxWidthBody(
          child: ScreenContainer(
            title: 'Settings',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProTopCard(
                  hasPro: _hasPro,
                  onOpenPro: _openProScreen,
                  onManageSubscription: _openSubscriptions,
                ),
                const SizedBox(height: Layout.sectionSpacing),

                // ACCOUNT
                const SectionHeader('Account'),
                AppCard(children: _accountRows()),
                const SizedBox(height: Layout.sectionSpacing),

                // PERSONALIZATION
                const SectionHeader('Personalization'),
                AppCard(children: _personalizationRows()),
                const SizedBox(height: Layout.sectionSpacing),

                // PRIVACY & DATA
                const SectionHeader('Privacy & data'),
                AppCard(children: _privacyRows()),
                const SizedBox(height: Layout.sectionSpacing),

                // iOS INTEGRATIONS
                const SectionHeader('iOS integrations'),
                AppCard(children: _integrationRows()),
                const SizedBox(height: Layout.sectionSpacing),

                // ABOUT
                const SectionHeader('About'),
                AppCard(children: _aboutRows()),
                const SizedBox(height: 18),

                // Disclaimer + version footer. Bumped to textSecondary
                // (#64748B → 5.7:1 contrast vs cream) so this passes
                // WCAG AA on small text — textTertiary was 2.95:1, which
                // looks elegant but fails accessibility.
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Privio is a tool, not legal, medical, financial, '
                    'or tax advice. Outputs are aids — not substitutes for '
                    'human review.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    info == null
                        ? ''
                        : 'Privio ${info.version} (${info.buildNumber})',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
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
      ),
    );
  }

  List<Widget> _accountRows() {
    final rows = <_RowSpec>[];
    if (_hasPro) {
      rows.add(_RowSpec(
        icon: Icons.auto_awesome,
        title: _proPlanLabel(),
        subtitle: _proPlanSubtitle(),
        trailing: const _TextLink('Manage'),
        onTap: _openSubscriptions,
      ));
    }
    rows.add(_RowSpec(
      icon: Icons.restart_alt_outlined,
      title: 'Restore purchases',
      subtitle: 'Recover a previous purchase on this Apple ID',
      onTap: _restorePurchases,
    ));
    rows.add(_promoRowSpec());
    if (kDebugMode) {
      rows.add(_RowSpec(
        icon: Icons.bug_report_outlined,
        title: _hasPro ? 'DEBUG: turn Pro OFF' : 'DEBUG: turn Pro ON',
        subtitle: 'Debug builds only — bypasses StoreKit',
        onTap: () async {
          HapticsService.instance.tap();
          await PurchaseService.instance.setProForTesting(!_hasPro);
          if (mounted) {
            setState(() => _hasPro = PurchaseService.instance.hasPro);
          }
        },
      ));
    }
    if (kDebugMode &&
        (PromoCodeService.instance.hasActivePromo || _promoUsed)) {
      rows.add(_RowSpec(
        icon: Icons.delete_sweep_outlined,
        title: 'DEBUG: clear promo redemptions',
        subtitle: 'Wipe redemption history — debug only',
        onTap: () async {
          HapticsService.instance.tap();
          await PromoCodeService.instance.clearForTesting();
          await _loadPromoState();
          if (mounted) setState(() {});
        },
      ));
    }
    return _build(rows);
  }

  List<Widget> _personalizationRows() => _build([
        _RowSpec(
          icon: Icons.person_outline,
          title: 'Display name',
          subtitle: 'For your home screen greeting',
          trailing: CardRowTrailingValue(
            _displayName == null || _displayName!.isEmpty
                ? 'Not set'
                : _displayName!,
          ),
          onTap: _editDisplayName,
        ),
        _RowSpec(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          subtitle: 'Match system',
          onTap: _openAppearance,
        ),
        _RowSpec(
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
          // No row-level onTap — the Switch is the source of truth.
          // Pairing onTap with onChanged double-toggles and snaps back.
        ),
      ]);

  List<Widget> _privacyRows() => _build([
        _RowSpec(
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
        _RowSpec(
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
        _RowSpec(
          icon: Icons.description_outlined,
          title: 'Privacy Policy',
          subtitle: 'What we collect — and what we never collect',
          onTap: () => _open(
              'https://mustafasalimerek-bit.github.io/pdfprivio/privacy/'),
        ),
        _RowSpec(
          icon: Icons.gavel_outlined,
          title: 'Terms of Service',
          subtitle: 'The rules of using Privio',
          onTap: () => _open(
              'https://mustafasalimerek-bit.github.io/pdfprivio/terms/'),
        ),
      ]);

  List<Widget> _integrationRows() => _build([
        _RowSpec(
          icon: Icons.bolt_outlined,
          title: 'Action Button',
          subtitle: 'Bind Scan to PDF on iPhone 15 Pro+',
          onTap: _showActionButtonDialog,
        ),
        _RowSpec(
          icon: Icons.tune_outlined,
          title: 'Control Center',
          subtitle: 'iOS 18+ Lock Screen quick scan',
          onTap: _showControlCenterDialog,
        ),
      ]);

  List<Widget> _aboutRows() => _build([
        _RowSpec(
          icon: Icons.info_outline,
          title: 'About Privio',
          subtitle: 'On-device PDF toolkit by Erek Studio',
          onTap: () =>
              _open('https://mustafasalimerek-bit.github.io/pdfprivio/'),
        ),
        _RowSpec(
          icon: Icons.mail_outline,
          title: 'Contact support',
          subtitle: 'Questions, bugs, feature requests',
          onTap: _emailSupport,
        ),
      ]);

  _RowSpec _promoRowSpec() {
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
    return _RowSpec(
      icon: Icons.card_giftcard_outlined,
      title: title,
      subtitle: subtitle,
      onTap: _openRedeemDialog,
    );
  }

  /// Turn a list of row specs into [CardRow]s with correct `isLast`,
  /// auto-attaching a chevron when no trailing is supplied.
  List<Widget> _build(List<_RowSpec> rows) {
    return [
      for (var i = 0; i < rows.length; i++)
        CardRow(
          isLast: i == rows.length - 1,
          onTap: rows[i].onTap,
          leading: CardRowLeading(
            icon: rows[i].icon,
            title: rows[i].title,
            subtitle: rows[i].subtitle,
          ),
          trailing: rows[i].trailing ??
              (rows[i].onTap != null ? const CardRowChevron() : null),
        ),
    ];
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
            '3. Tap "Choose a Shortcut" → Privio → '
            '"Scan to PDF".\n\n'
            'A press-and-hold now opens the scanner. Other Privio '
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
            'iOS 18 lets you put Privio\'s scanner on the Lock '
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

/// Plain data shape so [_build] can wire each row uniformly.
class _RowSpec {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  _RowSpec({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
}

/// Dark-teal hero card at the top of Settings. Drives the Pro
/// upsell for free users and surfaces "Manage subscription" for
/// active Pro users.
class _ProTopCard extends StatelessWidget {
  final bool hasPro;
  final VoidCallback onOpenPro;
  final VoidCallback onManageSubscription;
  const _ProTopCard({
    required this.hasPro,
    required this.onOpenPro,
    required this.onManageSubscription,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(Layout.heroCornerRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Layout.heroCornerRadius),
        onTap: hasPro ? onManageSubscription : onOpenPro,
        child: Padding(
          padding: const EdgeInsets.all(Layout.heroPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasPro ? Icons.check_circle : Icons.auto_awesome,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      hasPro ? 'PRIVIO PRO · ACTIVE' : 'PRIVIO PRO',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasPro ? 'Full toolkit unlocked' : 'Unlock the full toolkit',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasPro
                    ? 'Manages in Apple ID · same on-device privacy'
                    : 'No daily limits. 5 Pro-only features.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasPro
                          ? 'Manage subscription'
                          : 'Start 7-day free trial',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.arrow_forward,
                      color: AppColors.primary,
                      size: 13,
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

/// Teal "Manage" / "Open" trailing link.
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
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
