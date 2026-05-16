import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/result.dart';
import '../../data/models/receipt.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/document_scanner_service.dart';
import '../../data/services/expense_ledger_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/ocr_service.dart';
import '../../data/services/receipt_extraction_service.dart';
import '../../widgets/privacy_badge.dart';
import 'expense_ledger_screen.dart';

/// Capture one receipt → OCR → extract → confirm → save. Designed
/// around the freelancer's three-second receipt-at-the-cafe workflow:
/// open, scan, save, back to the table. Heuristic extraction
/// pre-fills the form; the user only types when extraction missed.
class ReceiptCaptureScreen extends ConsumerStatefulWidget {
  const ReceiptCaptureScreen({super.key});

  @override
  ConsumerState<ReceiptCaptureScreen> createState() =>
      _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState
    extends ConsumerState<ReceiptCaptureScreen> {
  File? _source;
  bool _busy = false;
  String _status = '';
  String _rawText = '';

  final _dateController = TextEditingController();
  final _vendorController = TextEditingController();
  final _totalController = TextEditingController();
  final _taxController = TextEditingController();
  final _currencyController = TextEditingController(text: 'USD');
  final _categoryController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _date;
  bool? _scannerAvailable;

  static const List<String> _commonCategories = [
    'Meals',
    'Travel',
    'Office',
    'Software',
    'Equipment',
    'Mileage',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    DocumentScannerService.instance.isAvailable().then((v) {
      if (mounted) setState(() => _scannerAvailable = v);
    });
  }

  @override
  void dispose() {
    _dateController.dispose();
    _vendorController.dispose();
    _totalController.dispose();
    _taxController.dispose();
    _currencyController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    HapticsService.instance.tap();
    final res = await DocumentScannerService.instance.scan();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        if (value.isEmpty) return;
        await _processSource(value.pages.first);
      case Err(:final message):
        _snack(message);
    }
  }

  Future<void> _pickImage() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'heic'],
    );
    final path = res?.paths.firstOrNull;
    if (path == null) return;
    await _processSource(File(path));
  }

  Future<void> _processSource(File source) async {
    setState(() {
      _busy = true;
      _status = 'Reading receipt with Apple Vision…';
    });
    final ocr = await OcrService.instance.recognize(image: source);
    if (!mounted) return;
    switch (ocr) {
      case Ok(:final value):
        final draft = ReceiptExtractionService.instance.extract(value);
        setState(() {
          _source = source;
          _busy = false;
          _status = '';
          _rawText = value.plainText;
          _vendorController.text = draft.vendor ?? '';
          _totalController.text = draft.total ?? '';
          _taxController.text = draft.tax ?? '';
          _currencyController.text = draft.currency;
          _date = draft.date;
          _dateController.text =
              draft.date == null ? '' : _formatDate(draft.date!);
        });
        HapticsService.instance.success();
      case Err(:final message):
        setState(() {
          _busy = false;
          _status = '';
        });
        _snack(message);
    }
  }

  Future<void> _pickDate() async {
    HapticsService.instance.tap();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateController.text = _formatDate(picked);
      });
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_source == null) return;
    HapticsService.instance.tap();
    final archived =
        await ExpenseLedgerService.instance.archiveSource(_source!);
    final receipt = Receipt(
      id: ExpenseLedgerService.instance.nextId(),
      capturedAt: DateTime.now().toUtc(),
      date: _date,
      vendor: _vendorController.text.trim().isEmpty
          ? null
          : _vendorController.text.trim(),
      total: _totalController.text.trim().isEmpty
          ? null
          : _totalController.text.trim(),
      tax: _taxController.text.trim().isEmpty
          ? null
          : _taxController.text.trim(),
      currency: _currencyController.text.trim().isEmpty
          ? 'USD'
          : _currencyController.text.trim().toUpperCase(),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      category: _categoryController.text.trim().isEmpty
          ? null
          : _categoryController.text.trim(),
      sourcePath: archived.path,
      rawText: _rawText,
    );
    await ExpenseLedgerService.instance.save(receipt);
    await AuditService.instance.record(
      tool: 'receipt',
      inputFile: _source,
      params: {
        'hasDate': '${receipt.date != null}',
        'hasVendor': '${receipt.vendor != null}',
        'hasTotal': '${receipt.total != null}',
        'currency': receipt.currency,
        if (receipt.category != null) 'category': receipt.category!,
      },
    );
    HapticsService.instance.success();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ExpenseLedgerScreen()),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Expense ledger',
            onPressed: () {
              HapticsService.instance.tap();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ExpenseLedgerScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthBody(
          child: _busy ? _busyView() : _editorView(),
        ),
      ),
    );
  }

  Widget _busyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_status,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              )),
        ],
      ),
    );
  }

  Widget _editorView() {
    if (_source == null) {
      return _pickerView();
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Center(child: PrivacyBadge()),
        const SizedBox(height: 12),
        _sourceThumbnail(),
        const SizedBox(height: 16),
        _field(
          label: 'Date',
          controller: _dateController,
          readOnly: true,
          onTap: _pickDate,
          icon: Icons.calendar_today_outlined,
        ),
        const SizedBox(height: 10),
        _field(
          label: 'Vendor',
          controller: _vendorController,
          icon: Icons.store_outlined,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _field(
                label: 'Total',
                controller: _totalController,
                icon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              child: _field(
                label: 'Currency',
                controller: _currencyController,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _field(
          label: 'Tax (optional)',
          controller: _taxController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
          ],
        ),
        const SizedBox(height: 10),
        _categoryField(),
        const SizedBox(height: 10),
        _field(
          label: 'Note (optional)',
          controller: _noteController,
          icon: Icons.notes_outlined,
          maxLines: 2,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save to ledger'),
          onPressed: _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Re-scan / pick another receipt'),
          onPressed: () => setState(() {
            _source = null;
            _vendorController.clear();
            _totalController.clear();
            _taxController.clear();
            _dateController.clear();
            _categoryController.clear();
            _noteController.clear();
            _date = null;
          }),
        ),
      ],
    );
  }

  Widget _pickerView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(child: PrivacyBadge()),
        const SizedBox(height: 18),
        const Icon(
          Icons.receipt_outlined,
          color: AppColors.primary,
          size: 56,
        ),
        const SizedBox(height: 14),
        const Text(
          'Snap a receipt',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Apple Vision pulls the date, vendor, total, tax, and '
          'currency on-device. You confirm, then it lands in your '
          'ledger ready for the year-end CSV export.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        if (_scannerAvailable == true)
          FilledButton.icon(
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Scan with camera'),
            onPressed: _scan,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Pick photo'),
          onPressed: _pickImage,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _sourceThumbnail() {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        image: DecorationImage(
          image: FileImage(_source!),
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    IconData? icon,
    bool readOnly = false,
    VoidCallback? onTap,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _categoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          label: 'Category (optional)',
          controller: _categoryController,
          icon: Icons.category_outlined,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _commonCategories
              .map((c) => InputChip(
                    label: Text(c, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      HapticsService.instance.select();
                      _categoryController.text = c;
                    },
                  ))
              .toList(),
        ),
      ],
    );
  }
}
