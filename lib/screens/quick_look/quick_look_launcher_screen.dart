import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/audit_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/quick_look_service.dart';
import '../../data/services/share_intent_service.dart';
import '../../widgets/tool_chrome.dart';

/// Thin launcher screen that bounces the user into the system
/// QLPreviewController (Live Text + Visual Look Up + Markup + Share).
/// Empty state matches the rest of the tool screens; on share-extension
/// entry we skip the picker and open the shared file directly.
class QuickLookLauncherScreen extends ConsumerStatefulWidget {
  const QuickLookLauncherScreen({super.key});

  @override
  ConsumerState<QuickLookLauncherScreen> createState() =>
      _QuickLookLauncherScreenState();
}

class _QuickLookLauncherScreenState
    extends ConsumerState<QuickLookLauncherScreen> {
  @override
  void initState() {
    super.initState();
    // Only auto-launch when the share extension handed us a file —
    // otherwise show the editorial empty state and let the user tap
    // the CTA so the screen feels like every other tool.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = PendingSharedFile.consume();
      if (pending != null) _show(pending);
    });
  }

  Future<void> _pickAndShow() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'heic'],
    );
    final path = res?.paths.firstOrNull;
    if (path == null) return;
    await _show(File(path));
  }

  Future<void> _show(File file) async {
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
      appBar: AppBar(
        title: const Text('Live Text view'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ToolEmptyState(
          heroIcon: Icons.center_focus_strong,
          title: 'Open in Live Text',
          subtitle: 'Apple system viewer — select, Look Up, Markup',
          primaryLabel: 'Pick a file',
          onPrimary: _pickAndShow,
        ),
      ),
    );
  }
}
