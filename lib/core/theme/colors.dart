import 'package:flutter/material.dart';

/// PDFPrivio brand palette. Deep teal — "professional document" feel,
/// intentionally distinct from Squeezly's indigo.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0F766E);
  static const Color primaryDark = Color(0xFF0B5650);
  static const Color primaryLight = Color(0xFF14B8A6);

  // Premium gradient (one-time purchase upsell)
  static const Color premiumGradientStart = Color(0xFFF59E0B);
  static const Color premiumGradientEnd = Color(0xFFEF4444);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE2E8F0);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);

  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // Tier badges shown next to features so users see paywall status up-front.
  static const Color freeBadge = Color(0xFF10B981);
  static const Color proBadge = Color(0xFFF59E0B);
}
