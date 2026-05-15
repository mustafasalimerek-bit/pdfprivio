import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdfwork/app.dart';

void main() {
  testWidgets('App boots and shows brand title', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PdfWorkApp()),
    );

    expect(find.text('PDFWork'), findsWidgets);
  });
}
