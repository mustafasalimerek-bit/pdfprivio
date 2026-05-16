import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EntitlementTier { free, pro }

/// One of the three SKUs we sell. The tier they unlock is the same —
/// monthly and yearly are auto-renewable subscriptions inside one ASC
/// subscription group, lifetime is a separate non-consumable.
enum ProSku { monthly, yearly, lifetime }

extension ProSkuIds on ProSku {
  String get productId {
    switch (this) {
      case ProSku.monthly:
        return PurchaseService.proMonthlyId;
      case ProSku.yearly:
        return PurchaseService.proYearlyId;
      case ProSku.lifetime:
        return PurchaseService.proLifetimeId;
    }
  }
}

/// One-stop shop for Pro entitlement + StoreKit interactions.
///
/// We sell three SKUs that all unlock the same feature set:
///   * `pro_monthly`  — $4.99/mo auto-renewable subscription
///   * `pro_yearly`   — $39.99/yr auto-renewable subscription (anchor)
///   * `pro_lifetime` — $79.99 one-time non-consumable
///
/// Why three? Different commitment levels for different customers:
/// casual users start monthly, pro users go yearly for the discount,
/// power users buy lifetime to never see a renewal screen again.
///
/// Entitlement is cached in shared_preferences as a coarse "has Pro"
/// boolean. The source of truth is the StoreKit purchase stream —
/// every cold start calls `restorePurchases()` so a re-install or new
/// device picks up the entitlement automatically. Receipt verification
/// is trust-Apple (no back-end, on-device wedge); for a $4.99–$79.99
/// SKU on jailbroken devices, the abuse risk is small enough that the
/// privacy upside of a serverless design wins.
class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  static const String proMonthlyId = 'com.erekstudio.pdfprivio.pro_monthly';
  static const String proYearlyId = 'com.erekstudio.pdfprivio.pro_yearly';
  static const String proLifetimeId = 'com.erekstudio.pdfprivio.pro_lifetime';
  static const Set<String> _allProductIds = {
    proMonthlyId,
    proYearlyId,
    proLifetimeId,
  };

  static const String _prefsKey = 'pdfprivio.pro.v1';
  static const String _prefsActiveSkuKey = 'pdfprivio.pro.active_sku.v1';

  final InAppPurchase _iap = InAppPurchase.instance;

  bool _initialized = false;
  bool _available = false;
  bool _hasPro = false;
  ProSku? _activeSku;
  final Map<ProSku, ProductDetails> _products = {};

  final _controller = StreamController<EntitlementTier>.broadcast();
  Stream<EntitlementTier> get entitlementChanges => _controller.stream;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool get isStoreAvailable => _available;
  bool get hasPro => _hasPro;
  EntitlementTier get tier =>
      _hasPro ? EntitlementTier.pro : EntitlementTier.free;
  ProSku? get activeSku => _activeSku;
  ProductDetails? productFor(ProSku sku) => _products[sku];
  bool get productsLoaded => _products.isNotEmpty;

  /// One-shot init. Safe to call multiple times — second call is a no-op.
  /// Call from app bootstrap before any UI reads `hasPro`.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Read cached entitlement immediately so UI doesn't flicker from
    // "free" to "pro" while StoreKit round-trips.
    _hasPro = await _readCachedEntitlement();
    _activeSku = await _readActiveSku();
    _controller.add(tier);

    try {
      _available = await _iap.isAvailable();
    } catch (e) {
      if (kDebugMode) debugPrint('IAP isAvailable failed: $e');
      _available = false;
    }

    if (!_available) return;

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _purchaseSub?.cancel(),
      onError: (error) {
        if (kDebugMode) debugPrint('Purchase stream error: $error');
      },
    );

    await _loadProducts();
    // Silent restore on cold start so re-installs and new devices pick
    // up entitlement without manual "Restore" tap. Apple HIG also wants
    // an explicit Restore button, which we expose in Settings + Pro tab.
    await _iap.restorePurchases();
  }

  Future<void> _loadProducts() async {
    try {
      final res = await _iap.queryProductDetails(_allProductIds);
      if (res.productDetails.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'No IAP products returned. Did you create the three SKUs in '
            'ASC with these exact identifiers?\n'
            '  $proMonthlyId\n  $proYearlyId\n  $proLifetimeId',
          );
        }
        return;
      }
      for (final p in res.productDetails) {
        final sku = _skuFor(p.id);
        if (sku != null) _products[sku] = p;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('queryProductDetails failed: $e');
    }
  }

  /// Kick off a purchase. Returns false if StoreKit isn't reachable or
  /// the SKU hasn't been provisioned in ASC. The UI then listens on
  /// `entitlementChanges` for the success / failure event from the
  /// purchase stream.
  Future<bool> buy(ProSku sku) async {
    if (!_available) return false;
    var product = _products[sku];
    if (product == null) {
      await _loadProducts();
      product = _products[sku];
      if (product == null) return false;
    }
    final param = PurchaseParam(productDetails: product);
    try {
      if (sku == ProSku.lifetime) {
        return await _iap.buyNonConsumable(purchaseParam: param);
      } else {
        return await _iap.buyNonConsumable(purchaseParam: param);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('buy($sku) failed: $e');
      return false;
    }
  }

  /// Apple HIG requires a Restore Purchases button. Exposed from Settings
  /// and from the Pro tab footer.
  Future<void> restorePurchases() async {
    if (!_available) return;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      if (kDebugMode) debugPrint('restorePurchases failed: $e');
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          // Spinner in UI; transaction not yet settled.
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final sku = _skuFor(p.productID);
          if (sku != null) {
            _setPro(true, sku: sku);
          }
          if (p.pendingCompletePurchase) {
            _iap.completePurchase(p);
          }
        case PurchaseStatus.error:
          if (kDebugMode) {
            debugPrint('Purchase error: ${p.error?.message}');
          }
          if (p.pendingCompletePurchase) {
            _iap.completePurchase(p);
          }
        case PurchaseStatus.canceled:
          if (p.pendingCompletePurchase) {
            _iap.completePurchase(p);
          }
      }
    }
  }

  ProSku? _skuFor(String productId) {
    switch (productId) {
      case proMonthlyId:
        return ProSku.monthly;
      case proYearlyId:
        return ProSku.yearly;
      case proLifetimeId:
        return ProSku.lifetime;
      default:
        return null;
    }
  }

  Future<void> _setPro(bool value, {ProSku? sku}) async {
    if (_hasPro == value && _activeSku == sku) return;
    _hasPro = value;
    _activeSku = sku;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    if (sku != null) {
      await prefs.setString(_prefsActiveSkuKey, sku.name);
    } else {
      await prefs.remove(_prefsActiveSkuKey);
    }
    _controller.add(tier);
  }

  Future<bool> _readCachedEntitlement() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<ProSku?> _readActiveSku() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefsActiveSkuKey);
    if (name == null) return null;
    for (final sku in ProSku.values) {
      if (sku.name == name) return sku;
    }
    return null;
  }

  /// Debug-only: flip the entitlement without going through StoreKit.
  /// Useful for screenshotting / developing the unlocked vs locked UI
  /// before ASC sandbox products are ready. No-op in release builds.
  Future<void> setProForTesting(bool value, {ProSku? sku}) async {
    if (!kDebugMode) return;
    await _setPro(value, sku: sku ?? (value ? ProSku.lifetime : null));
  }
}
