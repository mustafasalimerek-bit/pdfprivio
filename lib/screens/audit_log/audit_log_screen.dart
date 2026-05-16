import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../data/models/audit_entry.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/haptics_service.dart';

/// Browse + export the on-device audit log. Niche by design — most
/// users will never open this screen; compliance-conscious lawyers /
/// CPAs will hit it once a quarter to pull a CSV for their records
/// or to defend a particular operation in a malpractice dispute.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  List<AuditEntry> _entries = const [];
  bool _loading = true;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = AuditService.instance.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await AuditService.instance.getAll(limit: 500);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _exportCsv() async {
    if (_entries.isEmpty) return;
    HapticsService.instance.tap();
    final file = await AuditService.instance.exportCsv();
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'PDFPrivio audit log (CSV export)',
      ),
    );
  }

  Future<void> _confirmClear() async {
    HapticsService.instance.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear audit log?'),
        content: const Text(
          'This deletes every audit entry from this device. The action '
          'cannot be undone. Tool operations from this point onward '
          'will be logged again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuditService.instance.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export as CSV',
              onPressed: _exportCsv,
            ),
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear log',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries.isEmpty) {
      return const _EmptyState();
    }
    return Column(
      children: [
        _Header(count: _entries.length),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: _entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            itemBuilder: (_, i) => _EntryTile(entry: _entries[i]),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count ${count == 1 ? "entry" : "entries"} · '
              'kept for 90 days · on-device only',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: AppColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'No audit entries yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              "Every Sign, Redact, OCR, Merge, or PII Scan you run gets "
              "recorded here with timestamp + file metadata. Useful for "
              "compliance (ABA Model Rule 1.15, SOX, GDPR) or defending a "
              "specific operation later.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Log lives on this device — never uploaded.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final AuditEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, y · HH:mm');
    final inputLabel = entry.inputFileName ?? '—';
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(_iconFor(entry.tool),
            color: AppColors.primary, size: 18),
      ),
      title: Text(
        _titleFor(entry.tool),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            df.format(entry.timestamp.toLocal()),
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          if (entry.inputFileName != null) ...[
            const SizedBox(height: 1),
            Text(
              inputLabel,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (entry.inputSha256Prefix != null) ...[
            const SizedBox(height: 1),
            Text(
              'sha256:${entry.inputSha256Prefix}…',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontFamily: 'Menlo',
              ),
            ),
          ],
        ],
      ),
      trailing: entry.success
          ? const Icon(Icons.check_circle, color: AppColors.primary, size: 18)
          : Icon(Icons.error_outline, color: AppColors.error, size: 18),
    );
  }

  IconData _iconFor(String tool) {
    switch (tool) {
      case 'sign':
        return Icons.draw_outlined;
      case 'redact':
        return Icons.format_color_fill;
      case 'ocr':
        return Icons.text_snippet_outlined;
      case 'merge':
        return Icons.merge_outlined;
      case 'pii_scan':
        return Icons.shield_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  String _titleFor(String tool) {
    switch (tool) {
      case 'sign':
        return 'Signed PDF';
      case 'redact':
        return 'Redacted PDF';
      case 'ocr':
        return 'OCR — searchable layer added';
      case 'merge':
        return 'Merged PDFs';
      case 'pii_scan':
        return 'Scanned for sensitive data';
      default:
        return tool;
    }
  }
}
