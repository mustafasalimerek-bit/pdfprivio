import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;

/// Generates throw-away sample PDFs so a first-time user can try a tool
/// without picking their own document.
///
/// The PII sample is the centrepiece — it embeds clearly fictitious but
/// regex-matching identifiers (SSN, credit card, IBAN, TC Kimlik, email,
/// phone) so the user can hit PII Scan or Redact and immediately see
/// PDFWork doing work on their behalf. We deliberately use well-known
/// reserved test values (Stripe's 4242 card, the GB82 WEST IBAN, the
/// Hollywood 555 phone prefix) so anyone who manually inspects the
/// sample sees they aren't real personal data.
class SamplePdfService {
  SamplePdfService._();
  static final SamplePdfService instance = SamplePdfService._();

  /// Builds (or reuses) `account_notice_sample.pdf` in the app's
  /// temporary directory and returns the File.
  Future<File> piiSampleDoc() async {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'pdfwork_samples', 'account_notice.pdf');
    final file = File(path);
    if (await file.exists()) return file;
    await Directory(p.dirname(path)).create(recursive: true);

    final bytes = await _buildPiiSampleBytes();
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<List<int>> _buildPiiSampleBytes() async {
    final pdf = pw.Document(
      title: 'Account Closing Notice (Sample)',
      author: 'PDFWork',
      subject: 'Sample document for PDFWork demo',
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pw_pdf.PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 56, vertical: 64),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'NORTHWAY MUTUAL CREDIT UNION',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Member services · 1820 Sample Way, Springfield, IL 62701',
              style: const pw.TextStyle(
                fontSize: 9,
                color: pw_pdf.PdfColors.grey700,
              ),
            ),
            pw.Divider(height: 26),
            pw.Text(
              'Account closing notice',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'PDFWork Sample Document — every identifier on this page is '
              'fictional. Names, account numbers, and reference IDs use '
              'reserved test values (Stripe 4242 card, GB82 WEST IBAN, '
              'Hollywood 555 phone prefix) so no real person can be '
              'mistaken for the subject of this notice.',
              style: pw.TextStyle(
                fontSize: 9,
                color: pw_pdf.PdfColors.grey600,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
            pw.SizedBox(height: 22),
            pw.Text(
              'Dear Jane Doe,',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'This letter confirms the closure of your member account '
              'effective the end of business on the date below. We have '
              'compiled the following information for your records.',
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
            ),
            pw.SizedBox(height: 18),
            _row('Account holder', 'Jane Doe'),
            _row('Date of birth', 'DOB: 04/11/1981'),
            _row('Social Security Number', '555-55-5555'),
            _row('Employer Tax ID', '12-3456789'),
            _row('TC Kimlik No (TR ref)', '10000000146'),
            _row('Primary card on file',
                'Visa ending  4242 4242 4242 4242'),
            _row('Linked IBAN',
                'GB82 WEST 1234 5698 7654 32'),
            _row('Mobile', '(555) 123-4567'),
            _row('Email of record', 'jane.doe@example.com'),
            pw.SizedBox(height: 22),
            pw.Text(
              'If any of the above information is incorrect, please '
              'contact a member representative within 30 days. After '
              'that period the account record will be moved to long-'
              'term retention storage.',
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'We appreciate your years of membership and wish you well.',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 22),
            pw.Text(
              'Sincerely,',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Member Services',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              'Sample generated by PDFWork — try Find sensitive data, '
              'then Redact, on this page.',
              style: const pw.TextStyle(
                fontSize: 8,
                color: pw_pdf.PdfColors.grey500,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  pw.Widget _row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 170,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 10,
                color: pw_pdf.PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
