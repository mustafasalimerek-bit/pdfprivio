import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/theme/colors.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/share_intent_service.dart';
import '../../widgets/banner_ad_widget.dart';
import '../../widgets/shared_file_action_sheet.dart';
import '../home_screen.dart';
import '../pro/pro_screen.dart';
import '../recent/recent_screen.dart';
import '../settings/settings_screen.dart';

/// Four-tab bottom nav shell: Tools / Recent / Pro / Settings.
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

class _RootScaffoldState extends ConsumerState<RootScaffold> {
  int _index = 0;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  static const _tabs = <Widget>[
    HomeScreen(),
    RecentScreen(),
    ProScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Defer until the widget has a real context — using the
    // post-frame callback also catches the cold-launch share payload
    // that ShareIntentService.init() emits during app boot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareSub = ShareIntentService.instance.intents.listen((files) {
        if (!mounted) return;
        SharedFileActionSheet.show(context, files);
      });
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    HapticsService.instance.select();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: IndexedStack(index: _index, children: _tabs)),
          // Sticky banner above the nav bar. Renders empty for Pro users
          // and on AdMob no-fill — collapses to zero height in both cases
          // so the IndexedStack reclaims the space automatically.
          const BannerAdWidget(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
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
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(
              Icons.workspace_premium,
              color: AppColors.primary,
            ),
            label: 'Pro',
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
