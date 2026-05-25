import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/app_intent_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/share_intent_service.dart';
import '../../data/state/nav_provider.dart';
import '../../widgets/shared_file_action_sheet.dart';
import '../home_screen.dart';
import '../pro/pro_screen.dart';
import '../recent/recent_screen.dart';
import '../settings/settings_screen.dart';

/// Three-destination nav shell: Tools / Recent / Settings.
///
/// On iPhone (and iPad in narrow Split View under 700pt) we use a
/// bottom `NavigationBar` — the standard iOS pattern, thumb-reachable.
/// On iPad once the width clears [Breakpoints.iPadCompact] we switch
/// to a `NavigationRail` on the left edge — the iPad-native pattern
/// per Apple HIG and the layout used by Mail, Notes, Files, Music,
/// Settings, etc. The selected tab + IndexedStack behaviour is shared
/// across both layouts so descendant code (tab switching, deep links,
/// state retention) doesn't have to branch.
///
/// Pro used to live as a fourth tab, but the upgrade pitch reads more
/// natural as a hero card pinned to the top of Settings — the bottom
/// nav stays focused on tasks the user came here to do. Pro screen is
/// still reachable via that card, paywalls, and the `tab:pro` Siri /
/// Shortcuts route (which now pushes ProScreen as a fullscreen route
/// instead of switching tabs).
///
/// IndexedStack keeps each tab's state alive between switches — a
/// half-typed redaction term won't disappear when the user pops into
/// Recent and back. Each tab is a top-level Scaffold with its own
/// AppBar, so navigation inside a tab (e.g. picking a PDF inside Tools)
/// pushes routes above the shell, not inside it.
class RootScaffold extends ConsumerStatefulWidget {
  const RootScaffold({super.key});

  @override
  ConsumerState<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends ConsumerState<RootScaffold>
    with WidgetsBindingObserver {
  // Selected tab is owned by `selectedTabProvider` so descendants can
  // programmatically switch tabs (e.g. the home "See all" link). Local
  // state is read-only and derived from the provider in build().
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  StreamSubscription<String>? _intentSub;

  static const _tabs = <Widget>[
    HomeScreen(),
    RecentScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Re-apply the orientation policy now that a view is attached.
      // main() runs before the scene connects on a URL-scheme cold
      // launch, so it falls back to portraitUp; here we know whether
      // we're on iPad and can lift the lock.
      final shortest = MediaQuery.sizeOf(context).shortestSide;
      SystemChrome.setPreferredOrientations(
        shortest >= 600
            ? const <DeviceOrientation>[]
            : const [DeviceOrientation.portraitUp],
      );
      // Subscribe to the hot streams FIRST so any share that lands
      // during the next frame already has a listener…
      _shareSub = ShareIntentService.instance.intents.listen((files) {
        if (!mounted || files.isEmpty) return;
        SharedFileActionSheet.show(context, files);
      });
      // Both streams get an explicit onError so a single bad route or
      // share payload can't kill the subscription silently (which would
      // leave the app deaf to subsequent intents until cold restart).
      _intentSub = AppIntentService.instance.routes.listen(
        _handleIntentRoute,
        onError: (Object err) {
          debugPrint('AppIntent route stream error: $err');
        },
      );
      var initialShares =
          await ShareIntentService.instance.consumeInitial();
      if (initialShares.isEmpty) {
        // Retry once after a beat — the implicit Flutter engine's
        // plugin registration can race against the post-frame callback
        // in scene mode (FlutterImplicitEngineDelegate). If the bridge
        // wasn't installed yet, the first call quietly returned empty.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        initialShares = await ShareIntentService.instance.consumeInitial();
      }
      if (mounted && initialShares.isNotEmpty) {
        SharedFileActionSheet.show(context, initialShares);
      }
      final pendingRoute =
          await AppIntentService.instance.consumePending();
      if (mounted && pendingRoute != null) {
        _handleIntentRoute(pendingRoute);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A Siri / Shortcuts trigger fired while we were backgrounded
    // writes to UserDefaults and brings us back. Re-drain the queue on
    // every resume so the navigator catches it. Same logic for the
    // custom PDFPrivioShare Share Extension — anything it dropped in
    // the App Group folder while we were away gets imported into
    // Documents/Inbox and surfaced through the action sheet.
    if (state == AppLifecycleState.resumed) {
      AppIntentService.instance.onResume();
      ShareIntentService.instance.drainExtensionDrop();
    }
  }

  void _handleIntentRoute(String route) {
    if (!mounted) return;
    HapticsService.instance.select();
    // "tab:<name>" switches the bottom-nav tab; everything else
    // is treated as a navigator route.
    if (route.startsWith('tab:')) {
      final notifier = ref.read(selectedTabProvider.notifier);
      switch (route.substring(4)) {
        case 'recent':
          notifier.state = 1;
        case 'settings':
          notifier.state = 2;
        case 'pro':
          // Pro is no longer a tab; push it as a fullscreen route so
          // Shortcuts / Siri intents still land somewhere meaningful.
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProScreen()),
          );
        case 'tools':
        default:
          notifier.state = 0;
      }
      return;
    }
    // Intent routes may carry a query string (e.g. "/tool/scan?auto=1")
    // that the target screen reads from ModalRoute.settings.arguments
    // to decide whether to skip its intro state and act immediately.
    // The Navigator routes table only knows the bare paths, so split
    // before pushing. Uri.parse can throw on malformed input — guard so
    // a bad route written to UserDefaults by a future intent doesn't
    // crash navigation; fall back to the literal string in that case.
    Uri? uri;
    try {
      uri = Uri.parse(route);
    } catch (e) {
      debugPrint('AppIntent route parse failed for "$route": $e');
    }
    Navigator.of(context).pushNamed(
      uri?.path ?? route,
      arguments: (uri?.queryParameters.isNotEmpty ?? false)
          ? uri!.queryParameters
          : null,
    );
  }

  void _select(int i) {
    if (i == ref.read(selectedTabProvider)) return;
    HapticsService.instance.select();
    ref.read(selectedTabProvider.notifier).state = i;
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(selectedTabProvider);
    final useRail = Breakpoints.isWide(context);

    if (useRail) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                backgroundColor: AppColors.surface,
                indicatorColor: AppColors.primary.withValues(alpha: 0.14),
                useIndicator: true,
                minWidth: 88,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(
                      Icons.grid_view,
                      color: AppColors.primary,
                    ),
                    label: Text('Tools'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.history_outlined),
                    selectedIcon: Icon(
                      Icons.history,
                      color: AppColors.primary,
                    ),
                    label: Text('Recent'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(
                      Icons.settings,
                      color: AppColors.primary,
                    ),
                    label: Text('Settings'),
                  ),
                ],
              ),
              const VerticalDivider(
                thickness: 1,
                width: 1,
                color: AppColors.border,
              ),
              Expanded(
                child: IndexedStack(index: index, children: _tabs),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _select,
        height: 64,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view, color: AppColors.primary),
            label: 'Tools',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: AppColors.primary),
            label: 'Recent',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: AppColors.primary),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
