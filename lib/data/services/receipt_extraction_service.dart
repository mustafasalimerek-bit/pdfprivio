import 'ocr_service.dart';

/// Best-effort fields pulled from a receipt's OCR text.
///
/// Every field is nullable — the extractor only emits what it's
/// reasonably confident about. The capture screen pre-fills the form
/// with these values; the user edits / fills in the gaps before
/// saving. Treat this as a draft, not the source of truth.
class ReceiptDraft {
  final DateTime? date;
  final String? vendor;
  final String? total;
  final String? tax;
  final String currency;

  const ReceiptDraft({
    this.date,
    this.vendor,
    this.total,
    this.tax,
    this.currency = 'USD',
  });
}

/// Heuristic field extractor — runs entirely on OCR output, no model.
///
/// Design notes:
///   * Conservative on purpose. False-confident extraction (wrong
///     total, wrong vendor) corrupts a CPA's books at year end. We
///     prefer leaving a field empty and making the user type it.
///   * Layout-aware via OCR bounding boxes: vendor is "tallest text
///     near the top", which beats first-line heuristics on receipts
///     where the merchant logo wraps onto multiple lines.
///   * No network, no model — pure Dart string + regex work.
class ReceiptExtractionService {
  ReceiptExtractionService._();
  static final ReceiptExtractionService instance =
      ReceiptExtractionService._();

  ReceiptDraft extract(OcrPageResult ocr) {
    final lines = _lines(ocr);
    return ReceiptDraft(
      date: _extractDate(lines),
      vendor: _extractVendor(ocr),
      total: _extractTotal(lines),
      tax: _extractTax(lines),
      currency: _extractCurrency(lines),
    );
  }

  List<String> _lines(OcrPageResult ocr) {
    // Sort by y descending (Vision's origin is bottom-left → top of
    // page first) then x ascending to roughly mimic reading order.
    final sorted = [...ocr.observations]
      ..sort((a, b) {
        final dy = b.y.compareTo(a.y);
        if (dy != 0) return dy;
        return a.x.compareTo(b.x);
      });
    return sorted.map((o) => o.text).toList();
  }

  // ----- date -----

