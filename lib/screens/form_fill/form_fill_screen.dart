import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_form_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import '../merge/merge_result_screen.dart';

class FormFillScreen extends ConsumerStatefulWidget {
  const FormFillScreen({super.key});

  @override
  ConsumerState<FormFillScreen> createState() => _FormFillScreenState();
}

class _FormFillScreenState extends ConsumerState<FormFillScreen> {
  PdfDocument? _doc;
  FormInspectOutcome? _inspect;
  final Map<int, dynamic> _values = {};
  final Map<int, TextEditingController> _textControllers = {};
  bool _flatten = true;
  double? _progress;
  String? _status;
  CancellationToken? _cancel;

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res == null) return;
    final path = res.paths.firstOrNull;
    if (path == null) return;

    final metaRes = await PdfMetadataService.instance.inspect(File(path));
    if (!mounted) return;
    switch (metaRes) {
      case Ok(:final value):
        setState(() => _doc = value);
        await _inspectForm();
      case Err(:final kind, :final message):
        HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kind == FailureKind.needsPassword
                ? 'This PDF is password-protected — unlock it first.'
                : message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _inspectForm() async {
    final doc = _doc;
    if (doc == null) return;
    setState(() {
      _progress = 0;
      _status = 'Reading form fields…';
    });
    final result = await PdfFormService.instance.inspect(input: doc);
    if (!mounted) return;
    setState(() {
      _progress = null;
      _status = null;
    });
    switch (result) {
      case Ok(:final value):
        setState(() {
          _inspect = value;
          _seedDefaults(value);
        });
        HapticsService.instance.select();
      case Err(:final message):
        HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _seedDefaults(FormInspectOutcome inspect) {
    _values.clear();
    for (final c in _textControllers.values) {
      c.dispose();
    }
    _textControllers.clear();
    for (final f in inspect.fields) {
      if (!f.kind.isEditable) continue;
      switch (f.kind) {
        case FormFieldKind.text:
        case FormFieldKind.multilineText:
          final txt = (f.currentValue as String?) ?? '';
          _textControllers[f.index] = TextEditingController(text: txt);
          _values[f.index] = txt;
        case FormFieldKind.checkbox:
          _values[f.index] = f.currentValue == true;
        case FormFieldKind.radioGroup:
        case FormFieldKind.comboBox:
        case FormFieldKind.listBox:
          _values[f.index] = (f.currentValue as String?) ?? '';
        default:
          break;
      }
    }
  }

  Future<void> _save() async {
    final doc = _doc;
    if (doc == null) return;
    HapticsService.instance.tap();

    for (final entry in _textControllers.entries) {
      _values[entry.key] = entry.value.text;
    }

    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
      _status = 'Saving…';
    });

    final result = await PdfFormService.instance.save(
      input: doc,
      values: _values,
      flatten: _flatten,
      onProgress: (p, m) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _status = m;
        });
      },
      cancel: cancel,
    );

    if (!mounted) return;
    setState(() {
      _progress = null;
      _status = null;
      _cancel = null;
    });

    switch (result) {
      case Ok(:final value):
        HapticsService.instance.success();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MergeResultScreen(
              outputFile: value.file,
              sourceCount: value.fieldsFilled,
              toolLabel: 'Form filled',
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _doc = null;
            _inspect = null;
            _values.clear();
            for (final c in _textControllers.values) {
              c.dispose();
            }
            _textControllers.clear();
          });
        }
      case Err(:final kind, :final message):
        HapticsService.instance.error();
        if (kind != FailureKind.cancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final inspect = _inspect;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fill form'),
        actions: [
          if (doc != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(() {
                  _doc = null;
                  _inspect = null;
                  _values.clear();
                  for (final c in _textControllers.values) {
                    c.dispose();
                  }
                  _textControllers.clear();
                });
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PrivacyBadge(),
                  ),
                ),
                Expanded(
                  child: doc == null
                      ? _EmptyState(onPick: _pick)
                      : inspect == null
                          ? const SizedBox.shrink()
                          : !inspect.hasForm
                              ? _NoFieldsState(doc: doc)
                              : _FormFields(
                                  inspect: inspect,
                                  values: _values,
                                  textControllers: _textControllers,
                                  flatten: _flatten,
                                  onFlattenChanged: (v) {
                                    HapticsService.instance.select();
                                    setState(() => _flatten = v);
                                  },
                                  onChange: () => setState(() {}),
                                ),
                ),
                if (doc != null &&
                    inspect != null &&
                    inspect.hasForm &&
                    _progress == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _flatten
                              ? 'Save flattened PDF · ${inspect.fields.where((f) => f.kind.isEditable).length} field'
                                  '${inspect.fields.where((f) => f.kind.isEditable).length == 1 ? '' : 's'}'
                              : 'Save filled (editable) PDF',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_progress != null)
            ProgressOverlay(
              progress: _progress,
              title: 'Form fill',
              subtitle: _status ?? 'On this device — no upload',
              onCancel: () => _cancel?.cancel(),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyState({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_document,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Fill in a PDF form',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'IRS, USCIS, court motions, intake forms — anything with '
              'AcroForm fields. PDFPrivio detects text boxes, checkboxes, '
              'radio groups, and dropdowns, then bakes your answers in '
              'so the recipient gets a final, uneditable PDF.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.add),
              label: const Text('Pick a PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoFieldsState extends StatelessWidget {
  final PdfDocument doc;
  const _NoFieldsState({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.info_outline,
                size: 36,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No fillable fields found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '"${doc.displayName}" doesn\'t have any AcroForm fields. '
              "Many tax/legal forms do — try a PDF straight from "
              'irs.gov, uscis.gov, or your court\'s e-filing portal.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormFields extends StatelessWidget {
  final FormInspectOutcome inspect;
  final Map<int, dynamic> values;
  final Map<int, TextEditingController> textControllers;
  final bool flatten;
  final ValueChanged<bool> onFlattenChanged;
  final VoidCallback onChange;

  const _FormFields({
    required this.inspect,
    required this.values,
    required this.textControllers,
    required this.flatten,
    required this.onFlattenChanged,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    // Group fields by page so the user reads the form in natural order.
    final byPage = <int, List<FormFieldDescriptor>>{};
    for (final f in inspect.fields) {
      byPage.putIfAbsent(f.pageIndex, () => []).add(f);
    }
    final pageOrder = byPage.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${inspect.fields.length} field'
                  '${inspect.fields.length == 1 ? '' : 's'} across '
                  '${inspect.totalPages} page'
                  '${inspect.totalPages == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _FlattenToggle(value: flatten, onChanged: onFlattenChanged),
        const SizedBox(height: 12),
        for (final pageIndex in pageOrder) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
            child: Text(
              'Page ${pageIndex + 1}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          for (final f in byPage[pageIndex]!)
            _FieldRow(
              field: f,
              value: values[f.index],
              controller: textControllers[f.index],
              onChanged: (v) {
                values[f.index] = v;
                onChange();
              },
            ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _FlattenToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _FlattenToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: value
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 18,
              color: value ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Flatten when saving',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value
                        ? 'Recipient gets a final PDF — checkboxes and '
                            "fields can't be changed after"
                        : 'Recipient gets an editable form — they can '
                            'change your answers',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final FormFieldDescriptor field;
  final dynamic value;
  final TextEditingController? controller;
  final ValueChanged<dynamic> onChanged;
  const _FieldRow({
    required this.field,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    field.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (field.readOnly)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'READ-ONLY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _control(),
          ],
        ),
      ),
    );
  }

  Widget _control() {
    if (field.readOnly && field.kind != FormFieldKind.checkbox) {
      return Text(
        value?.toString() ?? '—',
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    switch (field.kind) {
      case FormFieldKind.text:
      case FormFieldKind.multilineText:
        return TextField(
          controller: controller,
          maxLines: field.kind == FormFieldKind.multilineText ? 4 : 1,
          enabled: !field.readOnly,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Type here',
            filled: true,
            fillColor: AppColors.background,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
          onChanged: onChanged,
        );
      case FormFieldKind.checkbox:
        final checked = value == true;
        return Row(
          children: [
            Switch.adaptive(
              value: checked,
              onChanged:
                  field.readOnly ? null : (v) => onChanged(v),
              activeThumbColor: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              checked ? 'Checked' : 'Unchecked',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );
      case FormFieldKind.radioGroup:
        if (field.options.isEmpty) {
          return const Text(
            'No options found',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          );
        }
        final selected = (value as String?) ?? '';
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final opt in field.options)
              ChoiceChip(
                label: Text(opt),
                selected: selected == opt,
                onSelected: field.readOnly
                    ? null
                    : (_) => onChanged(opt),
                selectedColor:
                    AppColors.primary.withValues(alpha: 0.18),
              ),
          ],
        );
      case FormFieldKind.comboBox:
      case FormFieldKind.listBox:
        if (field.options.isEmpty) {
          return TextField(
            controller: controller ??
                TextEditingController(text: (value as String?) ?? ''),
            decoration: const InputDecoration(
              hintText: 'Type a value',
              isDense: true,
            ),
            onChanged: onChanged,
          );
        }
        final current = (value as String?) ?? '';
        final hasCurrent = field.options.contains(current);
        return DropdownButtonFormField<String>(
          initialValue: hasCurrent ? current : null,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
          ),
          items: [
            for (final o in field.options)
              DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged:
              field.readOnly ? null : (v) => onChanged(v ?? ''),
        );
      case FormFieldKind.signature:
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.draw_outlined,
                  color: AppColors.warning, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Signature field — fill the rest, save, then use the '
                  'Sign tool on the result to draw your signature.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        );
      case FormFieldKind.unsupported:
        return const Text(
          'Field type not yet supported',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
            fontStyle: FontStyle.italic,
          ),
        );
    }
  }
}
