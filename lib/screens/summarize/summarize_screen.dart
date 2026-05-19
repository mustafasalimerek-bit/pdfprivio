import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/result.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/scan_pickup_service.dart';
import '../../data/services/share_intent_service.dart';
import '../../data/services/summarization_service.dart';
import '../../widgets/tool_chrome.dart';

/// Summarise a PDF using Apple Intelligence on-device.
///
/// Honest UX: if the model isn't available (older iOS, non-Apple-
/// Intelligence device, model still downloading), we say so clearly
/// and fall back to plain text extraction. We never silently fail.
class SummarizeScreen extends ConsumerStatefulWidget {
  const SummarizeScreen({super.key});

  @override
  ConsumerState<SummarizeScreen> createState() => _SummarizeScreenState();
}

class _SummarizeScreenState extends ConsumerState<SummarizeScreen> {
  SummarizationAvailability _availability = SummarizationAvailability.unknown;
  File? _file;
  String? _extractedText;
  SummarizationResult? _result;
  bool _checkingAvailability = true;
  bool _busy = false;
  double _progress = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _checkAvailability();
    final pending = PendingSharedFile.consume();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFromFile(pending);
      });
    }
  }

  Future<void> _checkAvailability() async {
    final avail = await SummarizationService.instance.availability();
    if (!mounted) return;
    setState(() {
      _availability = avail;
      _checkingAvailability = false;
    });
  }

  Future<void> _pickPdf() async {
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

  Future<void> _loadFromFile(File file) async {
    setState(() {
      _file = file;
      _extractedText = null;
      _result = null;
      _busy = true;
      _progress = 0;
      _status = 'Reading PDF…';
    });

    final text = await SummarizationService.instance.extractText(file);
    if (!mounted) return;

    if (text.trim().isEmpty) {
      setState(() {
        _busy = false;
        _status = 'No text found in PDF';
        _extractedText = '';
      });
      _showSnack(
        'No text found — if this is a scanned PDF, run OCR first.',
      );
      return;
    }

    setState(() {
      _extractedText = text;
      _busy = false;
      _status = 'Ready — ${_formatChars(text.length)} of text';
    });
    HapticsService.instance.select();

    // Auto-run summary if Apple Intelligence is ready.
    if (_availability.isReady) {
      await _runSummary();
    }
  }

  Future<void> _runSummary() async {
    final text = _extractedText;
    if (text == null || text.isEmpty || !_availability.isReady) return;
    HapticsService.instance.tap();
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Summarising…';
      _result = null;
    });

    final result = await SummarizationService.instance.summarize(
      text: text,
      onProgress: (p, msg) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _status = msg;
        });
      },
    );
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _busy = false;
        _status = "Summary couldn't be generated.";
      });
      HapticsService.instance.error();
      _showSnack('Apple Intelligence returned no summary.');
      return;
    }

    setState(() {
      _busy = false;
      _result = result;
      _status = 'Done';
    });
    HapticsService.instance.select();

    await AuditService.instance.record(
      tool: 'summarize',
      inputFile: _file,
      params: {
        'charactersIn': '${result.charactersIn}',
        'wasChunked': '${result.wasChunked}',
        'chunkCount': '${result.chunkCount}',
        'elapsedMs': '${result.elapsed.inMilliseconds}',
      },
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  void _copySummary() {
    final summary = _result?.summary;
    if (summary == null) return;
    HapticsService.instance.tap();
    Clipboard.setData(ClipboardData(text: summary));
    _showSnack('Summary copied');
  }

  String _formatChars(int n) {
    if (n < 1000) return '$n chars';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}K chars';
    return '${(n / 1000).round()}K chars';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Summarize PDF'),
        centerTitle: true,
        actions: [
          if (_file != null)
            IconButton(
              icon: const Icon(Icons.file_open_outlined),
              tooltip: 'Pick another PDF',
              onPressed: _pickPdf,
            ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthBody(
          child: Column(
            children: [
              if (!_availability.isReady && !_checkingAvailability)
                _AvailabilityBanner(availability: _availability),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_checkingAvailability) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_file == null) {
      return _EmptyState(
        availability: _availability,
        onPick: _pickPdf,
        onScan: _scanPdf,
      );
    }
    if (_busy) {
      return _BusyState(progress: _progress, status: _status);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _FileHeader(file: _file!, status: _status),
        const SizedBox(height: 12),
        if (_result != null) ...[
          _ResultCard(result: _result!, onCopy: _copySummary),
        ] else if (_extractedText != null && _extractedText!.isNotEmpty)
          _ExtractedTextCard(
            text: _extractedText!,
            canRun: _availability.isReady,
            onRun: _runSummary,
          ),
      ],
    );
  }
}

class _AvailabilityBanner extends StatelessWidget {
  final SummarizationAvailability availability;
  const _AvailabilityBanner({required this.availability});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              availability.message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.warning,
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
  final SummarizationAvailability availability;
  final VoidCallback onPick;
  final VoidCallback onScan;
  const _EmptyState({
    required this.availability,
    required this.onPick,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return ToolEmptyState(
      heroIcon: Icons.auto_awesome,
      title: 'Summarize a PDF',
      subtitle: 'On-device Apple Intelligence',
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

class _BusyState extends StatelessWidget {
  final double progress;
  final String status;
  const _BusyState({required this.progress, required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.primary, size: 48),
            const SizedBox(height: 16),
            Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              color: AppColors.primary,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              minHeight: 6,
            ),
            const SizedBox(height: 12),
            const Text(
              'Running entirely on this device. Nothing leaves it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileHeader extends StatelessWidget {
  final File file;
  final String status;
  const _FileHeader({required this.file, required this.status});

  @override
  Widget build(BuildContext context) {
    final name = file.path.split('/').last;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
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

class _ExtractedTextCard extends StatelessWidget {
  final String text;
  final bool canRun;
  final VoidCallback onRun;
  const _ExtractedTextCard({
    required this.text,
    required this.canRun,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.text_snippet_outlined,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Extracted text',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${(text.length / 1000).round()}K chars',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Text(
                text.length > 2000 ? '${text.substring(0, 2000)}…' : text,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (canRun)
            FilledButton.icon(
              onPressed: onRun,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Summarise with Apple Intelligence'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'AI summary unavailable on this device — see banner above. '
                'You can still copy the extracted text above.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final SummarizationResult result;
  final VoidCallback onCopy;
  const _ResultCard({required this.result, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Summary',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                tooltip: 'Copy',
                onPressed: onCopy,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            result.summary,
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined,
                    color: AppColors.primary, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'On-device · ${formatBytes(result.charactersIn)} of text → '
                    '${result.wasChunked ? "${result.chunkCount} chunks · " : ""}'
                    '${result.elapsed.inSeconds}s',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
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
