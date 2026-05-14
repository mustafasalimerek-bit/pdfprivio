import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../core/theme/colors.dart';
import '../../data/services/haptics_service.dart';
import '../../providers/merge_providers.dart';
import '../../widgets/pdf_page_tile.dart';
import '../../widgets/privacy_badge.dart';

/// Grid view that lets the user reorder and remove individual pages across
/// every source document before merging.
///
/// Opening this screen for the first time (when the page list is empty)
/// seeds the grid with all pages from the workspace in current doc order;
/// from there the user is dragging pages around freely.
class MergePagesScreen extends ConsumerStatefulWidget {
  const MergePagesScreen({super.key});

  @override
  ConsumerState<MergePagesScreen> createState() => _MergePagesScreenState();
}

class _MergePagesScreenState extends ConsumerState<MergePagesScreen> {
  @override
  void initState() {
    super.initState();
    // If the user hasn't customized yet, seed from current workspace.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final existing = ref.read(mergePageRefsProvider);
      if (existing.isEmpty) {
        final docs = ref.read(mergeWorkspaceProvider);
        ref
            .read(mergePageRefsProvider.notifier)
            .initializeFromWorkspace(docs);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(mergePageRefsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder pages'),
        actions: [
          if (pages.isNotEmpty)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                ref.read(mergePageRefsProvider.notifier).reset();
                final docs = ref.read(mergeWorkspaceProvider);
                ref
                    .read(mergePageRefsProvider.notifier)
                    .initializeFromWorkspace(docs);
              },
              child: const Text('Reset order'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const PrivacyBadge(compact: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${pages.length} pages',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Long-press a page to drag it. Tap × to remove.',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: pages.isEmpty
                  ? const Center(
                      child: Text(
                        'No pages — go back and add PDFs.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ReorderableGridView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.72,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: pages.length,
                      onReorder: (oldIndex, newIndex) {
                        HapticsService.instance.drop();
                        ref
                            .read(mergePageRefsProvider.notifier)
                            .reorder(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final ref0 = pages[index];
                        return PdfPageTile(
                          key: ValueKey('${ref0.document.path}|'
                              '${ref0.pageIndex}|$index'),
                          pageRef: ref0,
                          onRemove: () {
                            HapticsService.instance.select();
                            ref
                                .read(mergePageRefsProvider.notifier)
                                .removeAt(index);
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        HapticsService.instance.tap();
                        ref.read(mergePageRefsProvider.notifier).reset();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: const Text('Use doc order'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: pages.isEmpty
                          ? null
                          : () {
                              HapticsService.instance.select();
                              Navigator.of(context).pop();
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Use ${pages.length} pages'),
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
