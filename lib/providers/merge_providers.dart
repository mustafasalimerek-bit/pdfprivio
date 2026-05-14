import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/result.dart';
import '../data/models/pdf_document.dart';
import '../data/models/pdf_page_ref.dart';
import '../data/services/pdf_metadata_service.dart';
import '../data/services/pdf_thumbnail_service.dart';

/// Workspace = the ordered list of PDFs the user is preparing to merge.
///
/// Lives in a notifier (not a plain StateProvider) so we can offer
/// reorder/remove/undo semantics later without changing call sites.
class MergeWorkspace extends StateNotifier<List<PdfDocument>> {
  MergeWorkspace() : super(const []);

  /// Inspects each file and appends those that parsed successfully. Returns
  /// the list of files that failed so the UI can show a single summary
  /// (rather than one dialog per bad file).
  Future<List<({File file, Err<PdfDocument> error})>> add(
      List<File> files) async {
    final failed = <({File file, Err<PdfDocument> error})>[];
    final added = <PdfDocument>[];

    for (final file in files) {
      final result = await PdfMetadataService.instance.inspect(file);
      switch (result) {
        case Ok<PdfDocument>(:final value):
          // De-duplicate: dropping the same file twice is almost always a
          // user mistake, not a "merge two copies" intent.
          if (!state.any((d) => d.path == value.path)) {
            added.add(value);
          }
        case Err<PdfDocument>():
          failed.add((file: file, error: result));
      }
    }

    if (added.isNotEmpty) {
      state = [...state, ...added];
    }
    return failed;
  }

  void reorder(int oldIndex, int newIndex) {
    // Flutter's ReorderableListView reports newIndex post-removal; normalize.
    final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(adjustedNew, item);
    state = list;
  }

  void removeAt(int index) {
    final removed = state[index];
    state = [...state]..removeAt(index);
    PdfThumbnailService.instance.evict(removed);
  }

  void clear() {
    for (final d in state) {
      PdfThumbnailService.instance.evict(d);
    }
    state = const [];
  }
}

final mergeWorkspaceProvider =
    StateNotifierProvider<MergeWorkspace, List<PdfDocument>>(
  (_) => MergeWorkspace(),
);

/// Total page count across the workspace — surfaced in the merge button
/// label so the user knows what they're about to commit to.
final mergeTotalPagesProvider = Provider<int>((ref) {
  final docs = ref.watch(mergeWorkspaceProvider);
  return docs.fold<int>(0, (sum, d) => sum + d.pageCount);
});

/// Progress of the active merge, 0.0–1.0, or null when idle.
final mergeProgressProvider = StateProvider<double?>((_) => null);

/// Customized page selection that supersedes doc-level merge when non-empty.
///
/// Empty list = user hasn't customized; merge runs in plain doc-level mode.
/// Non-empty = user has hand-picked / reordered pages on the grid screen.
class MergePageRefs extends StateNotifier<List<PdfPageRef>> {
  MergePageRefs() : super(const []);

  /// Expand every page from every workspace doc into a flat ordered list.
  /// Called when the user enters page-level mode so they start from a
  /// sensible baseline (all pages in current doc order).
  void initializeFromWorkspace(List<PdfDocument> docs) {
    final refs = <PdfPageRef>[];
    for (final doc in docs) {
      for (var i = 0; i < doc.pageCount; i++) {
        refs.add(PdfPageRef(document: doc, pageIndex: i));
      }
    }
    state = refs;
  }

  void reorder(int oldIndex, int newIndex) {
    final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(adjustedNew, item);
    state = list;
  }

  void removeAt(int index) {
    state = [...state]..removeAt(index);
  }

  /// Clear the customization. Merge falls back to doc-level mode.
  void reset() => state = const [];
}

final mergePageRefsProvider =
    StateNotifierProvider<MergePageRefs, List<PdfPageRef>>(
  (_) => MergePageRefs(),
);

/// True when the user has hand-picked pages and merge should use page-level.
final hasPageCustomizationProvider = Provider<bool>((ref) {
  return ref.watch(mergePageRefsProvider).isNotEmpty;
});
