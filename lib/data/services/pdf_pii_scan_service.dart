import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';
import 'audit_service.dart';

enum PiiCategory {
  ssn('SSN', 'US Social Security Number', 'high'),
  ein('EIN', 'US Employer Tax ID', 'high'),
  creditCard('Credit Card', 'Card number (Luhn-verified)', 'high'),
  iban('IBAN', 'International bank account', 'high'),
  tcKimlik('TC Kimlik No', 'Turkish national ID', 'high'),
  email('Email', 'Email address', 'medium'),
  phoneUs('Phone (US)', 'US-format phone number', 'medium'),
  phoneTr('Phone (TR)', 'Turkish mobile number', 'medium'),
  date('Date', 'Date of birth or similar', 'low');

  final String label;
  final String description;
  final String severity;
  const PiiCategory(this.label, this.description, this.severity);
}

class PiiMatch {
  final PiiCategory category;
  final String matchedText;
  final String redactedPreview;
  final int pageIndex;
  final String contextSnippet;

  const PiiMatch({
    required this.category,
    required this.matchedText,
    required this.redactedPreview,
    required this.pageIndex,
    required this.contextSnippet,
  });
}

class PiiScanOutcome {
  final List<PiiMatch> matches;
  final Map<PiiCategory, int> countsByCategory;
  final int totalPages;
  final int pagesWithFindings;
  final Duration elapsed;
  final bool wasMostlyEmpty;

  const PiiScanOutcome({
    required this.matches,
    required this.countsByCategory,
    required this.totalPages,
    required this.pagesWithFindings,
    required this.elapsed,
    required this.wasMostlyEmpty,
  });

  bool get hasFindings => matches.isNotEmpty;
  int get totalCount => matches.length;
}

class PdfPiiScanService {
  PdfPiiScanService._();
  static final PdfPiiScanService instance = PdfPiiScanService._();

  static final _ssn = RegExp(r'\b(?!000|666|9\d{2})\d{3}[-\s]?(?!00)\d{2}[-\s]?(?!0000)\d{4}\b');
  static final _ein = RegExp(r'\b\d{2}-\d{7}\b');
  static final _cardLoose = RegExp(r'\b(?:\d[ -]*?){13,19}\b');
  static final _iban = RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b');
  static final _tcKimlik = RegExp(r'(?<![\d])[1-9]\d{10}(?![\d])');
  static final _email = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b');
  static final _phoneUs = RegExp(r'(?:\+?1[-.\s]?)?\(?[2-9]\d{2}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b');
  static final _phoneTr = RegExp(r'(?:\+?90[-.\s]?)?5\d{2}[-.\s]?\d{3}[-.\s]?\d{2}[-.\s]?\d{2}\b');
  static final _dateContext = RegExp(
    r'(?:DOB|date of birth|doğum tarihi)[\s:]*([0-9]{1,2}[/.\-][0-9]{1,2}[/.\-][0-9]{2,4})',
    caseSensitive: false,
  );

