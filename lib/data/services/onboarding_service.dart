import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has seen the welcome onboarding flow. The
/// onboarding lives BEFORE the GDPR/ATT consent prompts so users can
/// see what PDFPrivio is and why we ask for permissions, instead of
/// being launched straight into a tracking dialog.
class OnboardingService {
  OnboardingService._();
  static final OnboardingService instance = OnboardingService._();

  static const String _key = 'pdfprivio.onboarding_seen.v1';

  Future<bool> hasSeenWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
