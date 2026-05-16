import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/colors.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/onboarding_service.dart';

/// Three-page welcome carousel shown once per install, before the
/// consent prompts. Sets the tone for the lawyer/CPA wedge: privacy
/// first, all 18 tools free, made for professionals.
class OnboardingScreen extends StatefulWidget {
  /// Called after the user dismisses the onboarding (Skip or finish).
  /// Parent typically navigates to the consent flow / home after this.
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _page = 0;

  static const _pages = <_Page>[
    _Page(
      icon: Icons.picture_as_pdf,
      title: 'Welcome to PDFPrivio',
      lead: 'The PDF toolkit lawyers, CPAs, and pros pick when '
          'Adobe Acrobat feels like overkill.',
      body: '18 tools in one app — scan paper, OCR scans, sign '
          'contracts, redact sensitive data, fill IRS / USCIS forms, '
          'compare versions, and more. No subscription.',
    ),
    _Page(
      icon: Icons.lock_outline,
      title: 'On-device privacy',
      lead: 'Your PDFs never leave this iPhone.',
      body: "Every operation runs locally — OCR, redaction, PII "
          'detection, signature. We do not have servers that receive '
          'your documents. The network panel shows 0 bytes for your '
          'files. Show this to clients with confidence.',
    ),
    _Page(
      icon: Icons.workspaces_outline,
      title: 'Built for daily workflows',
      lead: 'Recent files at the top, no account required.',
      body: "PDFPrivio remembers what you produced — last week's "
          "redacted file is one tap away. Pick from Files, iCloud, "
          'Dropbox, or Drive through the iOS picker. Output goes '
          'wherever you tell it.',
    ),
  ];

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
    if (_page >= _pages.length - 1) {
      _finish();
      return;
    }
    _pager.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _finish,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _PageView(page: _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                children: [
                  _Dots(count: _pages.length, current: _page),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        isLast ? 'Get started' : 'Continue',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (isLast) ...[
                    const SizedBox(height: 12),
                    _LegalAcceptance(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page {
  final IconData icon;
  final String title;
  final String lead;
  final String body;
  const _Page({
    required this.icon,
    required this.title,
    required this.lead,
    required this.body,
  });
}

class _PageView extends StatelessWidget {
  final _Page page;
  const _PageView({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 64, color: AppColors.primary),
          ),
          const SizedBox(height: 32),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            page.lead,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
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
  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 11,
      color: AppColors.textTertiary,
      height: 1.45,
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
            text: 'By tapping Get started you agree to our ',
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
