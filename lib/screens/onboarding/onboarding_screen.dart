import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/colors.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/onboarding_service.dart';
import '../../data/services/purchase_service.dart';

/// Three-page welcome carousel shown once per install, before any
/// consent prompts. Pages follow the editorial spec:
///   1. Privacy promise — shield + checklist
///   2. Features — 4 tools with icons + one-line subtitles
///   3. Pro trial — yearly/monthly card, "Start free trial" CTA, X
///      to skip the upsell and land on home as a free user.
class OnboardingScreen extends StatefulWidget {
  /// Called after the user dismisses the onboarding (X on Pro page,
  /// successful purchase, or any post-trial flow). Parent typically
  /// navigates to consent / home after this.
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
    // Whether the purchase succeeds, errors, or is cancelled mid-flow,
    // we mark onboarding seen and continue — the user has seen the
    // offer and can revisit it from Settings any time.
    if (ok) HapticsService.instance.success();
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pager,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _PrivacyPage(
                  page: _page,
                  totalPages: 3,
                  onContinue: _next,
                ),
                _FeaturesPage(
                  page: _page,
                  totalPages: 3,
                  onContinue: _next,
                ),
                _TrialPage(
                  selectedSku: _selectedSku,
                  onSelectSku: (sku) {
                    HapticsService.instance.select();
                    setState(() => _selectedSku = sku);
                  },
                  busy: _buying,
                  onStartTrial: _startTrial,
                  onSkip: _finish,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Page 1: privacy promise. Hero + three checkmark rows.
class _PrivacyPage extends StatelessWidget {
  final int page;
  final int totalPages;
  final VoidCallback onContinue;
  const _PrivacyPage({
    required this.page,
    required this.totalPages,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 2),
        const _HeroIcon(icon: Icons.verified_user_outlined),
        const SizedBox(height: 26),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            'Your documents stay private',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            'Everything happens on your iPhone. Nothing goes to the cloud.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 30),
        const _CheckRow('No cloud uploads'),
        const _CheckRow('No tracking, ever'),
        const _CheckRow('On-device AI only'),
        const Spacer(flex: 3),
        _OnboardingFooter(
          page: page,
          totalPages: totalPages,
          buttonLabel: 'Continue',
          onPressed: onContinue,
        ),
      ],
    );
  }
}

/// Page 2: feature list. 4 tool highlights, no hero icon.
class _FeaturesPage extends StatelessWidget {
  final int page;
  final int totalPages;
  final VoidCallback onContinue;
  const _FeaturesPage({
    required this.page,
    required this.totalPages,
    required this.onContinue,
  });

  static const _features = <_Feature>[
    _Feature(
      icon: Icons.document_scanner_outlined,
      title: 'Scan with auto-edge',
      subtitle: 'Camera to PDF instantly',
    ),
    _Feature(
      icon: Icons.draw_outlined,
      title: 'Sign and fill forms',
      subtitle: 'Contracts, NDAs, tax',
    ),
    _Feature(
      icon: Icons.find_in_page_outlined,
      title: 'Search any document',
      subtitle: 'On-device OCR',
    ),
    _Feature(
      icon: Icons.content_copy_outlined,
      title: 'Merge and compress',
      subtitle: 'Email-ready in one tap',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            'Everything PDF, offline',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '10+ pro tools in your pocket',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
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
        _OnboardingFooter(
          page: page,
          totalPages: totalPages,
          buttonLabel: 'Continue',
          onPressed: onContinue,
        ),
      ],
    );
  }
}

/// Page 3: Pro trial offer with three price cards + X to skip.
class _TrialPage extends StatelessWidget {
  final ProSku selectedSku;
  final ValueChanged<ProSku> onSelectSku;
  final bool busy;
  final VoidCallback onStartTrial;
  final VoidCallback onSkip;

  const _TrialPage({
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
        return 'Start free trial';
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
          children: [
            const SizedBox(height: 40),
            const _HeroIcon(icon: Icons.auto_awesome),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'Try Pro free for 7 days',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Unlock everything. Cancel anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _PriceCard(
                label: 'Yearly',
                badge: 'SAVE 33%',
                priceLine: '${_yearlyPerMonth()}/mo',
                secondaryLine: '${_yearlyTotal()} billed yearly',
                selected: selectedSku == ProSku.yearly,
                onTap: () => onSelectSku(ProSku.yearly),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _PriceCard(
                label: 'Monthly',
                priceLine: '${_monthlyPrice()}/mo',
                secondaryLine: 'Cancel anytime',
                selected: selectedSku == ProSku.monthly,
                onTap: () => onSelectSku(ProSku.monthly),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _PriceCard(
                label: 'Lifetime',
                priceLine: _lifetimePrice(),
                secondaryLine: 'One-time · no renewal',
                selected: selectedSku == ProSku.lifetime,
                onTap: () => onSelectSku(ProSku.lifetime),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : onStartTrial,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.45),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        )
                      : Text(
                          _ctaLabel(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _footerLine(),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: PurchaseService.instance.restorePurchases,
              child: const Text(
                'Restore purchase',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const _LegalAcceptance(),
            const SizedBox(height: 12),
          ],
        ),
        // X dismiss in the top-right — only on the trial page so users
        // can skip the upsell and continue to the home screen.
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.close),
            color: AppColors.textSecondary,
            tooltip: 'Skip',
            onPressed: onSkip,
          ),
        ),
      ],
    );
  }
}

class _HeroIcon extends StatelessWidget {
  final IconData icon;
  const _HeroIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        color: AppColors.iconTint,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Icon(icon, size: 52, color: AppColors.primary),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  const _CheckRow(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 6, 48, 6),
      child: Row(
        children: [
          const Icon(Icons.check, color: AppColors.primary, size: 18),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
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
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.iconTint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(feature.icon, color: AppColors.primary, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                feature.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                feature.subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
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
          ? AppColors.primary.withValues(alpha: 0.08)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
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
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (secondaryLine != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        secondaryLine!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
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
                  color: selected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: 1.6,
                  ),
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom dots + pill CTA shared by the first two onboarding pages.
class _OnboardingFooter extends StatelessWidget {
  final int page;
  final int totalPages;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _OnboardingFooter({
    required this.page,
    required this.totalPages,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        children: [
          _Dots(count: totalPages, current: page),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int current;
  const _Dots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
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
    final baseStyle = const TextStyle(
      fontSize: 11,
      color: AppColors.textTertiary,
      height: 1.45,
    );
    final linkStyle = baseStyle.copyWith(
      color: AppColors.primary,
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
      ),
    );
  }
}
