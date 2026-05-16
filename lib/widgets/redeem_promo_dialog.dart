import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/colors.dart';
import '../data/services/haptics_service.dart';
import '../data/services/promo_code_service.dart';

/// Modal redeem flow used by both Settings ("Redeem a promo code" tile)
/// and PaywallSheet ("Have a promo code?" link). Reads promo state on
/// build so reopening reflects the freshly-redeemed window.
///
/// One redemption per device, ever — if the user has already redeemed
/// (active or expired), the text field is hidden and the dialog turns
/// into an info card directing them to Pro.
class RedeemPromoDialog extends StatefulWidget {
  const RedeemPromoDialog({super.key});

  /// Resolves to true on a successful redemption — callers can refresh
  /// their state knowing the entitlement OR-gate just flipped.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const RedeemPromoDialog(),
    );
    return result ?? false;
  }

  @override
  State<RedeemPromoDialog> createState() => _RedeemPromoDialogState();
}

class _RedeemPromoDialogState extends State<RedeemPromoDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _loading = true;
  bool _alreadyRedeemed = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final any = await PromoCodeService.instance.hasAnyRedemption();
    if (!mounted) return;
    setState(() {
      _alreadyRedeemed = any;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final raw = _controller.text;
    if (raw.trim().isEmpty) {
      setState(() => _error = 'Enter a code to continue.');
      return;
    }
    HapticsService.instance.tap();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await PromoCodeService.instance.redeem(raw);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case PromoRedeemResult.success:
        // Capture the messenger before pop — after pop the dialog's
        // context is gone but the parent route's messenger lives on.
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Promo redeemed — 14 days of Pro unlocked.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case PromoRedeemResult.invalidCode:
        setState(
          () => _error = "That code isn't valid. Check spelling and try again.",
        );
      case PromoRedeemResult.alreadyRedeemed:
        setState(() {
          _alreadyRedeemed = true;
          _error = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeLeft = PromoCodeService.instance.timeLeft;
    final hasActive = timeLeft != null;
    final daysLeft = hasActive ? timeLeft.inDays : 0;

    if (_loading) {
      return const AlertDialog(
        backgroundColor: AppColors.background,
        content: SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Device has redeemed before. Show info-only state — no text field.
    if (_alreadyRedeemed) {
      return AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(hasActive ? 'Promo active' : 'Promo already used'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasActive) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '$daysLeft ${daysLeft == 1 ? "day" : "days"} left of '
                  'your 14-day Pro promo.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Each device can claim a 14-day Pro promo once. When "
                "this window ends you'll drop back to free tier — "
                "upgrade to Pro any time to stay unlocked.",
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ] else ...[
              const Text(
                'This device has already used its 14-day Pro promo. '
                "Promo codes can be redeemed once per device — upgrade "
                "to Pro to unlock everything again.",
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    // Eligible — show the redeem form.
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: const Text('Redeem promo code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '14 days of Pro, no purchase needed. Drops back to free '
            'tier when it ends. One redemption per device.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              _UpperCaseTextFormatter(),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
              LengthLimitingTextInputFormatter(20),
            ],
            decoration: InputDecoration(
              hintText: 'e.g. LAWYER14',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _redeem(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _redeem,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Redeem'),
        ),
      ],
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
