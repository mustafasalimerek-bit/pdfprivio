import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected index for [RootScaffold]'s bottom nav.
///
/// Descendants (e.g. the home-screen "See all" link) can switch tabs
/// by writing to this provider:
///
///   ref.read(selectedTabProvider.notifier).state = 1;
///
/// Keeping a single source of truth means programmatic switches stay
/// in sync with user-driven nav taps without needing a tab controller
/// or InheritedWidget glue.
final selectedTabProvider = StateProvider<int>((ref) => 0);
