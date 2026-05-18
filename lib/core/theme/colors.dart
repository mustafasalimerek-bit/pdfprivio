import 'package:flutter/material.dart';

/// Privio brand palette. Deep teal — "professional document" feel,
/// intentionally distinct from Squeezly's indigo.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0F766E);
  static const Color primaryDark = Color(0xFF0B5650);
  static const Color primaryLight = Color(0xFF14B8A6);

  // Premium gradient (one-time purchase upsell)
  static const Color premiumGradientStart = Color(0xFFF59E0B);
  static const Color premiumGradientEnd = Color(0xFFEF4444);

  // Cream-toned background — warmer than the cold slate of v1.0.0+3,
  // matches the App Store editorial aesthetic (Bear, Things, Mona)
  // that the home redesign is aiming for.
  static const Color background = Color(0xFFF5F1EA);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE7E0D2);

  // One-shade darker cream used as the home-screen header card
  // background. Reads as a "drop-down sheet" against the regular
  // cream body, gives the greeting + offline pill its own canvas
  // without needing harsh borders.
  static const Color headerCard = Color(0xFFECE6DA);

  // Soft teal-tinted neutral used for the icon containers on grid
  // tiles — pulls the eye to the icon without the harsh contrast of
  // pure white-on-cream.
  static const Color iconTint = Color(0xFFDDEAE6);

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
