import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/purchase_service.dart';
import '../../widgets/paywall_sheet.dart';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  bool _hasPro = PurchaseService.instance.hasPro;
  ProSku? _activeSku = PurchaseService.instance.activeSku;
  bool _busy = false;
  StreamSubscription<EntitlementTier>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = PurchaseService.instance.entitlementChanges.listen((tier) {
      if (!mounted) return;
      setState(() {
        _hasPro = tier == EntitlementTier.pro;
        _activeSku = PurchaseService.instance.activeSku;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _openPaywall() async {
    await PaywallSheet.show(context);
  }

  Future<void> _restore() async {
    HapticsService.instance.tap();
    setState(() => _busy = true);
    await PurchaseService.instance.restorePurchases();
    if (!mounted) return;
    setState(() => _busy = false);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PDFPrivio Pro',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: MaxWidthBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_hasPro) _ActiveBanner(activeSku: _activeSku),
            if (!_hasPro) const _Hero(),
            const SizedBox(height: 18),
            if (!_hasPro) ...[
              _PricingCard(
                sku: ProSku.monthly,
                title: 'Monthly',
                fallbackPrice: '\$4.99',
                cadence: 'per month',
                description: 'Start small — cancel any time in Apple ID settings.',
                onTap: _openPaywall,
              ),
              const SizedBox(height: 10),
              _PricingCard(
                sku: ProSku.yearly,
                title: 'Yearly',
                fallbackPrice: '\$39.99',
                cadence: 'per year',
                description: 'Save ~33% vs monthly. Anchor option for most users.',
                badge: 'BEST VALUE',
                onTap: _openPaywall,
              ),
              const SizedBox(height: 10),
              _PricingCard(
                sku: ProSku.lifetime,
                title: 'Lifetime',
                fallbackPrice: '\$79.99',
                cadence: 'one-time · never renews',
                description: 'Pay once, use forever. No subscription email reminders.',
                onTap: _openPaywall,
              ),
              const SizedBox(height: 22),
              const _PerksBlock(),
              const SizedBox(height: 18),
              _StaysFreeNote(),
            ],
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: _busy ? null : _restore,
                child: Text(
                  _busy ? 'Restoring…' : 'Restore purchases',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const _Faq(),
          ],
          ),
        ),
      ),
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  final ProSku? activeSku;
  const _ActiveBanner({required this.activeSku});

  String get _activeLabel {
    switch (activeSku) {
      case ProSku.monthly:
        return 'Monthly subscription · renews each month';
      case ProSku.yearly:
        return 'Yearly subscription · renews each year';
      case ProSku.lifetime:
        return 'Lifetime · paid once, yours forever';
      case null:
        return 'Pro is active on this Apple ID';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.20),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.workspace_premium,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "You're on Pro",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _activeLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.success,
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

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Text(
              'PDFPRIVIO PRO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Remove daily limits.\nUnlock the full toolkit.',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pro lifts the free-tier caps on 15 tools and opens Form '
            'Fill, Bates numbering, and Redact. Same on-device privacy.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.4,
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
  final String fallbackPrice;
  final String cadence;
  final String description;
  final String? badge;
  final VoidCallback onTap;

  const _PricingCard({
    required this.sku,
    required this.title,
    required this.fallbackPrice,
    required this.cadence,
    required this.description,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final product = PurchaseService.instance.productFor(sku);
    final price = product?.price ?? fallbackPrice;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: badge != null
                  ? AppColors.warning
                  : AppColors.border,
              width: badge != null ? 1.5 : 1,
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
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
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
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'Choose',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PerksBlock extends StatelessWidget {
  const _PerksBlock();

  static const _perks = <(IconData, String)>[
    (Icons.timer_off_outlined, 'No daily limits on any of the 15 free tools'),
    (Icons.edit_document, 'Form Fill — IRS, USCIS, court motion AcroForm fields'),
    (Icons.tag, 'Bates numbering — legal discovery standard'),
    (Icons.format_color_fill, 'Redact — text removed from data stream, not just hidden'),
    (Icons.block, 'No ads anywhere'),
    (Icons.lock_outline, 'Same on-device processing — your PDFs never leave the device'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHAT YOU GET',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          for (final (icon, text) in _perks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 13, height: 1.4),
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

class _StaysFreeNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined,
              color: AppColors.success, size: 16),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Free stays free. The 15 tools you can use today never get "
              'paywalled — Pro removes their daily caps, not the tools '
              'themselves.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.success,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq();

  static const _items = <_FaqItem>[
    _FaqItem(
      q: 'What is in the free tier?',
      a: '15 tools with daily caps (1–5 uses per tool per day) plus the '
          'three Pro-only tools locked. Quotas reset at midnight in your '
          'local timezone.',
    ),
    _FaqItem(
      q: 'Why three pricing options?',
      a: 'Monthly for casual try-out. Yearly is the best value for most '
          'professional users. Lifetime is for power users who want to '
          'never see a renewal screen.',
    ),
    _FaqItem(
      q: "Will my PDFs stay on-device on Pro?",
      a: 'Yes — Pro removes caps and unlocks tools, but every operation '
          'still runs locally. No backend, no upload, no change to the '
          'privacy posture.',
    ),
    _FaqItem(
      q: 'How do I cancel a subscription?',
      a: "Apple ID Settings → Subscriptions → PDFPrivio. We can't cancel "
          'on your behalf — Apple handles all subscription management.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 8, 2, 8),
          child: Text(
            'FREQUENTLY ASKED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  title: Text(
                    item.q,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.a,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});
}
