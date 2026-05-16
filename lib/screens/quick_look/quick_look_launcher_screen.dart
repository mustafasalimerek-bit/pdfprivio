import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/quick_look_service.dart';
import '../../data/services/share_intent_service.dart';

/// Thin launcher screen that immediately bounces the user into the
/// system QLPreviewController (Live Text + Visual Look Up + Markup
/// + Share — all the iOS-native PDF interactions). The screen
/// itself only renders while the file picker / QuickLook is on
/// screen, then pops back to wherever the user came from.
class QuickLookLauncherScreen extends ConsumerStatefulWidget {
  const QuickLookLauncherScreen({super.key});

  @override
  ConsumerState<QuickLookLauncherScreen> createState() =>
      _QuickLookLauncherScreenState();
}

class _QuickLookLauncherScreenState
    extends ConsumerState<QuickLookLauncherScreen> {
  bool _busy = false;
  String _status = 'Pick a PDF or image to open';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = PendingSharedFile.consume();
      if (pending != null) {
        _show(pending);
      } else {
        _pickAndShow();
      }
    });
  }

  Future<void> _pickAndShow() async {
    HapticsService.instance.tap();
    setState(() {
      _busy = true;
      _status = 'Pick a file…';
    });
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'heic'],
    );
    final path = res?.paths.firstOrNull;
    if (path == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await _show(File(path));
  }

  Future<void> _show(File file) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = 'Opening in Live Text view…';
    });
    final shown = await QuickLookService.instance.show(file);
    if (shown) {
      await AuditService.instance.record(
        tool: 'quick_look',
        inputFile: file,
        params: const {'viewer': 'QLPreviewController'},
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Text view')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.center_focus_strong,
                size: 56,
                color: AppColors.primary,
              ),
              const SizedBox(height: 14),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (_busy) const CircularProgressIndicator(),
              const SizedBox(height: 12),
              const Text(
                "Opens Apple's system viewer — Live Text lets you "
                "select any text on the page, Visual Look Up identifies "
                "embedded images, Markup adds annotations, all on-device.",
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
      ),
    );
  }
}
