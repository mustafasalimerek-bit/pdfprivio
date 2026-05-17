/// Display-string fallbacks shown while StoreKit metadata is still
/// loading — or when the device can't reach the App Store (airplane
/// mode, sandbox edge cases). Live prices from `PurchaseService.
/// productFor(...)` always take precedence.
///
/// These MUST match the prices configured in App Store Connect:
///   monthly  → product id `pro_monthly`
///   yearly   → product id `pro_yearly`
///   lifetime → product id `pro_lifetime`
///
/// If you change ASC pricing, update these strings and ship a new
/// build — otherwise users on the slow path see drift.
class PriceFallbacks {
  PriceFallbacks._();

  static const String monthly = '\$4.99';
  static const String yearly = '\$39.99';
  static const String lifetime = '\$79.99';

  /// Yearly broken into a per-month equivalent (~ yearly / 12).
  static const String yearlyPerMonth = '\$3.33';

  static const String yearlyWithYearSuffix = '$yearly/yr';
}
