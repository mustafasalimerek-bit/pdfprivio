import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/result.dart';
import '../models/pdf_document.dart';
import 'audit_service.dart';

/// What the encrypted PDF will allow non-owner viewers to do.
///
/// Most consumer cases just want "read-only" — anyone with the password
/// can view but not print, copy text, or modify. We expose the two common
/// presets and leave fine-grained AcroPermissions for the Pro tier.
enum PdfProtectionLevel {
  /// User-password only. Anyone with the password gets full access.
  fullAccess,

  /// User-password to open + owner-password locks down printing/copying.
  readOnly,
}

extension PdfProtectionLevelLabel on PdfProtectionLevel {
  String get label {
    switch (this) {
      case PdfProtectionLevel.fullAccess:
        return 'Password to open (full access)';
      case PdfProtectionLevel.readOnly:
        return 'Password to open + read-only';
    }
  }

  String get description {
    switch (this) {
      case PdfProtectionLevel.fullAccess:
        return 'Recipient enters the password and can do everything '
            'with the document.';
      case PdfProtectionLevel.readOnly:
        return 'Recipient enters the password to open but can\'t print, '
            'copy text, or modify the document.';
    }
  }
}

class PdfPasswordService {
  PdfPasswordService._();
  static final PdfPasswordService instance = PdfPasswordService._();

  Future<Result<File>> protect({
    required PdfDocument input,
    required String userPassword,
    PdfProtectionLevel level = PdfProtectionLevel.fullAccess,
  }) async {
    if (userPassword.isEmpty) {
      return Err(FailureKind.unknown, 'Password cannot be empty');
    }
    if (userPassword.length < 4) {
      return Err(FailureKind.unknown,
          'Password should be at least 4 characters');
    }

    sf.PdfDocument? doc;
    try {
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      doc.security.userPassword = userPassword;
      doc.security.algorithm = sf.PdfEncryptionAlgorithm.aesx256Bit;

      switch (level) {
        case PdfProtectionLevel.fullAccess:
          // No owner password set; viewer with the user password has
          // every permission by default.
          break;
        case PdfProtectionLevel.readOnly:
          // Owner password locks down editing/printing/copying. We
          // derive it deterministically from the user password + a
          // pepper so the user never has to track two passwords.
          doc.security.ownerPassword = '${userPassword}_owner';
          final perms = doc.security.permissions;
          perms.clear();
          perms.add(sf.PdfPermissionsFlags.accessibilityCopyContent);
          break;
      }

      final outBytes = await doc.save();
      final outFile = await _writeOutput(
        outBytes,
        '${input.displayName}_protected',
      );
      // Audit records ACTION, never the password itself — privilege
      // applies to the log too. Log length so the user can later
      // verify "I used a 12-char password".
      await AuditService.instance.record(
        tool: 'password',
        inputFile: input.file,
        outputFile: outFile,
        params: {
          'action': 'protect',
          'level': level.name,
          'passwordLength': '${userPassword.length}',
        },
      );
      return Ok(outFile);
    } catch (e) {
      return Err(FailureKind.unknown, 'Protection failed', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  /// Strips encryption from a PDF when the user supplies the correct
  /// password. Syncfusion throws on the wrong password — we route it to
  /// FailureKind.needsPassword so the UI can prompt the user to retry.
  Future<Result<File>> removePassword({
    required PdfDocument input,
    required String password,
  }) async {
    sf.PdfDocument? doc;
    try {
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes, password: password);

      // Clearing both passwords + permissions removes encryption entirely
      // when the file is saved.
      doc.security.userPassword = '';
      doc.security.ownerPassword = '';
      doc.security.permissions.clear();

      final outBytes = await doc.save();
      final outFile = await _writeOutput(
        outBytes,
        '${input.displayName}_unlocked',
      );
      await AuditService.instance.record(
        tool: 'password',
        inputFile: input.file,
        outputFile: outFile,
        params: {'action': 'unlock'},
      );
      return Ok(outFile);
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword,
            'That password didn\'t match the PDF',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Could not unlock PDF', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  Future<File> _writeOutput(List<int> bytes, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = baseName.replaceAll(RegExp(r'[\\/]'), '_').trim();
    final path = p.join(dir.path, '$safe.pdf');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
