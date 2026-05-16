import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_service.dart';

/// Per-tool daily usage caps for the free tier.
///
/// Bumping any of these requires no code change elsewhere — we centralise
/// the table so pricing experiments stay surgical.
class ToolLimits {
  /// Daily allowance for tools that have a free-with-limit policy.
  /// Tools NOT in this map are either always-free (none today) or
  /// Pro-only (listed in `proOnlyTools` below).
  static const Map<String, int> dailyFree = {
    'merge': 3,
    'split': 3,
    'compress': 5,
    'image_to_pdf': 3,
    'rotate': 5,
    'delete_pages': 5,
    'sign': 1,
    'extract_text': 3,
    'compare': 1,
    'scan_to_pdf': 1, // additionally page-capped at 5 in the scan flow
    'ocr_pdf': 1, // additionally page-capped at 3 in the ocr flow
    'watermark': 2,
    'password': 1,
    'page_numbers': 3,
    'pii_scan': 2,
  };

  /// Tools that are fully Pro-locked — no free uses, paywall on first
  /// tap. Each one is high-leverage for the lawyer/CPA wedge:
  ///   * form_fill — kills filling IRS/USCIS forms by hand
  ///   * bates — niche but mandatory for legal discovery
  ///   * redact — wrong usage = client leak, only paying customers
  static const Set<String> proOnly = {
    'form_fill',
    'bates',
    'redact',
  };

  /// Optional page-count guardrail on top of the daily cap. Keeps free
  /// tier from chewing through 200-page court filings on a single use.
  static const Map<String, int> freePageCap = {
    'scan_to_pdf': 5,
    'ocr_pdf': 3,
  };
}

class UsageState {
  final int used;
  final int allowance;
  final DateTime resetsAt;

  const UsageState({
    required this.used,
    required this.allowance,
    required this.resetsAt,
  });

  int get remaining => (allowance - used).clamp(0, allowance);
  bool get canUse => remaining > 0;
}

class UsageLimitsService {
  UsageLimitsService._();
  static final UsageLimitsService instance = UsageLimitsService._();

  static const String _keyPrefix = 'pdfprivio.usage.v1';

  final _controller = StreamController<String>.broadcast();
  Stream<String> get changes => _controller.stream;

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  String _counterKey(String toolId) =>
      '$_keyPrefix.$toolId.${_todayKey()}';

  DateTime _tomorrowMidnightLocal() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  /// Returns the user's remaining uses for [toolId] today.
  Future<UsageState> stateFor(String toolId) async {
    final allowance = ToolLimits.dailyFree[toolId] ?? 0;
    if (allowance == 0) {
      // No allowance configured means Pro-only — represent as zero used,
      // zero allowance so UI shows the lock state coherently.
      return UsageState(
        used: 0,
        allowance: 0,
        resetsAt: _tomorrowMidnightLocal(),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_counterKey(toolId)) ?? 0;
    return UsageState(
      used: used,
      allowance: allowance,
      resetsAt: _tomorrowMidnightLocal(),
    );
  }

  /// Pro users bypass every check. Free users with remaining quota get
  /// `true`; over-quota free users get `false`.
  Future<bool> canUse(String toolId) async {
    if (PurchaseService.instance.hasPro) return true;
    if (ToolLimits.proOnly.contains(toolId)) return false;
    final state = await stateFor(toolId);
    return state.canUse;
  }

  /// Bump the counter for [toolId] by one. Caller invokes this AFTER a
  /// successful operation so a failed/cancelled run doesn't burn a use.
  /// No-op for Pro users.
  Future<void> recordUse(String toolId) async {
    if (PurchaseService.instance.hasPro) return;
    if (!ToolLimits.dailyFree.containsKey(toolId)) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _counterKey(toolId);
    final cur = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, cur + 1);
    await _gcOldKeys(prefs, toolId);
    _controller.add(toolId);
  }

  /// Sweep counters older than today so shared_preferences doesn't grow
  /// unbounded over months. Called opportunistically after each record.
  Future<void> _gcOldKeys(SharedPreferences prefs, String toolId) async {
    final today = _todayKey();
    final prefix = '$_keyPrefix.$toolId.';
    final keys = prefs.getKeys();
    for (final k in keys) {
      if (k.startsWith(prefix) && !k.endsWith(today)) {
        await prefs.remove(k);
      }
    }
  }

  /// Debug helper for emptying every counter (e.g. when a tester wants
  /// to verify the limit dialog repeatedly without waiting for midnight).
  Future<void> resetAllForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
    _controller.add('__reset__');
  }

  /// Wipe usage rows from previous days at app boot. Without this we
  /// accumulate one shared_preferences entry per tool per day forever.
  /// Public counterpart to the per-tool sweep in `recordUse`.
  Future<void> pruneOldEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final stale = prefs
        .getKeys()
        .where((k) =>
            k.startsWith('$_keyPrefix.') && !k.endsWith('.$today'))
        .toList();
    for (final k in stale) {
      await prefs.remove(k);
    }
  }
}
