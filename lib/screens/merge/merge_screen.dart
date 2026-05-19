import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_merge_service.dart';
import '../../data/services/scan_pickup_service.dart';
import '../../data/services/share_intent_service.dart';
import '../../providers/merge_providers.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';
import 'merge_pages_screen.dart';
import 'merge_result_screen.dart';

class MergeScreen extends ConsumerStatefulWidget {
  const MergeScreen({super.key});

  @override
  ConsumerState<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends ConsumerState<MergeScreen> {
  CancellationToken? _activeCancel;

  @override
  void initState() {
    super.initState();
    final pending = PendingSharedFile.consume();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Seed the workspace with the shared file. User will then add
        // one or more additional files via the picker.
        await ref.read(mergeWorkspaceProvider.notifier).add([pending]);
        if (mounted) HapticsService.instance.select();
      });
    }
  }

  Future<void> _pickFiles() async {
    HapticsService.instance.tap();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (result == null) return;

    final files =
        result.paths.whereType<String>().map((p) => File(p)).toList();
    if (files.isEmpty) return;

    // Adding new docs invalidates a prior page-level customization, so we
    // clear it. The user can re-enter Customize and start fresh.
    if (ref.read(hasPageCustomizationProvider)) {
      ref.read(mergePageRefsProvider.notifier).reset();
    }

    final failed = await ref.read(mergeWorkspaceProvider.notifier).add(files);
    if (failed.isNotEmpty && mounted) {
      _showAddFailureSnack(failed);
    } else if (failed.isEmpty) {
      HapticsService.instance.select();
    }
  }

  void _showAddFailureSnack(
    List<({File file, Err<PdfDocument> error})> failed,
  ) {
    HapticsService.instance.error();
    final passworded =
        failed.where((f) => f.error.kind == FailureKind.needsPassword).length;
    final corrupted =
        failed.where((f) => f.error.kind == FailureKind.corrupted).length;
    final other = failed.length - passworded - corrupted;

    final parts = <String>[];
    if (passworded > 0) parts.add('$passworded password-protected');
    if (corrupted > 0) parts.add('$corrupted damaged');
    if (other > 0) parts.add('$other other error${other == 1 ? '' : 's'}');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Couldn't add: ${parts.join(', ')}"),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _scanPdf() async {
    HapticsService.instance.tap();
    final res = await ScanPickupService.instance.scanToPdf();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        if (ref.read(hasPageCustomizationProvider)) {
          ref.read(mergePageRefsProvider.notifier).reset();
        }
        final failed =
            await ref.read(mergeWorkspaceProvider.notifier).add([value]);
        if (failed.isNotEmpty && mounted) {
          _showAddFailureSnack(failed);
        } else if (failed.isEmpty) {
          HapticsService.instance.select();
        }
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

  Future<void> _customizePages() async {
    HapticsService.instance.tap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MergePagesScreen()),
    );
    // No further action needed — page refs persist in the provider and the
    // merge button below picks them up automatically.
  }

  Future<void> _merge() async {
    final docs = ref.read(mergeWorkspaceProvider);
    if (docs.length < 2) return;

    HapticsService.instance.tap();
    final cancel = CancellationToken();
    _activeCancel = cancel;
    ref.read(mergeProgressProvider.notifier).state = 0;

    final pageRefs = ref.read(mergePageRefsProvider);
    final usePageLevel = pageRefs.isNotEmpty;

    final Result<File> result;
    if (usePageLevel) {
      result = await PdfMergeService.instance.mergePages(
        pages: pageRefs,
        onProgress: (p) {
          if (mounted) {
            ref.read(mergeProgressProvider.notifier).state = p;
          }
        },
        cancel: cancel,
      );
    } else {
      result = await PdfMergeService.instance.merge(
        documents: docs,
        onProgress: (p) {
          if (mounted) {
            ref.read(mergeProgressProvider.notifier).state = p;
          }
        },
        cancel: cancel,
      );
    }

    if (!mounted) return;
    ref.read(mergeProgressProvider.notifier).state = null;
    _activeCancel = null;

    switch (result) {
      case Ok<File>(:final value):
        HapticsService.instance.success();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MergeResultScreen(
              outputFile: value,
              sourceCount: docs.length,
              toolLabel: 'Merged',
              toolIdForUsage: 'merge',
              pageCount: usePageLevel ? pageRefs.length : null,
            ),
          ),
        );
        // Fresh-start for the next visit.
        if (mounted) {
          ref.read(mergeWorkspaceProvider.notifier).clear();
          ref.read(mergePageRefsProvider.notifier).reset();
        }
      case Err<File>(:final kind, :final message):
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
    final docs = ref.watch(mergeWorkspaceProvider);
    final totalPages = ref.watch(mergeTotalPagesProvider);
    final progress = ref.watch(mergeProgressProvider);
    final pageRefs = ref.watch(mergePageRefsProvider);
    final hasCustom = pageRefs.isNotEmpty;
    final canMerge = docs.length >= 2 && progress == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge PDFs'),
        centerTitle: true,
        actions: [
          if (docs.isNotEmpty)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                ref.read(mergeWorkspaceProvider.notifier).clear();
                ref.read(mergePageRefsProvider.notifier).reset();
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: MaxWidthBody(
        child: Stack(
          children: [
            SafeArea(
              child: docs.isEmpty
                  ? _EmptyState(onAdd: _pickFiles, onScan: _scanPdf)
                  : Column(
                      children: [
                        Expanded(
                          child: _DocList(
                            docs: docs,
                            totalPages: totalPages,
                            customPageCount: hasCustom ? pageRefs.length : null,
                            onAdd: _pickFiles,
                            onCustomize:
                                docs.length >= 2 ? _customizePages : null,
                          ),
                        ),
                        if (canMerge)
                          _MergeButton(
                            count: docs.length,
                            customPageCount:
                                hasCustom ? pageRefs.length : null,
                            onTap: _merge,
                          ),
                      ],
                    ),
            ),
            if (progress != null)
              ProgressOverlay(
                progress: progress,
                title: hasCustom
                    ? 'Merging ${pageRefs.length} pages'
                    : 'Merging ${docs.length} PDFs',
                subtitle: 'Processing on this device — no upload',
                onCancel: () {
                  _activeCancel?.cancel();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onScan;
  const _EmptyState({required this.onAdd, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return ToolEmptyState(
      heroIcon: Icons.content_copy_outlined,
      title: 'Combine PDFs into one',
      subtitle: 'Add 2 or more files to begin',
      primaryLabel: 'Add files',
      primaryIcon: Icons.add,
      onPrimary: onAdd,
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

class _DocList extends ConsumerWidget {
  final List<PdfDocument> docs;
  final int totalPages;
  final int? customPageCount;
  final VoidCallback onAdd;
  final VoidCallback? onCustomize;

  const _DocList({
    required this.docs,
    required this.totalPages,
    required this.customPageCount,
    required this.onAdd,
    required this.onCustomize,
  });

  String _bytesSummary() {
    final total = docs.fold<int>(0, (a, d) => a + d.sizeBytes);
    return formatBytes(total);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Center(
            child: Text(
              customPageCount != null
                  ? '$customPageCount pages chosen from ${docs.length} files'
                  : '${docs.length} file${docs.length == 1 ? '' : 's'} · $totalPages page${totalPages == 1 ? '' : 's'} · ~${_bytesSummary()}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ReorderableListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: docs.length,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, _, _) => Material(
                      color: Colors.transparent,
                      child: child,
                    ),
                    onReorder: (oldIndex, newIndex) {
                      HapticsService.instance.drop();
                      ref
                          .read(mergeWorkspaceProvider.notifier)
                          .reorder(oldIndex, newIndex);
                      if (ref.read(hasPageCustomizationProvider)) {
                        ref.read(mergePageRefsProvider.notifier).reset();
                      }
                    },
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final isLast = index == docs.length - 1;
                      return Column(
                        key: ValueKey(doc.path),
                        children: [
                          _MergeFileRow(
                            document: doc,
                            index: index,
                            onRemove: () {
                              HapticsService.instance.select();
                              ref
                                  .read(mergeWorkspaceProvider.notifier)
                                  .removeAt(index);
                              if (ref.read(hasPageCustomizationProvider)) {
                                ref
                                    .read(mergePageRefsProvider.notifier)
                                    .reset();
                              }
                            },
                          ),
                          if (!isLast)
                            Padding(
                              padding: const EdgeInsets
                                  .symmetric(horizontal: 16),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: AppColors.border
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'Add another file',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
                if (onCustomize != null) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: onCustomize,
                    icon: Icon(
                      customPageCount != null
                          ? Icons.check_circle
                          : Icons.grid_view_outlined,
                      size: 16,
                    ),
                    label: Text(
                      customPageCount != null
                          ? 'Edit page selection'
                          : 'Customize page-by-page',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Single row inside the file-list card. Document glyph on the
/// left, filename + "X pages · Y KB" on the right, drag handle on
/// the far right. No remove button visible — the older "X to
/// remove" affordance moves into a row long-press / swipe (TODO).
class _MergeFileRow extends StatelessWidget {
  final PdfDocument document;
  final int index;
  final VoidCallback onRemove;

  const _MergeFileRow({
    required this.document,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismiss_${document.path}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: AppColors.error.withValues(alpha: 0.1),
        child: const Icon(Icons.delete_outline, color: AppColors.error),
      ),
      onDismissed: (_) => onRemove(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            // Mini paper glyph — lines on a card.
            Container(
              width: 38,
              height: 46,
              padding: const EdgeInsets.fromLTRB(6, 9, 6, 0),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in [22.0, 18.0, 14.0])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Container(
                        width: w,
                        height: 2,
                        decoration: BoxDecoration(
                          color: AppColors.iconTint,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    document.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${document.pageCount} page${document.pageCount == 1 ? '' : 's'} · ${formatBytes(document.sizeBytes)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Icon(
                  Icons.drag_handle,
                  color: AppColors.textTertiary,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MergeButton extends StatelessWidget {
  final int count;
  final int? customPageCount;
  final VoidCallback onTap;

  const _MergeButton({
    required this.count,
    required this.customPageCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = customPageCount != null
        ? 'Merge $customPageCount pages'
        : 'Merge $count files';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.content_copy_outlined, size: 18),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }
}
