import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/colors.dart';
import '../../data/services/consent_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/purchase_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _info = info);
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

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _SectionHeader(title: 'Subscription'),
            _SettingsTile(
              icon: Icons.workspace_premium_outlined,
              title: PurchaseService.instance.hasPro
                  ? 'PDFWork Pro · active'
                  : 'PDFWork Pro · not active',
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
            const SizedBox(height: 18),
            _SectionHeader(title: 'Privacy'),
            _SettingsTile(
              icon: Icons.shield_outlined,
              title: 'Manage data preferences',
              subtitle:
                  'Reopen the consent form to change analytics / ad choices',
              onTap: _resurfaceConsent,
            ),
            _SettingsTile(
              icon: Icons.description_outlined,
              title: 'Privacy Policy',
              subtitle: 'What we collect — and what we never collect',
              onTap: () => _open('https://mustafasalimerek-bit.github.io/pdfwork/privacy/'),
            ),
            _SettingsTile(
              icon: Icons.gavel_outlined,
              title: 'Terms of Service',
              subtitle: 'The rules of using PDFWork',
              onTap: () => _open('https://mustafasalimerek-bit.github.io/pdfwork/terms/'),
            ),
            const SizedBox(height: 18),
            _SectionHeader(title: 'About'),
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'About PDFWork',
              subtitle:
                  'On-device PDF toolkit by Erek Studio. Your documents '
                  'never leave this device.',
              onTap: () => _open('https://mustafasalimerek-bit.github.io/pdfwork/'),
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
                'PDFWork is a tool, not legal, medical, financial, or tax '
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
                    : 'PDFWork ${info.version} (${info.buildNumber})',
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
