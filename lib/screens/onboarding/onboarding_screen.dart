import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/price_fallbacks.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/onboarding_service.dart';
import '../../data/services/purchase_service.dart';

/// Three-page welcome flow shown once per install.
///   1. Privacy promise — shield hero + 3 checkmark rows
///   2. Features — 4 tool highlights
///   3. Pro trial paywall — plan picker + free-trial CTA
///
/// Vertical rhythm rule (all three pages): two flexible `Spacer()`s
/// sandwich the content cluster — one above, one between content
/// and the bottom dots-button-footer group. The two Spacers split
/// the leftover vertical space evenly, so the cluster sits in the
/// vertical center on tall devices (17 Pro Max) and compresses
/// gracefully on small ones (SE). Every other gap is a fixed
/// `SizedBox`. A "fixed top + flexible bottom" arrangement left a
/// huge dead zone above the CTA on Pro Max.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _page = 0;
  ProSku _selectedSku = ProSku.yearly;
  bool _buying = false;

  // Onboarding-local design tokens; kept off AppColors on purpose so
  // the spec values don't leak into the rest of the app — and so the
  // rest of the app's palette changes don't leak in here.
  //
  // _textPrimary mirrors AppColors.textPrimary (#0F172A) so onboarding
  // typography matches the rest of the app — slate-900, not pure black.
  // The other tokens (_bgCream, _teal, _tealBg, …) stay intentionally
  // distinct because they're brand-isolation decisions.
  static const _bgCream = Color(0xFFF5F4EF);
  static const _tealBg = Color(0xFFE1F5EE);
  static const _teal = Color(0xFF0F6E56);
  static const _textPrimary = Color(0xFF0F172A);
  static const _textSecondary = Color(0xFF6B6B6B);
  static const _textTertiary = Color(0xFF888780);
  static const _dotInactive = Color(0xFFD3D1C7);
  static const _warning = Color(0xFFF59E0B); // mirrors _OnboardingScreenState._warning
  static const _border = Color(0xFFE7E0D2); // mirrors _OnboardingScreenState._border

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    HapticsService.instance.tap();
    await OnboardingService.instance.markSeen();
    widget.onDone();
  }

  void _next() {
    HapticsService.instance.select();
    _pager.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _startTrial() async {
    if (_buying) return;
    HapticsService.instance.tap();
    setState(() => _buying = true);

    // Subscribe to the result stream BEFORE launching the dialog —
    // broadcast streams don't replay history, so if we awaited after
    // buy() we could miss a fast cancel. `.first` returns a Future
    // that resolves on the next event; the listener attaches now.
    final resultFuture = PurchaseService.instance.purchaseResults.first
        .timeout(
          const Duration(minutes: 5),
          onTimeout: () => PurchaseResult.error,
        );

    // 1. Launch the StoreKit dialog. `buy()` returns true once the
    //    dialog is *shown*, not when the purchase actually completes —
    //    a `false` here means we couldn't even surface one (StoreKit
    //    unreachable, SKU not provisioned in ASC, etc.).
    final launched = await PurchaseService.instance.buy(_selectedSku);
    if (!mounted) return;
    if (!launched) {
      setState(() => _buying = false);
      _showTrialError(
        "Couldn't start the trial. Check your connection, or tap × to skip.",
      );
      return;
    }

    // 2. Wait for a terminal event from the purchase stream. Cancel
    //    fires immediately when the user taps Cancel on the Apple ID
    //    sheet — no 60-second timeout needed. The 5-minute outer
    //    timeout is just a safety net for genuinely stuck transactions.
    final result = await resultFuture;
    if (!mounted) return;
    setState(() => _buying = false);

    if (result != PurchaseResult.success || !PurchaseService.instance.hasPro) {
      _showTrialError(
        result == PurchaseResult.canceled
            ? 'Trial cancelled. Tap Start to try again, or × to skip.'
            : "Trial didn't activate. Try again, or tap × to skip.",
      );
      return;
    }

    HapticsService.instance.success();
    await _finish();
  }

  void _showTrialError(String message) {
    HapticsService.instance.error();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _openTerms() async {
    HapticsService.instance.tap();
    final uri = Uri.parse(
        'https://mustafasalimerek-bit.github.io/pdfprivio/terms/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openPrivacy() async {
    HapticsService.instance.tap();
    final uri = Uri.parse(
        'https://mustafasalimerek-bit.github.io/pdfprivio/privacy/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgCream,
      body: SafeArea(
        child: PageView(
          controller: _pager,
          onPageChanged: (i) => setState(() => _page = i),
          children: [
            PrivacyPromiseView(
              currentPage: _page,
              onContinue: _next,
            ),
            FeaturesShowcaseView(
              currentPage: _page,
              onContinue: _next,
            ),
            TrialPaywallView(
              currentPage: _page,
              selectedSku: _selectedSku,
              busy: _buying,
              onSelectSku: (sku) {
                HapticsService.instance.select();
                setState(() => _selectedSku = sku);
              },
              onStartTrial: _startTrial,
              onSkip: _finish,
              onRestore: PurchaseService.instance.restorePurchases,
              onTerms: _openTerms,
              onPrivacy: _openPrivacy,
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacyPromiseView extends StatelessWidget {
  final int currentPage;
  final VoidCallback onContinue;
  const PrivacyPromiseView({
    super.key,
    required this.currentPage,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _OnboardingScreenState._tealBg,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _OnboardingScreenState._teal.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
                spreadRadius: -4,
              ),
            ],
          ),
          child: const Icon(
            Icons.security,
            size: 42,
            color: _OnboardingScreenState._teal,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Your documents stay private',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: _OnboardingScreenState._textPrimary,
            height: 1.2,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Everything happens on your ${Breakpoints.deviceNoun(context)}.\nNothing goes to the cloud.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: _OnboardingScreenState._textSecondary,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 70),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CheckRow('No cloud uploads'),
              SizedBox(height: 16),
              _CheckRow('No tracking, ever'),
              SizedBox(height: 16),
              _CheckRow('On-device AI only'),
            ],
          ),
        ),
        const Spacer(),
        _PageDots(current: currentPage, total: 3),
        const SizedBox(height: 14),
        _PrimaryButton(label: 'Continue', onPressed: onContinue),
        const SizedBox(height: 8),
      ],
    );
  }
}

class FeaturesShowcaseView extends StatelessWidget {
  final int currentPage;
  final VoidCallback onContinue;
  const FeaturesShowcaseView({
    super.key,
    required this.currentPage,
    required this.onContinue,
  });

  static const _features = <_Feature>[
    _Feature(
      icon: Icons.crop_free,
      title: 'Scan with auto-edge',
      subtitle: 'Camera to PDF instantly',
    ),
    _Feature(
      icon: Icons.draw,
      title: 'Sign and fill forms',
      subtitle: 'Contracts, NDAs, tax',
    ),
    _Feature(
      icon: Icons.find_in_page,
      title: 'Search any document',
      subtitle: 'On-device OCR',
    ),
    _Feature(
      icon: Icons.content_copy,
      title: 'Merge and compress',
      subtitle: 'Email-ready in one tap',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(),
        const Text(
          'Everything PDF, offline',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: _OnboardingScreenState._textPrimary,
            height: 1.2,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '23 tools · 18 free forever',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: _OnboardingScreenState._textSecondary,
          ),
        ),
        const SizedBox(height: 36),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              for (var i = 0; i < _features.length; i++) ...[
                _FeatureRow(feature: _features[i]),
                if (i != _features.length - 1) const SizedBox(height: 20),
              ],
            ],
          ),
        ),
        const Spacer(),
        _PageDots(current: currentPage, total: 3),
        const SizedBox(height: 14),
        _PrimaryButton(label: 'Continue', onPressed: onContinue),
        const SizedBox(height: 8),
      ],
    );
  }
}

