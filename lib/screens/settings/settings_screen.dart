import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/consent_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/promo_code_service.dart';
import '../../data/services/purchase_service.dart';
import '../../data/services/widget_data_service.dart';
import '../../widgets/redeem_promo_dialog.dart';
import '../audit_log/audit_log_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PackageInfo? _info;
  bool _promoUsed = false;
  bool _widgetShowsNames = true;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    _loadPromoState();
    _loadWidgetPref();
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
    if (mounted) setState(() => _widgetShowsNames = next);
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

  Future<void> _resurfaceConsent() async {
    HapticsService.instance.tap();
    await ConsentService.instance.resurfaceConsentForm();
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

  Widget _buildPromoTile() {
    final timeLeft = PromoCodeService.instance.timeLeft;
    final hasActive = timeLeft != null;
    final daysLeft = hasActive ? timeLeft.inDays : 0;

    final String title;
    final String subtitle;
    if (hasActive) {
      title = 'Promo active · $daysLeft '
          '${daysLeft == 1 ? "day" : "days"} left';
      subtitle = 'Your 14-day Pro promo is running. Drops back to free '
          'tier when it ends.';
    } else if (_promoUsed) {
      title = 'Promo used';
      subtitle = 'This device has claimed its 14-day Pro promo. '
          'Upgrade to Pro to unlock everything again.';
    } else {
      title = 'Redeem a promo code';
      subtitle = 'Got a code from a conference or campaign? Tap to '
          'enter it — 14 days of Pro, no purchase.';
    }

    return _SettingsTile(
      icon: Icons.card_giftcard_outlined,
      title: title,
      subtitle: subtitle,
      onTap: _openRedeemDialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: MaxWidthBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
            _SectionHeader(title: 'Subscription'),
            _SettingsTile(
              icon: Icons.workspace_premium_outlined,
              title: PurchaseService.instance.hasPro
                  ? 'PDFPrivio Pro · active'
                  : 'PDFPrivio Pro · not active',
              subtitle: PurchaseService.instance.hasPro
                  ? 'Tap to view your plan and manage in App Store settings'
                  : 'Tap to see pricing and unlock everything',
              onTap: () => _open(
                'https://apps.apple.com/account/subscriptions',
              ),
            ),
            _SettingsTile(
              icon: Icons.restart_alt_outlined,
              title: 'Restore purchases',
              subtitle:
                  'Recover a previous purchase on this Apple ID',
              onTap: _restorePurchases,
            ),
            _buildPromoTile(),
            if (kDebugMode)
              _SettingsTile(
                icon: Icons.bug_report_outlined,
                title: PurchaseService.instance.hasPro
                    ? 'DEBUG: turn Pro OFF'
                    : 'DEBUG: turn Pro ON',
                subtitle:
                    'Skip the StoreKit sandbox and toggle entitlement '
                    'locally. Debug builds only.',
                onTap: () async {
                  HapticsService.instance.tap();
                  await PurchaseService.instance.setProForTesting(
                    !PurchaseService.instance.hasPro,
                  );
                  if (mounted) setState(() {});
                },
              ),
            if (kDebugMode &&
                (PromoCodeService.instance.hasActivePromo || _promoUsed))
              _SettingsTile(
                icon: Icons.delete_sweep_outlined,
                title: 'DEBUG: clear promo redemptions',
                subtitle: 'Wipe redemption history (shared_prefs + '
                    'Keychain) so codes can be redeemed again. Debug only.',
                onTap: () async {
                  HapticsService.instance.tap();
                  await PromoCodeService.instance.clearForTesting();
                  await _loadPromoState();
                  if (mounted) setState(() {});
                },
              ),
            const SizedBox(height: 18),
            _SectionHeader(title: 'Privacy'),
            _SettingsTile(
              icon: Icons.shield_outlined,
              title: 'Manage data preferences',
              subtitle: 'Reopen the consent form to manage analytics, '
                  'ad choices, and the California Do Not Sell My '
                  'Personal Information opt-out',
              onTap: _resurfaceConsent,
            ),
            _SettingsTile(
              icon: _widgetShowsNames
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              title: _widgetShowsNames
                  ? 'Home Screen widget · file names visible'
                  : 'Home Screen widget · file names hidden',
              subtitle: _widgetShowsNames
                  ? 'Tap to hide file names on the widget — useful '
                      'when client-identifying file names should stay '
                      'off the Home Screen.'
                  : 'Tap to show file names again on the widget.',
              onTap: _toggleWidgetNames,
            ),
            _SettingsTile(
              icon: Icons.receipt_long_outlined,
              title: 'Audit log',
              subtitle: 'Every Sign / Redact / OCR / Merge / PII Scan '
                  'recorded with timestamp + file metadata. Browse, '
                  'export as CSV, or clear.',
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AuditLogScreen(),
                  ),
                );
              },
            ),
            _SettingsTile(
              icon: Icons.description_outlined,
              title: 'Privacy Policy',
              subtitle: 'What we collect — and what we never collect',
              onTap: () => _open('https://mustafasalimerek-bit.github.io/pdfprivio/privacy/'),
            ),
            _SettingsTile(
              icon: Icons.gavel_outlined,
              title: 'Terms of Service',
              subtitle: 'The rules of using PDFPrivio',
              onTap: () => _open('https://mustafasalimerek-bit.github.io/pdfprivio/terms/'),
            ),
            const SizedBox(height: 18),
            _SectionHeader(title: 'iOS integrations'),
            _SettingsTile(
              icon: Icons.bolt_outlined,
              title: 'Bind to Action Button',
              subtitle: 'iPhone 15 Pro / 16 Pro: Settings → Action Button '
                  '→ Shortcut → PDFPrivio → Scan to PDF. One physical '
                  'press opens the document scanner.',
              onTap: () {
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
                        'A press-and-hold of the Action Button now '
                        'opens PDFPrivio\'s scanner. Other shortcuts '
                        '(Sign, Redact, OCR, Find sensitive data, '
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
              },
            ),
            _SettingsTile(
              icon: Icons.tune_outlined,
              title: 'Add to Control Center / Lock Screen',
              subtitle: 'iOS 18+: long-press Control Center → + → '
                  'Scan to PDF. Tap from the Lock Screen without '
                  'unlocking.',
              onTap: () {
                HapticsService.instance.tap();
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Lock Screen quick scan'),
                    content: const SingleChildScrollView(
                      child: Text(
                        'iOS 18 lets you put PDFPrivio\'s scanner on '
                        'the Lock Screen or in Control Center.\n\n'
                        'Control Center:\n'
                        '1. Swipe down from the top-right.\n'
                        '2. Long-press a blank area → "+" → search '
                        '"Scan to PDF".\n'
                        '3. Tap to add. Drag to reposition.\n\n'
                        'Lock Screen:\n'
                        '1. Long-press the Lock Screen → Customize → '
                        'Lock Screen.\n'
                        '2. Tap a control slot → search "Scan to PDF".\n\n'
                        'On iOS 17 or earlier, use the Action Button '
                        'tile above or the home screen widget.',
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
              },
            ),
            const SizedBox(height: 18),
            _SectionHeader(title: 'About'),
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'About PDFPrivio',
              subtitle:
                  'On-device PDF toolkit by Erek Studio. Your documents '
                  'never leave this device.',
              onTap: () => _open('https://mustafasalimerek-bit.github.io/pdfprivio/'),
            ),
            _SettingsTile(
              icon: Icons.mail_outline,
              title: 'Contact support',
              subtitle: 'Questions, bugs, feature requests',
              onTap: () => _open('mailto:mustafasalimerek@gmail.com'),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'PDFPrivio is a tool, not legal, medical, financial, or tax '
                'advice. Outputs from automated detection, redaction, '
                'OCR, signature, and comparison features are aids — not '
                'substitutes for human review. You are responsible for '
                'verifying any document before relying on it for a '
                'consequential decision or sending it to a third party.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Text(
                info == null
                    ? ''
                    : 'PDFPrivio ${info.version} (${info.buildNumber})',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 6),
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
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
    );
  }
}
