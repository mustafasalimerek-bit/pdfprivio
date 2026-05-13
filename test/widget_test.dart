import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdfkitsy/app.dart';

void main() {
  testWidgets('App boots and shows brand title', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PdfKitsyApp()),
    );

    expect(find.text('PDFKitsy'), findsWidgets);
  });
}