class TrialPaywallView extends StatelessWidget {
  final int currentPage;
  final ProSku selectedSku;
  final ValueChanged<ProSku> onSelectSku;
  final bool busy;
  final VoidCallback onStartTrial;
  final VoidCallback onSkip;
  final VoidCallback onRestore;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  const TrialPaywallView({
    super.key,
    required this.currentPage,
    required this.selectedSku,
    required this.onSelectSku,
    required this.busy,
    required this.onStartTrial,
    required this.onSkip,
    required this.onRestore,
    required this.onTerms,
    required this.onPrivacy,
  });

  String _yearlyPerMonth() {
    final p = PurchaseService.instance.productFor(ProSku.yearly);
    if (p == null) return PriceFallbacks.yearlyPerMonth;
    final raw = p.rawPrice / 12.0;
    final symbol = p.currencySymbol;
    return '$symbol${raw.toStringAsFixed(2)}';
  }

  String _monthlyPrice() {
    final p = PurchaseService.instance.productFor(ProSku.monthly);
    if (p == null) return PriceFallbacks.monthly;
    return p.price;
  }

  String _yearlyTotal() {
    final p = PurchaseService.instance.productFor(ProSku.yearly);
    if (p == null) return PriceFallbacks.yearlyWithYearSuffix;
    return '${p.price}/yr';
  }

