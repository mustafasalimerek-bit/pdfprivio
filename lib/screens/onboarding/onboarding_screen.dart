import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/colors.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/onboarding_service.dart';
import '../../data/services/purchase_service.dart';

/// Three-page welcome flow shown once per install before any consent
/// prompts. Sequence is fixed:
///   1. Privacy promise — shield hero + 3 checkmark rows
///   2. Features — 4 tool highlights
///   3. Pro trial paywall — plan picker + "Start 7-day free trial"
///
/// Only Page 3 carries an X dismiss (Apple App Review compliance);
/// Page 1 + 2 require the user to tap Continue or swipe forward.
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

  // Onboarding-local design tokens. Kept local on purpose: the rest
  // of the app already has its own palette, and the spec calls for
  // pixel-specific values that should not leak into every screen.
  static const _bgCream = Color(0xFFF5F4EF);
  static const _tealBg = Color(0xFFE1F5EE);
  static const _teal = Color(0xFF0F6E56);
  static const _textPrimary = Color(0xFF000000);
  static const _textSecondary = Color(0xFF6B6B6B);
  static const _textTertiary = Color(0xFF888780);
  static const _dotInactive = Color(0xFFD3D1C7);

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
    final ok = await PurchaseService.instance.buy(_selectedSku);
    if (!mounted) return;
    setState(() => _buying = false);
    if (ok) HapticsService.instance.success();
    await _finish();
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Page 1 — privacy promise. Shield hero + 3 leading-aligned check
/// rows, then dots + Continue at the bottom.
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
        const SizedBox(height: 40),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _OnboardingScreenState._tealBg,
            borderRadius: BorderRadius.circular(22),
          ),
          // checkmark.shield.fill equivalent — Material doesn't ship the
          // exact SF Symbol but Icons.security gives the same "shield
          // with check inside" silhouette in filled style.
          child: const Icon(
            Icons.security,
            size: 38,
            color: _OnboardingScreenState._teal,
          ),
        ),
        const SizedBox(height: 22),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            'Your documents stay private',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: _OnboardingScreenState._textPrimary,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 60),
          child: Text(
            'Everything happens on your iPhone. Nothing goes to the cloud.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: _OnboardingScreenState._textSecondary,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 26),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CheckRow('No cloud uploads'),
              SizedBox(height: 12),
              _CheckRow('No tracking, ever'),
              SizedBox(height: 12),
              _CheckRow('On-device AI only'),
            ],
          ),
        ),
        const Spacer(),
        _PageDots(current: currentPage, total: 3),
        const SizedBox(height: 14),
        _ContinueButton(label: 'Continue', onPressed: onContinue),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Page 2 — feature showcase. 4 icon-tile rows centered vertically.
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
        const SizedBox(height: 28),
        const Text(
          'Everything PDF, offline',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: _OnboardingScreenState._textPrimary,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '10+ pro tools in your pocket',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: _OnboardingScreenState._textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            children: [
              for (var i = 0; i < _features.length; i++) ...[
                _FeatureRow(feature: _features[i]),
                if (i != _features.length - 1) const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        const Spacer(),
        _PageDots(current: currentPage, total: 3),
        const SizedBox(height: 14),
        _ContinueButton(label: 'Continue', onPressed: onContinue),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Page 3 — Pro trial paywall. Sparkles hero, plan picker, "Start
/// 7-day free trial" CTA, and an X in the top-right so the user
/// can dismiss without buying (Apple App Review compliance).
class TrialPaywallView extends StatelessWidget {
  final int currentPage;
  final ProSku selectedSku;
  final ValueChanged<ProSku> onSelectSku;
  final bool busy;
  final VoidCallback onStartTrial;
  final VoidCallback onSkip;

  const TrialPaywallView({
    super.key,
    required this.currentPage,
    required this.selectedSku,
    required this.onSelectSku,
    required this.busy,
    required this.onStartTrial,
    required this.onSkip,
  });

  String _yearlyPerMonth() {
    final p = PurchaseService.instance.productFor(ProSku.yearly);
    if (p == null) return '\$3.33';
    final raw = p.rawPrice / 12.0;
    final symbol = p.currencySymbol;
    return '$symbol${raw.toStringAsFixed(2)}';
  }

  String _monthlyPrice() {
    final p = PurchaseService.instance.productFor(ProSku.monthly);
    if (p == null) return '\$4.99';
    return p.price;
  }

  String _yearlyTotal() {
    final p = PurchaseService.instance.productFor(ProSku.yearly);
    if (p == null) return '\$39.99/yr';
    return '${p.price}/yr';
  }

  String _lifetimePrice() {
    final p = PurchaseService.instance.productFor(ProSku.lifetime);
    if (p == null) return '\$79.99';
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
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 36),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _OnboardingScreenState._tealBg,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 38,
                color: _OnboardingScreenState._teal,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Try Pro free for 7 days',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: _OnboardingScreenState._textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Unlock everything. Cancel anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: _OnboardingScreenState._textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _PriceCard(
                label: 'Yearly',
                badge: 'SAVE 33%',
                priceLine: '${_yearlyPerMonth()}/mo',
                secondaryLine: '${_yearlyTotal()} billed yearly',
                selected: selectedSku == ProSku.yearly,
                onTap: () => onSelectSku(ProSku.yearly),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _PriceCard(
                label: 'Monthly',
                priceLine: '${_monthlyPrice()}/mo',
                secondaryLine: 'Cancel anytime',
                selected: selectedSku == ProSku.monthly,
                onTap: () => onSelectSku(ProSku.monthly),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _PriceCard(
                label: 'Lifetime',
                priceLine: _lifetimePrice(),
                secondaryLine: 'One-time · no renewal',
                selected: selectedSku == ProSku.lifetime,
                onTap: () => onSelectSku(ProSku.lifetime),
              ),
            ),
            const Spacer(),
            _PageDots(current: currentPage, total: 3),
            const SizedBox(height: 14),
            _ContinueButton(
              label: busy ? '' : _ctaLabel(),
              onPressed: busy ? null : onStartTrial,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.2,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              _footerLine(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: _OnboardingScreenState._textTertiary,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: PurchaseService.instance.restorePurchases,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
              ),
              child: const Text(
                'Restore purchase',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _OnboardingScreenState._teal,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const _LegalAcceptance(),
            const SizedBox(height: 8),
          ],
        ),
        // X dismiss in the top-right — Apple App Review requires
        // paywall screens to be skippable. Only present on Page 3.
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            icon: const Icon(
              Icons.close,
              size: 22,
              color: _OnboardingScreenState._textSecondary,
            ),
            tooltip: 'Skip',
            onPressed: onSkip,
          ),
        ),
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
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _OnboardingScreenState._tealBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            feature.icon,
            size: 20,
            color: _OnboardingScreenState._teal,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                feature.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _OnboardingScreenState._textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                feature.subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: _OnboardingScreenState._textTertiary,
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

/// Page indicator — 3 dots, 6×6pt, 5pt spacing. Active brandTeal,
/// inactive brandBorder-ish neutral cream. iOS PageView's built-in
/// indicator can't be styled to the spec colors so this is custom.
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

/// Continue / primary CTA — rounded rectangle (14pt radius), not a
/// capsule. Matches the spec exactly.
class _ContinueButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? child;
  const _ContinueButton({
    required this.label,
    required this.onPressed,
    this.child,
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
          child: child ??
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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
          ? _OnboardingScreenState._teal.withValues(alpha: 0.06)
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
                  : AppColors.border,
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
                            fontSize: 12,
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
                              color: AppColors.warning,
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
                    const SizedBox(height: 2),
                    Text(
                      priceLine,
                      style: const TextStyle(
                        fontSize: 17,
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
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: selected
                      ? _OnboardingScreenState._teal
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? _OnboardingScreenState._teal
                        : AppColors.border,
                    width: 1.5,
                  ),
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 12)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalAcceptance extends StatelessWidget {
  const _LegalAcceptance();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontSize: 10,
      color: _OnboardingScreenState._textTertiary,
      height: 1.4,
      fontWeight: FontWeight.w400,
    );
    final linkStyle = baseStyle.copyWith(
      color: _OnboardingScreenState._teal,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'By continuing you agree to our '),
            TextSpan(
              text: 'Terms',
              style: linkStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () => _open(
                    'https://mustafasalimerek-bit.github.io/pdfprivio/terms/'),
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: linkStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () => _open(
                    'https://mustafasalimerek-bit.github.io/pdfprivio/privacy/'),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}
