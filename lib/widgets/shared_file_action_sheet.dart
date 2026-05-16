import 'dart:io';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/theme/colors.dart';
import '../data/services/haptics_service.dart';
import '../data/services/share_intent_service.dart';

/// Bottom sheet shown when another app (Mail, WhatsApp, Files…) hands
/// PDFPrivio a file via the Share Sheet. The user picks a tool; we copy
/// the file into our Inbox, stash it in [PendingSharedFile], and push
/// the chosen tool's route — the tool reads the pending file in its
/// own initState and skips its usual file picker.
///
/// For PDFs we surface the four highest-intent tools for the lawyer /
/// CPA wedge (Sign, Redact, Merge, OCR). For images there's only one
/// sensible target (Image to PDF), so we route straight there without
/// asking.
class SharedFileActionSheet {
  SharedFileActionSheet._();

  static Future<void> show(
    BuildContext context,
    List<SharedMediaFile> files,
  ) async {
    if (files.isEmpty) return;
    final first = files.first;
    // CFBundleDocumentTypes path drops files in temp / Files
    // sandbox — copy into Inbox first. The PDFPrivioShare /
    // PDFPrivioQuickSign extensions have already moved their file
    // into Documents/Inbox, so importToInbox just no-ops the copy
    // when the source already lives there.
    File workingFile;
    final src = File(first.path);
    if (src.path.contains('/Documents/Inbox/')) {
      workingFile = src;
    } else {
      final imported = await ShareIntentService.importToInbox(first);
      if (imported == null || !context.mounted) return;
      workingFile = imported;
    }

    // Quick Sign / other Action Extensions flagged a tool — skip the
    // chooser sheet and route straight there for the "quick" feel.
    final preferred = ShareIntentService.instance.pendingPreferredAction;
    if (preferred != null) {
      ShareIntentService.instance.clearPreferredAction();
      final route = _routeForAction(preferred);
      if (route != null && context.mounted) {
        PendingSharedFile.set(workingFile);
        await Navigator.of(context).pushNamed(route);
        return;
      }
    }

    final isImage = first.type == SharedMediaType.image;

    if (isImage) {
      // Single obvious action — skip the chooser.
      PendingSharedFile.set(workingFile);
      await Navigator.of(context).pushNamed('/tool/image_to_pdf');
      return;
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _Sheet(file: workingFile),
    );
  }

  /// Map the Action Extension's preferred-action string (set by
  /// PDFPrivioQuickSign etc.) to a named route. Unknown strings fall
  /// back to the chooser sheet.
  static String? _routeForAction(String action) {
    switch (action) {
      case 'sign':
        return '/tool/sign';
      case 'redact':
        return '/tool/redact';
      case 'ocr':
        return '/tool/ocr';
      case 'pii':
        return '/tool/pii';
      case 'merge':
        return '/tool/merge';
      default:
        return null;
    }
  }
}

class _Sheet extends StatelessWidget {
  final File file;
  const _Sheet({required this.file});

  @override
  Widget build(BuildContext context) {
    final name = file.path.split('/').last;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const Text(
            'Shared with PDFPrivio',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 18),
          _ActionTile(
            icon: Icons.draw_outlined,
            title: 'Sign PDF',
            subtitle: 'Draw a signature and place it on the page',
            onTap: () => _open(context, '/tool/sign'),
          ),
          _ActionTile(
            icon: Icons.format_color_fill,
            title: 'Redact',
            subtitle: 'Search words and black them out, permanently (Pro)',
            onTap: () => _open(context, '/tool/redact'),
          ),
          _ActionTile(
            icon: Icons.merge_outlined,
            title: 'Merge with another PDF',
            subtitle: 'Combine this file with one more',
            onTap: () => _open(context, '/tool/merge'),
          ),
          _ActionTile(
            icon: Icons.text_snippet_outlined,
            title: 'OCR — make searchable',
            subtitle: 'Add a text layer so Cmd+F finds words',
            onTap: () => _open(context, '/tool/ocr'),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                // Leave the file in Inbox — user can pick it from any
                // tool's file picker later under "On My iPhone /
                // PDFPrivio / Inbox" in the Files browser.
                Navigator.of(context).pop();
              },
              child: const Text(
                'Just save to Inbox',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, String route) {
    HapticsService.instance.tap();
    PendingSharedFile.set(file);
    Navigator.of(context).pop();
    Navigator.of(context).pushNamed(route);
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
