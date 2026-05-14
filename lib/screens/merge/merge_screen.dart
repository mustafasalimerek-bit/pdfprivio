import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_merge_service.dart';
import '../../providers/merge_providers.dart';
import '../../widgets/pdf_doc_tile.dart';
import '../../widgets/privacy_badge.dart';
import '../../widgets/progress_overlay.dart';
import 'merge_result_screen.dart';

class MergeScreen extends ConsumerStatefulWidget {
  const MergeScreen({super.key});

  @override
  ConsumerState<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends ConsumerState<MergeScreen> {
  CancellationToken? _activeCancel;

  Future<void> _pickFiles() async {
    HapticsService.instance.tap();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (result == null) return;

    final files = result.paths
        .whereType<String>()
        .map((p) => File(p))
        .toList();
    if (files.isEmpty) return;

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

  Future<void> _merge() async {
    final docs = ref.read(mergeWorkspaceProvider);
    if (docs.length < 2) return;

    HapticsService.instance.tap();
    final cancel = CancellationToken();
    _activeCancel = cancel;
    ref.read(mergeProgressProvider.notifier).state = 0;

    final result = await PdfMergeService.instance.merge(
      documents: docs,
      onProgress: (p) {
        if (mounted) {
          ref.read(mergeProgressProvider.notifier).state = p;
        }
      },
      cancel: cancel,
    );

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
            ),
          ),
        );
        // Clear the workspace once the user has dismissed the result —
        // re-opening Merge from the home tile should feel like a fresh start.
        if (mounted) {
          ref.read(mergeWorkspaceProvider.notifier).clear();
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
    final canMerge = docs.length >= 2 && progress == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge PDFs'),
        actions: [
          if (docs.isNotEmpty)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                ref.read(mergeWorkspaceProvider.notifier).clear();
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
                  child: docs.isEmpty
                      ? _EmptyState(onAdd: _pickFiles)
                      : _DocList(
                          docs: docs,
                          totalPages: totalPages,
                          onAdd: _pickFiles,
                        ),
                ),
                if (canMerge)
                  _MergeButton(count: docs.length, onTap: _merge),
              ],
            ),
          ),
          if (progress != null)
            ProgressOverlay(
              progress: progress,
              title: 'Merging ${docs.length} PDFs',
              subtitle: 'Processing on this device — no upload',
              onCancel: () {
                _activeCancel?.cancel();
              },
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

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
                Icons.library_books_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Combine PDFs into one',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add two or more PDFs. Drag to reorder before merging.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add PDFs'),
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

class _DocList extends ConsumerWidget {
  final List<PdfDocument> docs;
  final int totalPages;
  final VoidCallback onAdd;

  const _DocList({
    required this.docs,
    required this.totalPages,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${docs.length} PDFs · $totalPages page${totalPages == 1 ? '' : 's'} total',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add more'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: docs.length,
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              HapticsService.instance.drop();
              ref
                  .read(mergeWorkspaceProvider.notifier)
                  .reorder(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final doc = docs[index];
              return PdfDocTile(
                key: ValueKey(doc.path),
                document: doc,
                onRemove: () {
                  HapticsService.instance.select();
                  ref.read(mergeWorkspaceProvider.notifier).removeAt(index);
                },
                reorderHandle: ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_handle,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MergeButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _MergeButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            'Merge $count PDFs',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
