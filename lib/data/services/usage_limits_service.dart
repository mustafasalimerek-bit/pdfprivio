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
  ///   * batch — amplifies any tool 50x; the wedge for stacks of
  ///     exhibits/receipts. Free users keep per-tool daily caps.
  ///   * receipt — CPA/freelancer expense ledger. Heuristic field
  ///     extraction + persistent ledger + QuickBooks CSV is the
  ///     buying trigger for the tax-season audience.
  static const Set<String> proOnly = {
    'form_fill',
    'bates',
    'redact',
    'batch',
    'receipt',
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

  /// True for tools with no daily cap (e.g. Bookmarks, Summarize,
  /// Live Text view). The UI uses this to skip the quota pill and
  /// the tap-time paywall — those tools are free unlimited and
  /// shouldn't pretend to be over-quota.
  final bool unlimited;

  const UsageState({
    required this.used,
    required this.allowance,
    required this.resetsAt,
    this.unlimited = false,
  });

  int get remaining => (allowance - used).clamp(0, allowance);
  bool get canUse => unlimited || remaining > 0;
}

class UsageLimitsService {
  UsageLimitsService._();
  static final UsageLimitsService instance = UsageLimitsService._();

  static const String _keyPrefix = 'pdfprivio.usage.v1';
  static const String _lifetimePrefix = 'pdfprivio.lifetime.v1';

  final _controller = StreamController<String>.broadcast();
  Stream<String> get changes => _controller.stream;

  String _lifetimeKey(String toolId) => '$_lifetimePrefix.$toolId';

  /// Lifetime use count for [toolId]. Survives daily resets and Pro
  /// state, so the "Frequent" tools panel surfaces what the user
  /// actually reaches for over months — not just today's caps.
  Future<int> lifetimeCount(String toolId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lifetimeKey(toolId)) ?? 0;
  }

  /// Bulk variant — one read of [SharedPreferences.getKeys] instead of
  /// N round-trips when ranking the whole tool catalog.
  Future<Map<String, int>> lifetimeCountsFor(List<String> toolIds) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final id in toolIds)
        id: prefs.getInt(_lifetimeKey(id)) ?? 0,
    };
  }

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
  ///
  /// Three classes of tool:
  ///   * in [ToolLimits.proOnly] → returns zero/zero (paywall handled
  ///     by `_isProOnly` check in the tile, this state still flags
  ///     `canUse=false` for the lock UI).
  ///   * in [ToolLimits.dailyFree] → metered, returns real usage.
  ///   * neither (Bookmarks, Summarize, Live Text view) → unlimited
  ///     free use, returns `unlimited=true` so the tile shows no
  ///     badge and tap doesn't fire the paywall.
  Future<UsageState> stateFor(String toolId) async {
    if (ToolLimits.proOnly.contains(toolId)) {
      return UsageState(
        used: 0,
        allowance: 0,
        resetsAt: _tomorrowMidnightLocal(),
      );
    }
    final allowance = ToolLimits.dailyFree[toolId];
    if (allowance == null) {
      // Not metered and not Pro-only → free unlimited.
      return UsageState(
        used: 0,
        allowance: 0,
        resetsAt: _tomorrowMidnightLocal(),
        unlimited: true,
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
  /// Daily counter is no-op for Pro users; lifetime counter is bumped
  /// for everyone so the Frequent ranking stays accurate post-upgrade.
  Future<void> recordUse(String toolId) async {
    final prefs = await SharedPreferences.getInstance();
    final lk = _lifetimeKey(toolId);
    await prefs.setInt(lk, (prefs.getInt(lk) ?? 0) + 1);
    if (!PurchaseService.instance.hasPro &&
        ToolLimits.dailyFree.containsKey(toolId)) {
      final key = _counterKey(toolId);
      final cur = prefs.getInt(key) ?? 0;
      await prefs.setInt(key, cur + 1);
      await _gcOldKeys(prefs, toolId);
    }
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
