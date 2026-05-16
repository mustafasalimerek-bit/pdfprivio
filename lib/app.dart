import 'package:flutter/material.dart';

import 'core/theme/colors.dart';
import 'core/theme/theme.dart';
import 'data/services/consent_service.dart';
import 'data/services/onboarding_service.dart';
import 'screens/image_to_pdf/image_to_pdf_screen.dart';
import 'screens/merge/merge_screen.dart';
import 'screens/ocr_pdf/ocr_pdf_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/pii_scan/pii_scan_screen.dart';
import 'screens/redact/redact_screen.dart';
import 'screens/root/root_scaffold.dart';
import 'screens/scan/scan_screen.dart';
import 'screens/sign/sign_screen.dart';

class PdfPrivioApp extends StatelessWidget {
  const PdfPrivioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDFPrivio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _BootGate(),
      // Routes for the SharedFileActionSheet (inbound files) and the
      // AppIntents bridge (Siri / Shortcuts triggers). The rest of the
      // app pushes its tool screens with MaterialPageRoute inside
      // HomeScreen — the named routes only exist for system-driven
      // entry points.
      routes: {
        '/tool/sign': (_) => const SignScreen(),
        '/tool/redact': (_) => const RedactScreen(),
        '/tool/merge': (_) => const MergeScreen(),
        '/tool/ocr': (_) => const OcrPdfScreen(),
        '/tool/image_to_pdf': (_) => const ImageToPdfScreen(),
        '/tool/pii': (_) => const PiiScanScreen(),
        '/tool/scan': (_) => const ScanScreen(),
      },
    );
  }
}

/// Sequences the cold-boot UI:
///   1) first-launch onboarding (3-page welcome) if not yet seen
///   2) ConsentService.gather() — UMP + ATT prompts
///   3) HomeScreen
///
/// Each stage gates the next, so the user always sees a coherent flow
/// rather than a stack of prompts piled on top of an interactive UI.
class _BootGate extends StatefulWidget {
  const _BootGate();

  @override
  State<_BootGate> createState() => _BootGateState();
}

enum _BootStage { checking, onboarding, gatheringConsent, ready }

class _BootGateState extends State<_BootGate> {
  _BootStage _stage = _BootStage.checking;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final seen = await OnboardingService.instance.hasSeenWelcome();
    if (!mounted) return;
    if (!seen) {
      setState(() => _stage = _BootStage.onboarding);
      return;
    }
    await _afterOnboarding();
  }

  Future<void> _afterOnboarding() async {
    if (!mounted) return;
    setState(() => _stage = _BootStage.gatheringConsent);
    await ConsentService.instance.gather();
    if (!mounted) return;
    setState(() => _stage = _BootStage.ready);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _BootStage.checking:
      case _BootStage.gatheringConsent:
        return const _BootSplash();
      case _BootStage.onboarding:
        return OnboardingScreen(onDone: _afterOnboarding);
      case _BootStage.ready:
        return const RootScaffold();
    }
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
