import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/colors.dart';
import '../data/services/haptics_service.dart';
import 'bates/bates_screen.dart';
import 'compress/compress_screen.dart';
import 'delete_pages/delete_pages_screen.dart';
import 'image_to_pdf/image_to_pdf_screen.dart';
import 'merge/merge_screen.dart';
import 'password/password_screen.dart';
import 'rotate/rotate_screen.dart';
import 'sign/sign_screen.dart';
import 'split/split_screen.dart';
import 'watermark/watermark_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PDFKitsy',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 4),
            const Text(
              'Offline PDF tools',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _ToolTile(
              icon: Icons.library_books_outlined,
              title: 'Merge PDFs',
              subtitle: 'Combine multiple PDFs into one',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MergeScreen()),
                );
              },
            ),
            _ToolTile(
              icon: Icons.compress_outlined,
              title: 'Compress PDF',
              subtitle: 'Shrink for email — keep quality',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CompressScreen()),
                );
              },
            ),
            _ToolTile(
              icon: Icons.content_cut_outlined,
              title: 'Split PDF',
              subtitle: 'Extract range, every N pages, or N parts',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SplitScreen()),
                );
              },
            ),
            _ToolTile(
              icon: Icons.image_outlined,
              title: 'Image to PDF',
              subtitle: 'Photos, receipts, screenshots → one PDF',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ImageToPdfScreen()),
                );
              },
            ),
            _ToolTile(
              icon: Icons.rotate_right_outlined,
              title: 'Rotate pages',
              subtitle: 'Fix sideways scans or flip a PDF',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RotateScreen()),
                );
              },
            ),
            _ToolTile(
              icon: Icons.delete_sweep_outlined,
              title: 'Delete pages',
              subtitle: 'Pick the pages to drop, keep the rest',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeletePagesScreen()),
                );
              },
            ),
            _ToolTile(
              icon: Icons.draw_outlined,
              title: 'Sign PDF',
              subtitle: 'Draw, place, save — audit-trail included',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SignScreen()),
                );
              },
            ),
            _ToolTile(
              icon: Icons.tag,
              title: 'Bates numbering',
              subtitle: 'Sequential page IDs — legal discovery standard',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BatesScreen()),
                );
              },
            ),
            _ToolTile(
              icon: Icons.lock_outline,
              title: 'Password protect',
              subtitle: 'AES-256 encrypt or unlock — pick auto-detects',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PasswordScreen()),
                );
              },
            ),
            _ToolTile(
              icon: Icons.water_drop_outlined,
              title: 'Watermark',
              subtitle: 'CONFIDENTIAL / DRAFT — diagonal, center, or tile',
              isFree: true,
              onTap: () {
                HapticsService.instance.tap();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WatermarkScreen()),
                );
              },
            ),
            const _ComingSoonTile(
              icon: Icons.draw_outlined,
              title: 'Sign PDF',
              subtitle: 'Add your signature, single or bulk',
            ),
            const _ComingSoonTile(
              icon: Icons.search,
              title: 'OCR + Search',
              subtitle: 'Make scans searchable, find any word',
              isPro: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isFree;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isFree = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isFree) const _Pill(label: 'FREE', color: AppColors.freeBadge),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isPro;

  const _ComingSoonTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isPro = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.textTertiary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isPro) const _Pill(label: 'PRO', color: AppColors.proBadge),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const _Pill(label: 'SOON', color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
