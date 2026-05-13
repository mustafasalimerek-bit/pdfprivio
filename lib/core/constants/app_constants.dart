class AppConstants {
  AppConstants._();

  static const String appName = 'PDFKitsy';
  static const String appTagline = 'Offline PDF tools. No subscription.';

  // Legal URLs (will live under erekstudio-legal GitHub Pages once created)
  static const String privacyPolicyUrl =
      'https://mustafasalimerek-bit.github.io/erekstudio-legal/pdfkitsy/privacy_en.html';
  static const String termsOfServiceUrl =
      'https://mustafasalimerek-bit.github.io/erekstudio-legal/pdfkitsy/terms_en.html';

  // Apple App Store ID — set after ASC app is created
  static const String appStoreId = '';
  // Google Play Store package
  static const String playStorePackage = 'com.erekstudio.pdfkitsy';

  // IAP product IDs — same across stores so client code does not branch
  static const String iapLifetimeProductId = 'pdfkitsy_pro_lifetime';
  static const String iapMonthlyProductId = 'pdfkitsy_pro_monthly';
  static const String iapYearlyProductId = 'pdfkitsy_pro_yearly';
}
