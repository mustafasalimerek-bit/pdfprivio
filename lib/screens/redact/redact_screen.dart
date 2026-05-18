import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../data/services/pdf_redact_service.dart';
import '../../data/services/recent_files_service.dart';
import '../../data/services/scan_pickup_service.dart';
import '../../data/services/share_intent_service.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';

class RedactScreen extends ConsumerStatefulWidget {
  final PdfDocument? initialDoc;
  final List<String>? initialSearches;
  final bool initialCaseSensitive;
  final String? heroTitle;

  const RedactScreen({
    super.key,
    this.initialDoc,
    this.initialSearches,
    this.initialCaseSensitive = false,
    this.heroTitle,
  });

  @override
  ConsumerState<RedactScreen> createState() => _RedactScreenState();
}

class _RedactScreenState extends ConsumerState<RedactScreen> {
  PdfDocument? _doc;
  final List<String> _searches = [];
  final TextEditingController _input = TextEditingController();
  bool _caseSensitive = false;
  bool _makeSearchable = true;
  double? _progress;
  String? _status;
  CancellationToken? _cancel;

  @override
  void initState() {
    super.initState();
    _doc = widget.initialDoc;
    _caseSensitive = widget.initialCaseSensitive;
    if (widget.initialSearches != null) {
      _searches.addAll(widget.initialSearches!.toSet());
    }
    // Pre-load file handed in by "Share to Privio".
    if (_doc == null) {
      final pending = PendingSharedFile.consume();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadFromFile(pending);
        });
      }
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadFromFile(File file) async {
    final outcome = await PdfMetadataService.instance.inspect(file);
    if (!mounted) return;
    switch (outcome) {
      case Ok(:final value):
        setState(() => _doc = value);
        HapticsService.instance.select();
      case Err(:final kind, :final message):
        HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kind == FailureKind.needsPassword
                ? 'This PDF is password-protected — open it elsewhere first.'
                : message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _pick() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = res?.paths.firstOrNull;
    if (path == null) return;
    await _loadFromFile(File(path));
  }

  Future<void> _scanPdf() async {
    HapticsService.instance.tap();
    final res = await ScanPickupService.instance.scanToPdf();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        await _loadFromFile(value);
      case Err(:final kind, :final message):
        if (kind != FailureKind.cancelled) {
          HapticsService.instance.error();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }

  void _addSearch() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (_searches.contains(text)) {
      // Duplicate — silently no-op rather than scolding.
      _input.clear();
      return;
    }
    HapticsService.instance.select();
    setState(() {
      _searches.add(text);
      _input.clear();
    });
  }

  void _removeSearch(int index) {
    HapticsService.instance.tap();
    setState(() => _searches.removeAt(index));
  }

  Future<void> _run() async {
    final doc = _doc;
    if (doc == null || _searches.isEmpty) return;
    HapticsService.instance.tap();

    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _progress = 0;
      _status = 'Starting…';
    });

    final result = await PdfRedactService.instance.redact(
      input: doc,
      searchTexts: _searches,
      caseSensitive: _caseSensitive,
      makeSearchable: _makeSearchable,
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
        unawaited(RecentFilesService.instance.record(
          file: value.file,
          toolLabel: 'Redacted',
        ));
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _RedactResultScreen(outcome: value),
          ),
        );
        if (mounted) {
          setState(() {
            _doc = null;
            _searches.clear();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Redact'),
        centerTitle: true,
        actions: [
          if (doc != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(() {
                  _doc = null;
                  _searches.clear();
                });
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: doc == null
                ? _EmptyState(onPick: _pick, onScan: _scanPdf)
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          children: [
                            _DocSummary(doc: doc),
                            const SizedBox(height: 14),
                            const Text(
                              "Texts to redact",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _input,
                                    onSubmitted: (_) => _addSearch(),
                                    decoration: InputDecoration(
                                      hintText: 'Name, account #, address…',
                                      filled: true,
                                      fillColor: AppColors.surface,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _addSearch,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Icon(Icons.add, size: 20),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (_searches.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: AppColors.textTertiary,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "Add one or more strings. We'll find "
                                        "every line containing them and "
                                        'cover it with a black rectangle.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (var i = 0; i < _searches.length; i++)
                                    InputChip(
                                      label: Text(
                                        _searches[i],
                                        style: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                      onDeleted: () => _removeSearch(i),
                                      backgroundColor: AppColors.surface,
                                      side: const BorderSide(
                                        color: AppColors.border,
                                      ),
                                      deleteIconColor: AppColors.error,
                                    ),
                                ],
                              ),
                            const SizedBox(height: 14),
                            SwitchListTile(
                              title: const Text(
                                'Case-sensitive',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Off: "John" matches "JOHN" and "john"',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              value: _caseSensitive,
                              onChanged: (v) {
                                HapticsService.instance.select();
                                setState(() => _caseSensitive = v);
                              },
                              activeThumbColor: AppColors.primary,
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.success
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.success
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.verified_outlined,
                                    size: 16,
                                    color: AppColors.success,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Real redaction: matched words are "
                                      "rasterized into the page and the "
                                      "original text layer is removed. "
                                      "Copy-paste, Cmd+F, and PDF parsers "
                                      "all see only black bars.",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            _SearchableToggle(
                              value: _makeSearchable,
                              onChanged: (v) {
                                HapticsService.instance.select();
                                setState(() => _makeSearchable = v);
                              },
                            ),
                            const SizedBox(height: 10),
                            const DisclaimerBanner(
                              message: 'Redactions cover the matching '
                                  'words on each page. Embedded objects, '
                                  'attached files, metadata, and prior '
                                  'versions are not touched — open the '
                                  'output in another viewer to verify '
                                  'before sending externally.',
                            ),
                          ],
                        ),
                      ),
                      if (_progress == null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: ToolPrimaryButton(
                            label: _searches.isEmpty
                                ? 'Add at least one search text'
                                : 'Redact ${_searches.length} term'
                                    '${_searches.length == 1 ? '' : 's'}',
                            icon: Icons.format_color_fill,
                            enabled: _searches.isNotEmpty,
                            onTap: _run,
                          ),
                        ),
                    ],
                  ),
          ),
          if (_progress != null)
            ProgressOverlay(
              progress: _progress,
              title: 'Redacting',
              subtitle: _status ?? 'Processing on this device — no upload',
              onCancel: () => _cancel?.cancel(),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  final VoidCallback onScan;
  const _EmptyState({required this.onPick, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return ToolEmptyState(
      heroIcon: Icons.format_color_fill,
      title: 'Redact text',
      subtitle: 'Black-bar names, IDs, addresses — true redaction',
      primaryLabel: 'Pick a PDF',
      onPrimary: onPick,
      altSources: [
        ToolAltSource(
          icon: Icons.camera_alt_outlined,
          label: 'Scan',
          onTap: onScan,
        ),
      ],
    );
  }
}

class _DocSummary extends StatelessWidget {
  final PdfDocument doc;
  const _DocSummary({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.picture_as_pdf_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${doc.pageCount} pages · ${formatBytes(doc.sizeBytes)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RedactResultScreen extends StatelessWidget {
  final RedactOutcome outcome;
  const _RedactResultScreen({required this.outcome});

  Future<void> _share(BuildContext context) async {
    HapticsService.instance.tap();
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(outcome.file.path)],
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _open() async {
    HapticsService.instance.tap();
    await OpenFilex.open(outcome.file.path);
  }

  @override
  Widget build(BuildContext context) {
    final noMatches = outcome.matchesFound == 0;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Done'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: (noMatches
                            ? AppColors.warning
                            : AppColors.success)
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    noMatches ? Icons.search_off : Icons.check_circle,
                    color: noMatches
                        ? AppColors.warning
                        : AppColors.success,
                    size: 52,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  noMatches
                      ? 'No matches found'
                      : '${outcome.matchesFound} redaction'
                          '${outcome.matchesFound == 1 ? '' : 's'} applied',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  noMatches
                      ? "Your search terms didn't appear in this PDF."
                      : 'Across ${outcome.pagesAffected} page'
                          '${outcome.pagesAffected == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              const Center(child: PrivacyBadge()),
              if (!noMatches) ...[
                const SizedBox(height: 14),
                const DisclaimerBanner(
                  message: 'Before sharing externally: open the output '
                      'in a different PDF viewer and check no PII '
                      'bleeds through embedded objects, attachments, '
                      'or metadata.',
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _share(context),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchableToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SearchableToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: value
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.find_in_page_outlined,
              size: 18,
              color: value ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Keep non-redacted text searchable',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value
                        ? 'OCR runs on the redacted output — Cmd+F still '
                            'works on everything except the black bars'
                        : 'Output is an image-only PDF — fastest, smallest, '
                            'but Cmd+F finds nothing',
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
