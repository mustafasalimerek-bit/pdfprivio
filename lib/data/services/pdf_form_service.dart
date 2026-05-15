import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// One inspected AcroForm field. We expose a flat, UI-friendly view
/// instead of leaking Syncfusion's class hierarchy to the screens.
class FormFieldDescriptor {
  final int index; // position in PdfFormFieldCollection
  final String name; // technical name, e.g. "Form1[0].Page1[0].Name[0]"
  final String label; // best human-readable display label we can derive
  final FormFieldKind kind;
  final int pageIndex;
  final ui.Rect bounds;
  final bool readOnly;
  final bool multiline;
  final List<String> options; // for combo/list/radio
  final dynamic currentValue; // String for text/radio/combo, bool for checkbox

  const FormFieldDescriptor({
    required this.index,
    required this.name,
    required this.label,
    required this.kind,
    required this.pageIndex,
    required this.bounds,
    required this.readOnly,
    required this.multiline,
    required this.options,
    required this.currentValue,
  });
}

enum FormFieldKind {
  text,
  multilineText,
  checkbox,
  radioGroup,
  comboBox,
  listBox,
  signature,
  unsupported;

  bool get isEditable =>
      this != FormFieldKind.signature && this != FormFieldKind.unsupported;
}

class FormInspectOutcome {
  final List<FormFieldDescriptor> fields;
  final int totalPages;
  final bool hasForm;

  const FormInspectOutcome({
    required this.fields,
    required this.totalPages,
    required this.hasForm,
  });
}

class FormSaveOutcome {
  final File file;
  final int fieldsFilled;
  final bool flattened;

  const FormSaveOutcome({
    required this.file,
    required this.fieldsFilled,
    required this.flattened,
  });
}

/// Reads AcroForm fields out of a PDF, exposes them as a flat list,
/// and writes a filled copy back.
///
/// "Flatten on save" is the default: it bakes filled values into the
/// page graphics and removes the editable widgets. This is what lawyers
/// and CPAs almost always want — once you send a court filing or a 1040
/// you don't want the recipient to be able to uncheck a box.
class PdfFormService {
  PdfFormService._();
  static final PdfFormService instance = PdfFormService._();

