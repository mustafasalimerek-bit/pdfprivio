import 'package:flutter/material.dart';

import 'core/theme/theme.dart';
import 'screens/home_screen.dart';

class PdfKitsyApp extends StatelessWidget {
  const PdfKitsyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDFKitsy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
