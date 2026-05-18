import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/receipt.dart';
import '../../data/services/expense_ledger_service.dart';
import '../../data/services/haptics_service.dart';

/// Browse and export the on-device expense ledger.
///
/// One row per receipt, newest first. Long-press a row for delete.
/// Toolbar export dumps every receipt to a QuickBooks-friendly CSV
/// via the Share Sheet. v1.0 doesn't support tap-to-edit yet — to
/// fix a wrong field, delete the row and re-scan; v1.1 adds an
/// inline editor.
class ExpenseLedgerScreen extends ConsumerStatefulWidget {
  const ExpenseLedgerScreen({super.key});

  @override
  ConsumerState<ExpenseLedgerScreen> createState() =>
      _ExpenseLedgerScreenState();
}

class _ExpenseLedgerScreenState
    extends ConsumerState<ExpenseLedgerScreen> {
  List<Receipt> _receipts = [];
  double _totalUsd = 0;
  bool _loading = true;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = ExpenseLedgerService.instance.changes.listen((_) => _refresh());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await ExpenseLedgerService.instance.getAll();
    final total =
        await ExpenseLedgerService.instance.totalFor(currency: 'USD');
    if (!mounted) return;
    setState(() {
      _receipts = list;
      _totalUsd = total;
      _loading = false;
    });
  }

  Future<void> _exportCsv() async {
    if (_receipts.isEmpty) return;
    HapticsService.instance.tap();
    final file = await ExpenseLedgerService.instance.exportCsv();
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Privio expense ledger',
      ),
    );
  }

  Future<void> _confirmDelete(Receipt r) async {
    HapticsService.instance.tap();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: Text(
          r.vendor == null
              ? 'This receipt will be removed from your ledger.'
              : 'The receipt from ${r.vendor} will be removed from '
                  'your ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go == true) {
      await ExpenseLedgerService.instance.delete(r.id);
      HapticsService.instance.success();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense ledger'),
        actions: [
          if (_receipts.isNotEmpty)
            IconButton(
              tooltip: 'Export as CSV',
              icon: const Icon(Icons.ios_share),
              onPressed: _exportCsv,
            ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthBody(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_receipts.isEmpty) {
      return const _EmptyState();
    }
    return Column(
      children: [
        _SummaryCard(count: _receipts.length, totalUsd: _totalUsd),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: _receipts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ReceiptTile(
              receipt: _receipts[i],
              onDelete: () => _confirmDelete(_receipts[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int count;
  final double totalUsd;
  const _SummaryCard({required this.count, required this.totalUsd});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.simpleCurrency(name: 'USD');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.summarize_outlined,
                color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count receipt${count == 1 ? '' : 's'} '
                    '· ${fmt.format(totalUsd)} USD subtotal',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Tap Share to export every receipt as a '
                    'QuickBooks-friendly CSV.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  final Receipt receipt;
  final VoidCallback onDelete;
  const _ReceiptTile({required this.receipt, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: onDelete,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _Thumbnail(path: receipt.sourcePath),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.vendor ?? '(no vendor)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (receipt.date != null)
                          dateFmt.format(receipt.date!),
                        if (receipt.category != null) receipt.category!,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    receipt.total == null
                        ? '—'
                        : '${receipt.currency} ${receipt.total}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (receipt.tax != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'tax ${receipt.tax}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String path;
  const _Thumbnail({required this.path});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final isImage = ['.png', '.jpg', '.jpeg', '.heic']
        .any((e) => path.toLowerCase().endsWith(e));
    if (!isImage) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.receipt_outlined, size: 20),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        file,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 44,
          height: 44,
          color: AppColors.background,
          child: const Icon(Icons.receipt_outlined, size: 20),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 14),
            const Text(
              'No receipts yet',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Scan or pick a receipt from the capture screen — it '
              'lands here ready for the year-end CSV.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
