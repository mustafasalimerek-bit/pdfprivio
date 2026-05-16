import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_service.dart';

enum PromoRedeemResult {
  success,
  invalidCode,
  alreadyRedeemed,
}

/// Promotional access layer that runs alongside (not instead of) StoreKit.
///
/// Apple subscription offer codes and Google Play promo codes both
/// convert to a paid auto-renewal after the free window ends. We need a
/// time-bounded grant that drops the user back to free tier when it
/// expires, with zero billing involvement. Apple's review rules permit
/// promotional unlocks (beta, marketing, conference giveaways) as long
/// as no money changes hands outside IAP — so we run our own redemption.
///
/// ## Abuse model
///
/// Hard limit: **one redemption per device, ever** (no stacking). To
/// stop "uninstall and re-redeem" abuse, the redemption flag is mirrored
/// to flutter_secure_storage with `synchronizable: true`, which on iOS
/// writes through iCloud Keychain. That gives us two layers without a
/// backend:
///
/// - **Per-device**: Keychain (iOS) / EncryptedSharedPreferences
///   (Android) survives app uninstall on iOS. Android still wipes on
///   "Clear app data" — acceptable asymmetry since the paid tier lives
///   on iOS and Android revenue is mostly AdMob.
/// - **Per-Apple-ID**: iCloud Keychain syncs the flag across the user's
///   devices on the same Apple ID. iPhone redeems → iPad sees the flag
///   within seconds. No entitlement or container config required —
///   `synchronizable: true` is enough.
///
/// Entitlement is OR-gated with StoreKit Pro inside PurchaseService —
/// real subscribers are unaffected by promo state, and an active promo
/// upgrades a free user transparently.
class PromoCodeService {
  PromoCodeService._();
  static final PromoCodeService instance = PromoCodeService._();

  // Marketing campaign codes. Each redemption grants 14 days of Pro
  // with no conversion to paid. Per-channel naming so analytics tells
  // us which campaign converts (tag promo_redeemed events with the code).
  //
  // To add/retire codes: change this set and ship a release.
  static const Set<String> _validCodes = {
    'LAWYER14', // r/Lawyertalk, LinkedIn legal groups
    'CPA14', // r/Accounting, AICPA Twitter
    'PHLAUNCH', // ProductHunt launch day
    'BETA2026', // TestFlight beta tester thank-you
    'INFLUENCE', // Influencer giveaway
  };

  static const String _expiryKey = 'pdfprivio.promo.expiry_ms.v1';
  static const String _redeemedAtKey = 'pdfprivio.promo.redeemed_at_ms.v1';
  static const String _redeemedCodesKey = 'pdfprivio.promo.redeemed.v1';

  static const Duration _grantDuration = Duration(days: 14);

  // first_unlock (NOT first_unlock_this_device_only) is the prerequisite
  // for iCloud Keychain sync. Combined with `synchronizable: true`, the
  // Keychain entry replicates across the user's iOS devices on the same
  // Apple ID.
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
      synchronizable: true,
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _inited = false;
  DateTime? _expiry;

  final _controller = StreamController<bool>.broadcast();

  /// Fires when promo state changes (redeem / clear). PurchaseService
  /// also bridges this onto its own entitlement stream so widgets that
  /// already listen to PurchaseService.entitlementChanges see promo
  /// activations without subscribing twice.
  Stream<bool> get changes => _controller.stream;

  /// One-shot init. Reads both shared_prefs (fast-path cache) and
  /// secure storage (durable across uninstall + Apple ID-scoped on iOS)
  /// and reconciles them — secure storage wins if there's a conflict
  /// because that's our source of truth for abuse-prevention.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    final prefs = await SharedPreferences.getInstance();
    final prefsExpiry = prefs.getInt(_expiryKey);
    final prefsRedeemed = prefs.getStringList(_redeemedCodesKey) ?? const [];

