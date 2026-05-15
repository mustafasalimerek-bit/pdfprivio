import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/theme/colors.dart';
import '../data/services/ads_service.dart';
import '../data/services/purchase_service.dart';

/// Sticky banner above the bottom nav for free users.
///
/// Renders nothing for Pro users — both initially and after a successful
/// purchase (we listen on `entitlementChanges` and dispose the ad in
/// place). The host doesn't need to remove this widget from its tree;
/// it gracefully collapses to a zero-height shrink.
///
/// Failures (no fill, network blip) also collapse to nothing rather than
/// showing a broken placeholder — better to give the user back the screen
/// real estate than to clutter it with empty banner frames.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _failed = false;
  StreamSubscription<EntitlementTier>? _sub;
  bool _isPro = PurchaseService.instance.hasPro;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = PurchaseService.instance.entitlementChanges.listen((tier) {
      if (!mounted) return;
      final nowPro = tier == EntitlementTier.pro;
      if (nowPro != _isPro) {
        setState(() {
          _isPro = nowPro;
          if (_isPro) {
            _ad?.dispose();
            _ad = null;
            _loaded = false;
            _failed = false;
          }
        });
        if (!nowPro && _ad == null) {
          _load();
        }
      }
    });
  }

  void _load() {
    if (_isPro) return;
    final ad = AdsService.instance.createBanner(
      size: AdSize.banner,
      onLoaded: () {
        if (!mounted) return;
        setState(() => _loaded = true);
      },
      onFailed: (_) {
        if (!mounted) return;
        setState(() {
          _failed = true;
          _ad = null;
          _loaded = false;
        });
      },
    );
    if (ad == null) return; // Pro user or service refused.
    _ad = ad;
    unawaited(ad.load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPro || _failed || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        height: _ad!.size.height.toDouble(),
        width: _ad!.size.width.toDouble(),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}
