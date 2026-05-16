import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/colors.dart';
import '../data/services/haptics_service.dart';
import '../data/services/purchase_service.dart';
import '../data/services/usage_limits_service.dart';

/// Drop-in bottom sheet that pitches Pro with all three SKUs side by
/// side. Used from two places:
///   * tile tap on a Pro-only tool (Form Fill / Bates / Redact)
///   * tile tap on a free-tier-exhausted tool
///
/// Pass `quotaContext` if the user hit a daily limit — the heading then
/// reads "You've used today's free X" instead of the generic upsell
/// line, which converts much better than a vague "go Pro" prompt.
class PaywallSheet extends StatefulWidget {
  final String? quotaContext; // e.g. "Compress PDF"

  const PaywallSheet({super.key, this.quotaContext});

  /// Pushes the sheet and resolves when it closes. Returns true if the
  /// user successfully purchased while inside — caller can re-attempt
  /// the gated action on the back of that.
  static Future<bool> show(BuildContext context, {String? quotaContext}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaywallSheet(quotaContext: quotaContext),
    ).then((v) => v ?? false);
  }

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  ProSku _selected = ProSku.yearly; // anchor — best value
  bool _busy = false;
  late final void Function() _entitlementListener;

  @override
  void initState() {
    super.initState();
    _entitlementListener = () {
      if (mounted && PurchaseService.instance.hasPro) {
        Navigator.of(context).pop(true);
      }
    };
    PurchaseService.instance.entitlementChanges.listen((_) {
      _entitlementListener();
    });
  }

  Future<void> _buy() async {
    HapticsService.instance.tap();
    setState(() => _busy = true);
    final ok = await PurchaseService.instance.buy(_selected);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok && !PurchaseService.instance.isStoreAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "The App Store is not reachable right now. "
            "Check your connection and try again.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (!ok && PurchaseService.instance.productFor(_selected) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "This pricing option isn't available yet on the App Store. "
            "We're enabling it — try again shortly.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _restore() async {
    HapticsService.instance.tap();
    setState(() => _busy = true);
    await PurchaseService.instance.restorePurchases();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final monthly = PurchaseService.instance.productFor(ProSku.monthly);
    final yearly = PurchaseService.instance.productFor(ProSku.yearly);
    final lifetime = PurchaseService.instance.productFor(ProSku.lifetime);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                _Header(quotaContext: widget.quotaContext),
                const SizedBox(height: 18),
                _PerkList(),
                const SizedBox(height: 22),
                _PricingCard(
                  sku: ProSku.monthly,
                  title: 'Monthly',
                  product: monthly,
                  fallbackPrice: '\$4.99',
                  cadence: 'per month',
                  selected: _selected == ProSku.monthly,
                  onSelect: () => setState(() => _selected = ProSku.monthly),
                ),
                const SizedBox(height: 10),
                _PricingCard(
                  sku: ProSku.yearly,
                  title: 'Yearly',
                  product: yearly,
                  fallbackPrice: '\$39.99',
                  cadence: 'per year',
                  badge: 'BEST VALUE',
                  selected: _selected == ProSku.yearly,
                  onSelect: () => setState(() => _selected = ProSku.yearly),
                ),
                const SizedBox(height: 10),
                _PricingCard(
                  sku: ProSku.lifetime,
                  title: 'Lifetime',
                  product: lifetime,
                  fallbackPrice: '\$79.99',
                  cadence: 'one-time · no renewal',
                  selected: _selected == ProSku.lifetime,
                  onSelect: () => setState(() => _selected = ProSku.lifetime),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _buy,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          )
                        : Text(
                            _ctaFor(_selected),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _restore,
                    child: const Text(
                      'Restore purchases',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const _LegalFooter(),
              ],
            ),
          ),
        );
      },
    );
  }

  String _ctaFor(ProSku sku) {
    switch (sku) {
      case ProSku.monthly:
        return 'Start monthly';
      case ProSku.yearly:
        return 'Start yearly';
      case ProSku.lifetime:
        return 'Buy lifetime';
    }
  }
}

class _Header extends StatelessWidget {
  final String? quotaContext;
  const _Header({this.quotaContext});

  @override
  Widget build(BuildContext context) {
    final reset = UsageLimitsService.instance
        .stateFor('merge'); // any tool, just for resetsAt
    return FutureBuilder(
      future: reset,
      builder: (context, snap) {
        final resetsAt = snap.data?.resetsAt;
        final inHours = resetsAt?.difference(DateTime.now()).inHours;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'PDFPRIVIO PRO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              quotaContext != null
                  ? "Free $quotaContext is used up for today"
                  : 'Unlock the full PDFPrivio toolkit',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              quotaContext != null
                  ? 'Your daily quota resets at midnight'
                      '${inHours != null ? ' — in ${inHours}h' : ''}. '
                      'Or remove the cap and unlock Form Fill, Bates, '
                      'and Redact right now.'
                  : 'Remove daily limits across 15 tools and unlock '
                      'Form Fill, Bates numbering, and Redact.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PerkList extends StatelessWidget {
  static const _items = <String>[
    'No daily limits on any tool',
    'Form Fill, Bates numbering, Redact — unlocked',
    'No ads',
    'Same on-device privacy guarantee',
  ];

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
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                    size: 17,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(fontSize: 13, height: 1.35),
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

class _PricingCard extends StatelessWidget {
  final ProSku sku;
  final String title;
  final ProductDetails? product;
  final String fallbackPrice;
  final String cadence;
  final String? badge;
  final bool selected;
  final VoidCallback onSelect;

  const _PricingCard({
    required this.sku,
    required this.title,
    required this.product,
    required this.fallbackPrice,
    required this.cadence,
    required this.selected,
    required this.onSelect,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final price = product?.price ?? fallbackPrice;
    return InkWell(
      onTap: () {
        HapticsService.instance.select();
        onSelect();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected
                  ? AppColors.primary
                  : AppColors.textTertiary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.warning,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cadence,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 10,
      color: AppColors.textTertiary,
      height: 1.5,
    );
    final linkStyle = baseStyle.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(
            text: 'Monthly and yearly auto-renew until cancelled — manage '
                "in your Apple ID's subscription settings. Lifetime is a "
                'one-time purchase. Payment is charged to your Apple ID at '
                'confirmation. By continuing you agree to our ',
          ),
          TextSpan(
            text: 'Terms of Service',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _open('https://mustafasalimerek-bit.github.io/pdfprivio/terms/'),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _open('https://mustafasalimerek-bit.github.io/pdfprivio/privacy/'),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