  Future<Result<PiiScanOutcome>> scan({
    required PdfDocument input,
    void Function(double progress, String message)? onProgress,
    CancellationToken? cancel,
  }) async {
    final stopwatch = Stopwatch()..start();
    sf.PdfDocument? doc;
    try {
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      final extractor = sf.PdfTextExtractor(doc);
      final pageCount = doc.pages.count;
      final matches = <PiiMatch>[];
      final pagesHit = <int>{};
      var totalChars = 0;

      for (var i = 0; i < pageCount; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled');
        }
        onProgress?.call(
          i / pageCount,
          'Scanning page ${i + 1} of $pageCount',
        );

        final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        totalChars += text.length;

        final pageMatches = _scanText(text, pageIndex: i);
        if (pageMatches.isNotEmpty) pagesHit.add(i);
        matches.addAll(pageMatches);
      }

      stopwatch.stop();
      onProgress?.call(1.0, 'Done');

      final counts = <PiiCategory, int>{};
      for (final m in matches) {
        counts[m.category] = (counts[m.category] ?? 0) + 1;
      }

      final avg = pageCount == 0 ? 0 : totalChars / pageCount;

      // Audit: record counts only, never the matched strings — those
      // ARE the PII, so logging them defeats the purpose.
      await AuditService.instance.record(
        tool: 'pii_scan',
        inputFile: input.file,
        params: {
          'totalPages': '$pageCount',
          'pagesWithFindings': '${pagesHit.length}',
          'totalMatches': '${matches.length}',
          'categories': counts.entries
              .map((e) => '${e.key.name}=${e.value}')
              .join(','),
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
        },
      );

      return Ok(PiiScanOutcome(
        matches: matches,
        countsByCategory: counts,
        totalPages: pageCount,
        pagesWithFindings: pagesHit.length,
        elapsed: stopwatch.elapsed,
        wasMostlyEmpty: avg < 8,
      ));
    } catch (e) {
      stopwatch.stop();
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword,
            'PDF is password-protected', cause: e);
      }
      return Err(FailureKind.unknown, 'Scan failed', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  List<PiiMatch> _scanText(String text, {required int pageIndex}) {
    final out = <PiiMatch>[];
    final seen = <String>{};

    void addMatch(PiiCategory cat, RegExpMatch m, String matched) {
      final key = '${cat.name}::$matched::${m.start}';
      if (seen.contains(key)) return;
      seen.add(key);
      out.add(PiiMatch(
        category: cat,
        matchedText: matched,
        redactedPreview: _redact(matched, cat),
        pageIndex: pageIndex,
        contextSnippet: _snippet(text, m.start, m.end),
      ));
    }

    for (final m in _ssn.allMatches(text)) {
      addMatch(PiiCategory.ssn, m, m.group(0)!);
    }
    for (final m in _ein.allMatches(text)) {
      addMatch(PiiCategory.ein, m, m.group(0)!);
    }
    for (final m in _cardLoose.allMatches(text)) {
      final raw = m.group(0)!;
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 13 || digits.length > 19) continue;
      if (!_luhnValid(digits)) continue;
      addMatch(PiiCategory.creditCard, m, raw.trim());
    }
    for (final m in _iban.allMatches(text)) {
      addMatch(PiiCategory.iban, m, m.group(0)!);
    }
    for (final m in _tcKimlik.allMatches(text)) {
      final s = m.group(0)!;
      if (_tcKimlikValid(s)) addMatch(PiiCategory.tcKimlik, m, s);
    }
    for (final m in _email.allMatches(text)) {
      addMatch(PiiCategory.email, m, m.group(0)!);
    }
    for (final m in _phoneUs.allMatches(text)) {
      addMatch(PiiCategory.phoneUs, m, m.group(0)!);
    }
    for (final m in _phoneTr.allMatches(text)) {
      addMatch(PiiCategory.phoneTr, m, m.group(0)!);
    }
    for (final m in _dateContext.allMatches(text)) {
      addMatch(PiiCategory.date, m, m.group(1) ?? m.group(0)!);
    }

    return out;
  }

  String _snippet(String text, int start, int end) {
    final s = (start - 24).clamp(0, text.length);
    final e = (end + 24).clamp(0, text.length);
    final raw = text.substring(s, e).replaceAll(RegExp(r'\s+'), ' ').trim();
    final prefix = s > 0 ? '…' : '';
    final suffix = e < text.length ? '…' : '';
    return '$prefix$raw$suffix';
  }

  String _redact(String value, PiiCategory cat) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    switch (cat) {
      case PiiCategory.ssn:
        return digits.length >= 4
            ? 'XXX-XX-${digits.substring(digits.length - 4)}'
            : 'XXX-XX-XXXX';
      case PiiCategory.creditCard:
        return digits.length >= 4
            ? '•••• •••• •••• ${digits.substring(digits.length - 4)}'
            : '•••• $digits';
      case PiiCategory.email:
        final at = value.indexOf('@');
        if (at <= 1) return '•••${value.substring(at)}';
        return '${value[0]}•••${value.substring(at)}';
      case PiiCategory.phoneUs:
      case PiiCategory.phoneTr:
        return digits.length >= 4
            ? '••• ••• ${digits.substring(digits.length - 4)}'
            : '••••';
      case PiiCategory.tcKimlik:
        return digits.length >= 4
            ? '•••••••${digits.substring(digits.length - 4)}'
            : '•••••';
      case PiiCategory.iban:
        return value.length >= 8
            ? '${value.substring(0, 4)}•••${value.substring(value.length - 4)}'
            : '••••';
      default:
        return value;
    }
  }

  bool _luhnValid(String digits) {
    var sum = 0;
    var alt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = int.parse(digits[i]);
      if (alt) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alt = !alt;
    }
    return sum % 10 == 0 && digits.length >= 13;
  }

  bool _tcKimlikValid(String s) {
    if (s.length != 11) return false;
    final d = s.split('').map(int.parse).toList();
    if (d[0] == 0) return false;
    final oddSum = d[0] + d[2] + d[4] + d[6] + d[8];
    final evenSum = d[1] + d[3] + d[5] + d[7];
    final c10 = ((oddSum * 7) - evenSum) % 10;
    if (c10 < 0 || c10 != d[9]) return false;
    final c11 = (d.take(10).reduce((a, b) => a + b)) % 10;
    return c11 == d[10];
  }
}
