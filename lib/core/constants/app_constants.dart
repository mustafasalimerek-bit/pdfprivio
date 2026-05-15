class AppConstants {
  AppConstants._();

  static const String appName = 'PDFWork';
  static const String appTagline = 'Offline PDF tools. No subscription.';

  // Legal URLs (will live under erekstudio-legal GitHub Pages once created)
  static const String privacyPolicyUrl =
      'https://mustafasalimerek-bit.github.io/erekstudio-legal/pdfwork/privacy_en.html';
  static const String termsOfServiceUrl =
      'https://mustafasalimerek-bit.github.io/erekstudio-legal/pdfwork/terms_en.html';

  // Apple App Store ID (App Store Connect)
  static const String appStoreId = '6769270643';
  // Google Play Store
  static const String playStorePackage = 'com.erekstudio.pdfwork';
  static const String playConsoleAppId = '4976288492451327073';

  // IAP product IDs — same across stores so client code does not branch
  static const String iapLifetimeProductId = 'pdfwork_pro_lifetime';
  static const String iapMonthlyProductId = 'pdfwork_pro_monthly';
  static const String iapYearlyProductId = 'pdfwork_pro_yearly';
}