  String _lifetimePrice() {
    final p = PurchaseService.instance.productFor(ProSku.lifetime);
    if (p == null) return PriceFallbacks.lifetime;
    return p.price;
  }

  String _ctaLabel() {
    switch (selectedSku) {
      case ProSku.yearly:
      case ProSku.monthly:
        return 'Start 7-day free trial';
      case ProSku.lifetime:
        return 'Buy lifetime';
    }
  }

  String _footerLine() {
    switch (selectedSku) {
      case ProSku.yearly:
        return '7 days free, then ${_yearlyTotal()}';
      case ProSku.monthly:
        return '7 days free, then ${_monthlyPrice()}/mo';
      case ProSku.lifetime:
        return '${_lifetimePrice()} one-time · no renewal';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // X close button — Apple App Review compliance.
        SizedBox(
          height: 44,
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: _OnboardingScreenState._textTertiary,
                ),
                tooltip: 'Skip',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                onPressed: onSkip,
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
        const Spacer(),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _OnboardingScreenState._tealBg,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _OnboardingScreenState._teal.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
                spreadRadius: -4,
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome,
            size: 40,
            color: _OnboardingScreenState._teal,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Try Pro free for 7 days',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: _OnboardingScreenState._textPrimary,
            height: 1.2,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Unlock everything. Cancel anytime.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: _OnboardingScreenState._textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              _PriceCard(
                label: 'Yearly',
                badge: 'SAVE 33%',
                priceLine: '${_yearlyPerMonth()}/mo',
                secondaryLine: '${_yearlyTotal()} billed yearly',
                selected: selectedSku == ProSku.yearly,
                onTap: () => onSelectSku(ProSku.yearly),
              ),
              const SizedBox(height: 10),
              _PriceCard(
                label: 'Monthly',
                priceLine: '${_monthlyPrice()}/mo',
                secondaryLine: 'Cancel anytime',
                selected: selectedSku == ProSku.monthly,
                onTap: () => onSelectSku(ProSku.monthly),
              ),
              const SizedBox(height: 10),
              _PriceCard(
                label: 'Lifetime',
                priceLine: _lifetimePrice(),
                secondaryLine: 'One-time · no renewal',
                selected: selectedSku == ProSku.lifetime,
                onTap: () => onSelectSku(ProSku.lifetime),
              ),
            ],
          ),
        ),
        const Spacer(),
        _PageDots(current: currentPage, total: 3),
        const SizedBox(height: 14),
        _PrimaryButton(
          label: _ctaLabel(),
          onPressed: busy ? null : onStartTrial,
          busy: busy,
        ),
        const SizedBox(height: 14),
        Text(
          _footerLine(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: _OnboardingScreenState._textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        // Restore · Terms · Privacy on one line.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _InlineLink('Restore', onRestore),
            const _InlineDot(),
            _InlineLink('Terms', onTerms),
            const _InlineDot(),
            _InlineLink('Privacy', onPrivacy),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  const _CheckRow(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.check,
          size: 14,
          color: _OnboardingScreenState._teal,
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: _OnboardingScreenState._textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Feature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _FeatureRow extends StatelessWidget {
  final _Feature feature;
  const _FeatureRow({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _OnboardingScreenState._tealBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            feature.icon,
            size: 24,
            color: _OnboardingScreenState._teal,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                feature.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: _OnboardingScreenState._textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                feature.subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: _OnboardingScreenState._textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  final int current;
  final int total;
  const _PageDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == current
                  ? _OnboardingScreenState._teal
                  : _OnboardingScreenState._dotInactive,
              shape: BoxShape.circle,
            ),
          ),
          if (i != total - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: _OnboardingScreenState._teal,
            disabledBackgroundColor:
                _OnboardingScreenState._teal.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.2,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  final String label;
  final String priceLine;
  final String? secondaryLine;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _PriceCard({
    required this.label,
    required this.priceLine,
    this.secondaryLine,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? _OnboardingScreenState._tealBg
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _OnboardingScreenState._teal
                  : _OnboardingScreenState._border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _OnboardingScreenState._textSecondary,
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
                              color: _OnboardingScreenState._warning,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      priceLine,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _OnboardingScreenState._textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (secondaryLine != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        secondaryLine!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _OnboardingScreenState._textTertiary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected
                      ? _OnboardingScreenState._teal
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? _OnboardingScreenState._teal
                        : _OnboardingScreenState._border,
                    width: 1.5,
                  ),
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 13)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _InlineLink(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _OnboardingScreenState._teal,
          ),
        ),
      ),
    );
  }
}

class _InlineDot extends StatelessWidget {
  const _InlineDot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          color: _OnboardingScreenState._dotInactive,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
