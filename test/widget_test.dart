import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdfprivio/app.dart';

/// Smoke test for cold-boot rendering.
///
/// main() in production wires Firebase, Hive, path_provider, and a
/// dozen other native plugins that aren't available in a unit test.
/// We stub the one widget tree dependency we actually exercise on the
/// first frame (SharedPreferences for OnboardingService.hasSeenWelcome)
/// and verify that PdfPrivioApp can mount without throwing. That's
/// what catches missing const-constructor issues and bad MaterialApp
/// config, which is most of what regresses without a full e2e harness.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App boots without throwing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PdfPrivioApp()),
    );
    // Let the first frame settle — _BootGate's initState fires async
    // work but we just need a clean tree.
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