  Future<Result<FormInspectOutcome>> inspect({
    required PdfDocument input,
    CancellationToken? cancel,
  }) async {
    sf.PdfDocument? doc;
    try {
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      final form = doc.form;
      final fields = form.fields;
      final descriptors = <FormFieldDescriptor>[];

      for (var i = 0; i < fields.count; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled');
        }
        final field = fields[i];
        descriptors.add(_describe(field, doc, i));
      }

      return Ok(FormInspectOutcome(
        fields: descriptors,
        totalPages: doc.pages.count,
        hasForm: descriptors.isNotEmpty,
      ));
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword,
            'PDF is password-protected — unlock it first.', cause: e);
      }
      return Err(FailureKind.unknown, 'Could not read form.', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  /// `values[index]` is keyed by the field's index in the original
  /// inspect outcome — so the UI can write a `Map&lt;int, dynamic&gt;` from
  /// its controllers/state directly without re-walking the field tree.
  Future<Result<FormSaveOutcome>> save({
    required PdfDocument input,
    required Map<int, dynamic> values,
    bool flatten = true,
    void Function(double progress, String message)? onProgress,
    CancellationToken? cancel,
  }) async {
    sf.PdfDocument? doc;
    try {
      onProgress?.call(0.1, 'Loading form…');
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      final fields = doc.form.fields;
      var filled = 0;

      for (var i = 0; i < fields.count; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled');
        }
        if (!values.containsKey(i)) continue;
        final value = values[i];
        final field = fields[i];

        if (_apply(field, value)) {
          filled++;
        }
        onProgress?.call(
          0.1 + 0.7 * (i / fields.count),
          'Writing field ${i + 1} of ${fields.count}',
        );
      }

      if (flatten) {
        onProgress?.call(0.85, 'Flattening fields…');
        doc.form.flattenAllFields();
      }

      onProgress?.call(0.95, 'Saving file…');
      final outBytes = await doc.save();
      final outFile = await _writeOutput(
        outBytes,
        '${_safeBase(input.displayName)}_filled',
      );
      onProgress?.call(1.0, 'Done');

      return Ok(FormSaveOutcome(
        file: outFile,
        fieldsFilled: filled,
        flattened: flatten,
      ));
    } catch (e) {
      return Err(FailureKind.unknown, 'Could not save form.', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  FormFieldDescriptor _describe(
    sf.PdfField field,
    sf.PdfDocument doc,
    int index,
  ) {
    final FormFieldKind kind;
    final List<String> options;
    final dynamic currentValue;
    final bool multiline;

    if (field is sf.PdfTextBoxField) {
      multiline = field.multiline;
      kind = multiline ? FormFieldKind.multilineText : FormFieldKind.text;
      options = const [];
      currentValue = field.text;
    } else if (field is sf.PdfCheckBoxField) {
      kind = FormFieldKind.checkbox;
      multiline = false;
      options = const [];
      currentValue = field.isChecked;
    } else if (field is sf.PdfRadioButtonListField) {
      kind = FormFieldKind.radioGroup;
      multiline = false;
      options = _readRadioOptions(field);
      currentValue = field.selectedValue;
    } else if (field is sf.PdfComboBoxField) {
      kind = FormFieldKind.comboBox;
      multiline = false;
      options = _readListOptions(field.items);
      currentValue = field.selectedValue;
    } else if (field is sf.PdfListBoxField) {
      kind = FormFieldKind.listBox;
      multiline = false;
      options = _readListOptions(field.items);
      final sel = field.selectedValues;
      currentValue = sel.isEmpty ? '' : sel.first;
    } else if (field is sf.PdfSignatureField) {
      kind = FormFieldKind.signature;
      multiline = false;
      options = const [];
      currentValue = '';
    } else {
      kind = FormFieldKind.unsupported;
      multiline = false;
      options = const [];
      currentValue = '';
    }

    return FormFieldDescriptor(
      index: index,
      name: field.name ?? 'field_$index',
      label: _deriveLabel(field.name ?? ''),
      kind: kind,
      pageIndex: _pageIndexOf(field, doc),
      bounds: field.bounds,
      readOnly: field.readOnly,
      multiline: multiline,
      options: options,
      currentValue: currentValue,
    );
  }

  bool _apply(sf.PdfField field, dynamic value) {
    try {
      if (field is sf.PdfTextBoxField) {
        field.text = value?.toString() ?? '';
        return true;
      }
      if (field is sf.PdfCheckBoxField) {
        field.isChecked = value == true;
        return true;
      }
      if (field is sf.PdfRadioButtonListField) {
        if (value is String && value.isNotEmpty) {
          field.selectedValue = value;
          return true;
        }
      }
      if (field is sf.PdfComboBoxField) {
        if (value is String && value.isNotEmpty) {
          field.selectedValue = value;
          return true;
        }
      }
      if (field is sf.PdfListBoxField) {
        if (value is String && value.isNotEmpty) {
          field.selectedValues = [value];
          return true;
        }
      }
    } catch (_) {
      // Single bad write shouldn't sink the whole save — keep going.
    }
    return false;
  }

  List<String> _readRadioOptions(sf.PdfRadioButtonListField field) {
    final out = <String>[];
    for (var i = 0; i < field.items.count; i++) {
      final v = field.items[i].value;
      if (v.isNotEmpty) out.add(v);
    }
    return out;
  }

  List<String> _readListOptions(sf.PdfListFieldItemCollection items) {
    final out = <String>[];
    for (var i = 0; i < items.count; i++) {
      final t = items[i].text;
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }

  int _pageIndexOf(sf.PdfField field, sf.PdfDocument doc) {
    try {
      final page = field.page;
      if (page == null) return 0;
      for (var i = 0; i < doc.pages.count; i++) {
        if (identical(doc.pages[i], page)) return i;
      }
    } catch (_) {}
    return 0;
  }

  /// Best-effort human-readable label from the technical field name.
  /// Acrobat/InDesign forms often use names like
  /// "topmostSubform[0].Page1[0].f1_01[0]" — useless as a UI label.
  /// We pick the last `.`-segment, strip `[n]` indices, replace
  /// underscores/dashes with spaces, and Title-case it.
  String _deriveLabel(String name) {
    if (name.isEmpty) return 'Unnamed';
    var label = name.split('.').last;
    label = label.replaceAll(RegExp(r'\[\d+\]'), '');
    label = label.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    if (label.isEmpty) return name;
    return label
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  Future<File> _writeOutput(List<int> bytes, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = _safeBase(baseName);
    final path = p.join(dir.path, '$safe.pdf');
    final f = File(path);
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  String _safeBase(String s) =>
      s.replaceAll('.pdf', '').replaceAll(RegExp(r'[\\/]'), '_').trim();
}
