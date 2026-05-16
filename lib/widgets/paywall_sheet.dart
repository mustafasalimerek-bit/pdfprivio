import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/colors.dart';
import '../data/services/haptics_service.dart';
import '../data/services/purchase_service.dart';
import 'redeem_promo_dialog.dart';

/// Contextual paywall sheet. Two entry points and three visual modes:
///
///   * **Pro-only tap** (Form Fill / Bates / Redact / Batch / Receipt)
///     → feature-aware hero ("Unlock signing", "Unlock Bates", …)
///     with the tool's own icon. This is the highest-converting
///     surface — user just felt the need and we name what they're
///     paying for.
///   * **Quota-exhausted free tool** (Sign / Compress / Merge / …
///     hit daily cap) → generic "You've maxed today's free Sign"
///     hero with the tool icon.
///   * **Generic upsell** (Pro tab, Settings) → "Unlock the full
///     toolkit" sparkles hero.
///
/// Layout shape borrowed from the App-Store-editorial paywall pattern
/// (small "Pro feature" pill + close, tinted hero icon, perk list,
/// stacked plans with yearly default, big primary CTA, transparent
/// pricing microcopy, Restore / Terms / Privacy footer). The pricing
/// model — Monthly / Yearly / Lifetime, real App Store prices, no
/// hardcoded $X.XX in the sheet — is intentionally kept; the
/// lifetime tier serves the "subscription-averse" buyer segment and
/// the wedge audit decided that's worth keeping despite the
/// editorial mockup dropping it.
class PaywallSheet extends StatefulWidget {
  final String? quotaContext; // e.g. "Sign PDF", "Form Fill"

  const PaywallSheet({super.key, this.quotaContext});

  /// Returns `true` if the user successfully purchased while inside —
  /// caller can re-attempt the gated action on the back of that.
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