    final secureExpiryStr = await _readSecure(_expiryKey);
    final secureExpiry = secureExpiryStr == null
        ? null
        : int.tryParse(secureExpiryStr);
    final secureRedeemedStr = await _readSecure(_redeemedCodesKey);
    final secureRedeemed = (secureRedeemedStr ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList();

    // Union of both sources — any prior redemption from either store
    // marks this device as already-redeemed.
    final mergedRedeemed = <String>{...prefsRedeemed, ...secureRedeemed};

    // Pick the later expiry so a partial-uninstall mid-promo (Keychain
    // survived, prefs gone) restores remaining time on reinstall.
    int? mergedExpiry;
    if (prefsExpiry != null && secureExpiry != null) {
      mergedExpiry = prefsExpiry > secureExpiry ? prefsExpiry : secureExpiry;
    } else {
      mergedExpiry = prefsExpiry ?? secureExpiry;
    }

    // Reconcile back to both stores so they stay in lockstep.
    if (mergedRedeemed.isNotEmpty) {
      await prefs.setStringList(
        _redeemedCodesKey,
        mergedRedeemed.toList(),
      );
      await _writeSecure(_redeemedCodesKey, mergedRedeemed.join(','));
    }
    if (mergedExpiry != null) {
      await prefs.setInt(_expiryKey, mergedExpiry);
      await _writeSecure(_expiryKey, mergedExpiry.toString());
    }

    _expiry = mergedExpiry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(mergedExpiry);
  }

  /// True when an unexpired promo grant is in effect.
  bool get hasActivePromo {
    final exp = _expiry;
    return exp != null && DateTime.now().isBefore(exp);
  }

  DateTime? get expiresAt => _expiry;

  /// Time until the active promo expires, or null if none is active.
  Duration? get timeLeft {
    final exp = _expiry;
    if (exp == null) return null;
    final diff = exp.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  /// True when this device has ever redeemed a promo (active or expired).
  /// Drives the dialog's "already redeemed" branch and tile copy.
  Future<bool> hasAnyRedemption() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_redeemedCodesKey) ?? const [];
    return list.isNotEmpty;
  }

  /// Attempt to redeem [rawCode]. Per-device strict — one redemption
  /// per device for the lifetime of the app's Apple ID. Subsequent
  /// attempts (same or different codes) return `alreadyRedeemed`.
  Future<PromoRedeemResult> redeem(String rawCode) async {
    final code = rawCode.trim().toUpperCase().replaceAll(' ', '');
    if (!_validCodes.contains(code)) {
      return PromoRedeemResult.invalidCode;
    }

    final prefs = await SharedPreferences.getInstance();
    final redeemed = prefs.getStringList(_redeemedCodesKey) ?? const [];
    if (redeemed.isNotEmpty) {
      return PromoRedeemResult.alreadyRedeemed;
    }

    final now = DateTime.now();
    final newExpiry = now.add(_grantDuration);
    final newList = <String>[code];

    await prefs.setInt(_expiryKey, newExpiry.millisecondsSinceEpoch);
    await prefs.setInt(_redeemedAtKey, now.millisecondsSinceEpoch);
    await prefs.setStringList(_redeemedCodesKey, newList);

    // Mirror to secure storage — survives uninstall on iOS, syncs via
    // iCloud Keychain to the user's other devices on the same Apple ID.
    await _writeSecure(_expiryKey, newExpiry.millisecondsSinceEpoch.toString());
    await _writeSecure(_redeemedCodesKey, code);

    _expiry = newExpiry;
    _controller.add(true);
    PurchaseService.instance.notifyExternalEntitlementChange();

    return PromoRedeemResult.success;
  }

  /// Debug-only escape hatch. Wipes both stores so the redemption flow
  /// can be re-tested on the same device.
  Future<void> clearForTesting() async {
    if (!kDebugMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_expiryKey);
    await prefs.remove(_redeemedAtKey);
    await prefs.remove(_redeemedCodesKey);
    await _deleteSecure(_expiryKey);
    await _deleteSecure(_redeemedCodesKey);
    _expiry = null;
    _controller.add(false);
    PurchaseService.instance.notifyExternalEntitlementChange();
  }

  // ---- Secure-storage helpers ----
  //
  // Keychain reads can throw on first-launch race conditions or when
  // the user has just enabled / disabled iCloud Keychain. Treat any
  // failure as "no value" — we'd rather fall back to per-device-only
  // protection than crash the redeem flow.

  Future<String?> _readSecure(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {
      // Per-device protection still active via shared_prefs.
    }
  }

  Future<void> _deleteSecure(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {
      // No-op.
    }
  }
}