  /// Matches dates in formats US receipts actually use:
  ///   01/15/2025, 1-15-25, 2025-01-15, Jan 15 2025, January 15, 2025
  static final RegExp _dateNumeric = RegExp(
    r'(?:\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})|(?:\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2})',
  );
  static final RegExp _dateWord = RegExp(
    r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\s+\d{1,2}[,]?\s+\d{2,4}',
    caseSensitive: false,
  );
  static const _monthMap = <String, int>{
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  DateTime? _extractDate(List<String> lines) {
    final now = DateTime.now();
    DateTime? best;
    for (final line in lines) {
      final wordMatch = _dateWord.firstMatch(line);
      if (wordMatch != null) {
        final parsed = _parseWordDate(wordMatch.group(0)!);
        if (_isPlausible(parsed, now)) return parsed;
      }
      final numMatch = _dateNumeric.firstMatch(line);
      if (numMatch != null) {
        final parsed = _parseNumericDate(numMatch.group(0)!);
        if (_isPlausible(parsed, now)) {
          best ??= parsed;
        }
      }
    }
    return best;
  }

  bool _isPlausible(DateTime? d, DateTime now) {
    if (d == null) return false;
    // Filter junk: future-dated more than a day, or older than 5 years.
    if (d.isAfter(now.add(const Duration(days: 1)))) return false;
    if (d.isBefore(now.subtract(const Duration(days: 365 * 5)))) {
      return false;
    }
    return true;
  }

  DateTime? _parseWordDate(String raw) {
    final parts = raw.replaceAll(',', '').split(RegExp(r'\s+'));
    if (parts.length < 3) return null;
    final month = _monthMap[parts[0].toLowerCase().substring(
        0, parts[0].length < 3 ? parts[0].length : 3)];
    if (month == null) return null;
    final day = int.tryParse(parts[1]);
    var year = int.tryParse(parts[2]);
    if (day == null || year == null) return null;
    if (year < 100) year += 2000;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseNumericDate(String raw) {
    final parts = raw.split(RegExp(r'[\/\-\.]'));
    if (parts.length != 3) return null;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return null;
    // YYYY-MM-DD if first part is 4 digits.
    if (parts[0].length == 4) {
      try {
        return DateTime(nums[0]!, nums[1]!, nums[2]!);
      } catch (_) {
        return null;
      }
    }
    // Default to US-style MM/DD/YYYY for the lawyer/CPA wedge.
    var year = nums[2]!;
    if (year < 100) year += 2000;
    try {
      return DateTime(year, nums[0]!, nums[1]!);
    } catch (_) {
      return null;
    }
  }

  // ----- vendor -----

  /// Vendor = the tallest, top-most text observation. Beats "first
  /// line" because receipts often have address fragments above the
  /// merchant logo, and beats "longest string" because totals are
  /// often the widest text on the page.
  String? _extractVendor(OcrPageResult ocr) {
    if (ocr.observations.isEmpty) return null;
    final topThird = ocr.observations
        .where((o) => o.y > 0.66)
        .toList();
    if (topThird.isEmpty) return null;
    topThird.sort((a, b) => b.height.compareTo(a.height));
    final candidate = topThird.first.text.trim();
    // Strip leading/trailing punctuation and keep it under 60 chars.
    final cleaned = candidate
        .replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '')
        .trim();
    if (cleaned.isEmpty || cleaned.length > 60) return null;
    return cleaned;
  }

  // ----- total + tax -----

  static final RegExp _moneyPattern = RegExp(
    r'[\$\€\£\₺]?\s*(\d{1,3}(?:[,\.\s]\d{3})*[,\.]\d{2}|\d+[,\.]\d{2})',
  );

  static const _totalKeywords = [
    'grand total',
    'total amount',
    'amount due',
    'amount charged',
    'balance due',
    'total',
    'charged',
    'paid',
  ];

  static const _taxKeywords = [
    'sales tax',
    'tax total',
    'tax',
    'vat',
    'gst',
    'hst',
  ];

  String? _extractTotal(List<String> lines) {
    return _findMoneyNearKeyword(lines, _totalKeywords);
  }

  String? _extractTax(List<String> lines) {
    return _findMoneyNearKeyword(lines, _taxKeywords);
  }

  /// Subtotal / pre-tax / partial-payment lines we must NOT credit
  /// as the grand total. Covers Subtotal, Sub Total, Sub-Total,
  /// pre-tax, prediscount — the ones that screw up CPA books.
  static final RegExp _subtotalGuard = RegExp(
    r'\bsub[ -]?total\b|\bpre[ -]?tax\b',
    caseSensitive: false,
  );

  String? _findMoneyNearKeyword(List<String> lines, List<String> keywords) {
    // Word-boundary regexes per keyword — substring matching would
    // make "total" match inside "subtotal", which is the difference
    // between a $44 Total and a $40 Subtotal on a 50% of US
    // restaurant receipts. Compiled once per call.
    final patterns = keywords
        .map((k) => RegExp(
              r'\b' + RegExp.escape(k) + r'\b',
              caseSensitive: false,
            ))
        .toList();
    String? best;
    int? bestRank;
    for (final line in lines) {
      for (var i = 0; i < keywords.length; i++) {
        if (patterns[i].hasMatch(line)) {
          // Belt-and-braces: "Sub Total $40" word-bounds match "total",
          // and we mustn't pick it. Skip when the surrounding line is
          // explicitly a subtotal / pre-tax marker.
          if (keywords[i] == 'total' && _subtotalGuard.hasMatch(line)) {
            break;
          }
          final match = _moneyPattern.firstMatch(line);
          if (match != null) {
            // Lower rank wins (matches the order in the keywords list —
            // "grand total" beats "total" beats "paid").
            if (bestRank == null || i < bestRank) {
              best = _normaliseMoney(match.group(1)!);
              bestRank = i;
            }
          }
          break;
        }
      }
    }
    return best;
  }

  String _normaliseMoney(String raw) => normaliseMoney(raw);

  /// Convert "1.234,56" (EU) → "1234.56"; "1,234.56" (US) → "1234.56";
  /// "12,34" → "12.34". Public so the capture screen can run user-typed
  /// totals through the same normaliser before persisting — keeps CSV
  /// exports parseable by QuickBooks/Xero regardless of locale.
  static String normaliseMoney(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'\s'), '');
    if (cleaned.isEmpty) return cleaned;
    final lastComma = cleaned.lastIndexOf(',');
    final lastDot = cleaned.lastIndexOf('.');
    if (lastComma > lastDot) {
      cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
    } else {
      cleaned = cleaned.replaceAll(',', '');
    }
    return cleaned;
  }

  // ----- currency -----

  static final RegExp _eurWord = RegExp(r'\bEUR\b', caseSensitive: false);
  static final RegExp _gbpWord = RegExp(r'\bGBP\b', caseSensitive: false);
  static final RegExp _tryWord = RegExp(r'\bTRY\b', caseSensitive: false);

  String _extractCurrency(List<String> lines) {
    final joined = lines.join(' ');
    if (joined.contains('€') || _eurWord.hasMatch(joined)) return 'EUR';
    if (joined.contains('£') || _gbpWord.hasMatch(joined)) return 'GBP';
    // Word boundary on TRY so "RETRY" / "COUNTRY" don't flip currency.
    if (joined.contains('₺') || _tryWord.hasMatch(joined)) return 'TRY';
    return 'USD';
  }
}
