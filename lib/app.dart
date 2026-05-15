import 'package:flutter/material.dart';

import 'core/theme/colors.dart';
import 'core/theme/theme.dart';
import 'data/services/consent_service.dart';
import 'data/services/onboarding_service.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/root/root_scaffold.dart';

class PdfWorkApp extends StatelessWidget {
  const PdfWorkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDFWork',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _BootGate(),
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
