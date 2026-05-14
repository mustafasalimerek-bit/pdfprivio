import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../core/theme/colors.dart';
import '../data/services/haptics_service.dart';

/// Modal sheet that captures a hand-drawn signature and returns it as a PNG
/// to the caller. Resolves to `null` if the user backs out without saving.
///
/// We render the pad with a soft border-radius and a faint "sign here"
/// guide line so first-time users know where to start — the empty white
/// canvas pattern is one of the most reported confusion points in PDF
/// signing flows we surveyed.
class SignaturePadDialog extends StatefulWidget {
  const SignaturePadDialog({super.key});

  static Future<Uint8List?> show(BuildContext context) {
    return showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SignaturePadDialog(),
    );
  }

  @override
  State<SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<SignaturePadDialog> {
  late final SignatureController _controller;
  bool _hasStrokes = false;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 2.4,
      penColor: AppColors.textPrimary,
      exportBackgroundColor: Colors.transparent,
    )..addListener(_onChanged);
  }

  void _onChanged() {
    final has = _controller.isNotEmpty;
    if (has != _hasStrokes) {
      setState(() => _hasStrokes = has);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_hasStrokes) return;
    HapticsService.instance.success();
    final png = await _controller.toPngBytes(
      // High-DPI so the signature still looks crisp at small print sizes.
      width: 1400,
      height: 600,
    );
    if (!mounted) return;
    Navigator.of(context).pop(png);
  }

  void _clear() {
    HapticsService.instance.tap();
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: padding.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
              child: Text(
                'Draw your signature',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            AspectRatio(
              aspectRatio: 2.2,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Subtle "sign here" guide
                    if (!_hasStrokes)
                      const Positioned(
                        left: 16,
                        bottom: 18,
                        child: Text(
                          'Sign here',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: Container(
                        height: 1,
                        color: AppColors.border,
                      ),
                    ),
                    Signature(
                      controller: _controller,
                      backgroundColor: Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Use your finger or stylus. The signature is rendered '
              'on-device and never uploaded.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _hasStrokes ? _clear : null,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _hasStrokes ? _save : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Use this signature',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