  @override
  void initState() {
    super.initState();
    PurchaseService.instance.entitlementChanges.listen((_) {
      if (mounted && PurchaseService.instance.hasPro) {
        Navigator.of(context).pop(true);
      }
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
    final hero = _heroFor(widget.quotaContext);

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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DragHandle(),
                const SizedBox(height: 6),
                _TopBar(onClose: () => Navigator.of(context).pop(false)),
                const SizedBox(height: 22),
                _Hero(icon: hero.icon, title: hero.title, subtitle: hero.subtitle),
                const SizedBox(height: 20),
                const _PerkList(),
                const SizedBox(height: 18),
                _PricingCard(
                  sku: ProSku.yearly,
                  title: 'Yearly',
                  product: yearly,
                  fallbackPrice: '\$39.99',
                  cadence: 'per year',
                  badge: 'BEST VALUE',
                  splitMonthly: true,
                  selected: _selected == ProSku.yearly,
                  onSelect: () => setState(() => _selected = ProSku.yearly),
                ),
                const SizedBox(height: 10),
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
                  sku: ProSku.lifetime,
                  title: 'Lifetime',
                  product: lifetime,
                  fallbackPrice: '\$79.99',
                  cadence: 'one-time · no renewal',
                  selected: _selected == ProSku.lifetime,
                  onSelect: () => setState(() => _selected = ProSku.lifetime),
                ),
                const SizedBox(height: 20),
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
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _microcopyFor(_selected, monthly, yearly, lifetime),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _FooterLink(
                      label: 'Restore',
                      onTap: _busy ? null : _restore,
                    ),
                    _Dot(),
                    _FooterLink(
                      label: 'Promo code',
                      onTap: _busy
                          ? null
                          : () {
                              HapticsService.instance.tap();
                              RedeemPromoDialog.show(context);
                            },
                    ),
                    _Dot(),
                    _FooterLink(
                      label: 'Terms',
                      onTap: () => _openUrl(
                        'https://mustafasalimerek-bit.github.io/pdfprivio/terms/',
                      ),
                    ),
                    _Dot(),
                    _FooterLink(
                      label: 'Privacy',
                      onTap: () => _openUrl(
                        'https://mustafasalimerek-bit.github.io/pdfprivio/privacy/',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _LegalDisclosure(),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _ctaFor(ProSku sku) {
    switch (sku) {
      case ProSku.monthly:
        return 'Continue with monthly';
      case ProSku.yearly:
        return 'Continue with yearly';
      case ProSku.lifetime:
        return 'Buy lifetime';
    }
  }

  String _microcopyFor(
    ProSku sku,
    ProductDetails? monthly,
    ProductDetails? yearly,
    ProductDetails? lifetime,
  ) {
    switch (sku) {
      case ProSku.monthly:
        final p = monthly?.price ?? '\$4.99';
        return '$p / month · Cancel anytime in Apple ID settings';
      case ProSku.yearly:
        final p = yearly?.price ?? '\$39.99';
        return '$p / year · Cancel anytime in Apple ID settings';
      case ProSku.lifetime:
        final p = lifetime?.price ?? '\$79.99';
        return '$p one-time · No subscription, no renewal';
    }
  }
}

// ---------------------------------------------------------------------------
// Feature-aware hero mapping
// ---------------------------------------------------------------------------

class _PaywallHero {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PaywallHero({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

/// Map the gated tile's title to a hero icon + a short headline.
/// "Unlock signing" reads infinitely better than "Pro" when the user
/// just tapped Sign and got bounced here — and the icon match is the
/// non-verbal half of that message.
_PaywallHero _heroFor(String? ctx) {
  switch (ctx) {
    // Pro-only tools (5)
    case 'Fill form':
      return const _PaywallHero(
        icon: Icons.edit_document,
        title: 'Unlock form filling',
        subtitle: 'And 4 other Pro tools',
      );
    case 'Bates numbering':
      return const _PaywallHero(
        icon: Icons.tag,
        title: 'Unlock Bates numbering',
        subtitle: 'And 4 other Pro tools',
      );
    case 'Redact':
      return const _PaywallHero(
        icon: Icons.format_color_fill,
        title: 'Unlock redaction',
        subtitle: 'And 4 other Pro tools',
      );
    case 'Batch operations':
      return const _PaywallHero(
        icon: Icons.dynamic_feed_outlined,
        title: 'Unlock batch operations',
        subtitle: 'And 4 other Pro tools',
      );
    case 'Receipt scanner':
      return const _PaywallHero(
        icon: Icons.receipt_long_outlined,
        title: 'Unlock receipt scanning',
        subtitle: 'And 4 other Pro tools',
      );

    // Free tools that hit daily quota — icon-matched, copy says "used up"
    case 'Sign PDF':
      return const _PaywallHero(
        icon: Icons.draw_outlined,
        title: 'Sign is used up for today',
        subtitle: 'Pro removes the daily cap',
      );
    case 'Merge PDFs':
      return const _PaywallHero(
        icon: Icons.library_books_outlined,
        title: 'Merge is used up for today',
        subtitle: 'Pro removes the daily cap',
      );
    case 'Compress PDF':
      return const _PaywallHero(
        icon: Icons.compress_outlined,
        title: 'Compress is used up for today',
        subtitle: 'Pro removes the daily cap',
      );
    case 'Split PDF':
      return const _PaywallHero(
        icon: Icons.content_cut_outlined,
        title: 'Split is used up for today',
        subtitle: 'Pro removes the daily cap',
      );
    case 'OCR PDF':
      return const _PaywallHero(
        icon: Icons.find_in_page_outlined,
        title: 'OCR is used up for today',
        subtitle: 'Pro removes the daily cap',
      );
    case 'Scan to PDF':
      return const _PaywallHero(
        icon: Icons.document_scanner_outlined,
        title: 'Scan is used up for today',
        subtitle: 'Pro removes the daily cap',
      );
    case 'Find sensitive data':
      return const _PaywallHero(
        icon: Icons.shield_outlined,
        title: 'PII scan is used up for today',
        subtitle: 'Pro removes the daily cap',
      );

    // Generic upsell (Pro tab, Settings)
    default:
      return const _PaywallHero(
        icon: Icons.auto_awesome,
        title: 'Unlock the full toolkit',
        subtitle: '5 Pro tools + no daily limits',
      );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textTertiary.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onClose;
  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
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
                size: 13,
                color: AppColors.primary,
              ),
              SizedBox(width: 5),
              Text(
                'Pro feature',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Close button required by Apple App Review Guidelines 3.1.2 +
        // 3.2.2 — must be visible and tappable. Kept neutral grey so
        // the default visual pull stays on the primary CTA below.
        IconButton(
          onPressed: onClose,
          icon: const Icon(
            Icons.close,
            color: AppColors.textTertiary,
            size: 22,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          tooltip: 'Close',
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Hero({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.iconTint,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(
            icon,
            color: AppColors.primary,
            size: 36,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PerkList extends StatelessWidget {
  const _PerkList();

  static const _items = <String>[
    'Form Fill, Bates, Redact, Batch, Receipts',
    'No daily limits on any tool',
    'No ads anywhere',
    'Same on-device privacy — files never leave',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.iconTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: AppColors.primary,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
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
  /// When true (yearly), the price row shows the $/mo split anchor:
  /// "$3.33 /mo · billed $39.99/yr". The other tiers show flat price.
  final bool splitMonthly;

  const _PricingCard({
    required this.sku,
    required this.title,
    required this.product,
    required this.fallbackPrice,
    required this.cadence,
    required this.selected,
    required this.onSelect,
    this.badge,
    this.splitMonthly = false,
  });

  @override
  Widget build(BuildContext context) {
    final price = product?.price ?? fallbackPrice;
    return InkWell(
      onTap: () {
        HapticsService.instance.select();
        onSelect();
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (splitMonthly)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _approxMonthlyForYearly(price),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            '/mo · billed $price/yr',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          price,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            cadence,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RadioBubble(selected: selected),
          ],
        ),
      ),
    );
  }

  /// Best-effort split: extract leading currency symbol + the number,
  /// divide by 12, re-attach the symbol. Falls back to the full price
  /// string if we can't parse — better to show "$39.99 /mo" than crash.
  String _approxMonthlyForYearly(String price) {
    final match = RegExp(r'(\D*)(\d+[\.,]?\d*)').firstMatch(price);
    if (match == null) return price;
    final symbol = match.group(1) ?? '';
    final raw = match.group(2) ?? '';
    final normalised = raw.replaceAll(',', '.');
    final yearly = double.tryParse(normalised);
    if (yearly == null) return price;
    final monthly = yearly / 12;
    final formatted = monthly.toStringAsFixed(2);
    return '$symbol$formatted';
  }
}

class _RadioBubble extends StatelessWidget {
  final bool selected;
  const _RadioBubble({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, color: Colors.white, size: 16)
          : const SizedBox.shrink(),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: onTap == null
                ? AppColors.textTertiary
                : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        '·',
        style: TextStyle(
          fontSize: 11,
          color: AppColors.textTertiary.withValues(alpha: 0.7),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LegalDisclosure extends StatelessWidget {
  const _LegalDisclosure();

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
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(
            text: 'Subscriptions automatically renew unless cancelled at '
                'least 24 hours before the end of the current period. '
                'Payment is charged to your Apple ID at confirmation. '
                'Lifetime is a one-time purchase with no renewal. '
                'By continuing you agree to our ',
          ),
          TextSpan(
            text: 'Terms',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () =>
                  _open('https://mustafasalimerek-bit.github.io/pdfprivio/terms/'),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () =>
                  _open('https://mustafasalimerek-bit.github.io/pdfprivio/privacy/'),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
