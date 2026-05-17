import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format_bytes.dart';
import '../../core/utils/result.dart';
import '../../data/models/pdf_document.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/pdf_metadata_service.dart';
import '../../data/services/pdf_password_service.dart';
import '../../widgets/progress_overlay.dart';
import '../../widgets/tool_chrome.dart';
import '../merge/merge_result_screen.dart';

enum _PasswordMode { add, remove }

class PasswordScreen extends ConsumerStatefulWidget {
  const PasswordScreen({super.key});

  @override
  ConsumerState<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends ConsumerState<PasswordScreen> {
  PdfDocument? _doc;
  _PasswordMode _mode = _PasswordMode.add;
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  PdfProtectionLevel _level = PdfProtectionLevel.fullAccess;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    HapticsService.instance.tap();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res == null) return;
    final path = res.paths.firstOrNull;
    if (path == null) return;

    // We try to read metadata; if it bounces with needsPassword we still
    // load the file in a minimal form so the user can move on to removal.
    final outcome = await PdfMetadataService.instance.inspect(File(path));
    if (!mounted) return;
    switch (outcome) {
      case Ok(:final value):
        setState(() {
          _doc = value;
          _mode = _PasswordMode.add; // unencrypted → add a password
          _password.clear();
          _confirm.clear();
        });
        HapticsService.instance.select();
      case Err(:final kind, :final message):
        if (kind == FailureKind.needsPassword) {
          // Switch into remove-mode with a minimal doc handle.
          final stat = await File(path).stat();
          if (!mounted) return;
          setState(() {
            _doc = PdfDocument(
              file: File(path),
              displayName: File(path).uri.pathSegments.last,
              sizeBytes: stat.size,
              pageCount: 0,
              isPasswordProtected: true,
              hasOcrLayer: false,
              addedAt: DateTime.now(),
            );
            _mode = _PasswordMode.remove;
            _password.clear();
          });
          HapticsService.instance.tap();
        } else {
          HapticsService.instance.error();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }

  Future<void> _run() async {
    final doc = _doc;
    if (doc == null) return;

    if (_mode == _PasswordMode.add) {
      if (_password.text.isEmpty) return;
      if (_password.text != _confirm.text) {
        HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Passwords don't match"),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    } else {
      if (_password.text.isEmpty) return;
    }

    HapticsService.instance.tap();
    setState(() => _busy = true);

    final Result<File> result;
    if (_mode == _PasswordMode.add) {
      result = await PdfPasswordService.instance.protect(
        input: doc,
        userPassword: _password.text,
        level: _level,
      );
    } else {
      result = await PdfPasswordService.instance.removePassword(
        input: doc,
        password: _password.text,
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok(:final value):
        HapticsService.instance.success();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MergeResultScreen(
              outputFile: value,
              sourceCount: 1,
              toolLabel: 'Password',
              toolIdForUsage: 'password',
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _doc = null;
            _password.clear();
            _confirm.clear();
          });
        }
      case Err(:final kind, :final message):
        HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kind == FailureKind.needsPassword
                ? 'Wrong password — try again'
                : message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Password'),
        centerTitle: true,
        actions: [
          if (doc != null)
            TextButton(
              onPressed: () {
                HapticsService.instance.tap();
                setState(() {
                  _doc = null;
                  _password.clear();
                  _confirm.clear();
                });
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: doc == null
                ? _EmptyState(onPick: _pick)
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          children: [
                            _DocSummary(
                              doc: doc,
                              isEncrypted:
                                  _mode == _PasswordMode.remove,
                            ),
                            const SizedBox(height: 14),
                            if (_mode == _PasswordMode.add) ...[
                              _PasswordField(
                                controller: _password,
                                obscure: _obscure,
                                onToggleObscure: () => setState(
                                  () => _obscure = !_obscure,
                                ),
                                label: 'New password',
                              ),
                              const SizedBox(height: 10),
                              _PasswordField(
                                controller: _confirm,
                                obscure: _obscure,
                                onToggleObscure: () => setState(
                                  () => _obscure = !_obscure,
                                ),
                                label: 'Confirm',
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Protection level',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final l in PdfProtectionLevel.values)
                                _LevelCard(
                                  level: l,
                                  selected: l == _level,
                                  onTap: () {
                                    HapticsService.instance.select();
                                    setState(() => _level = l);
                                  },
                                ),
                            ] else ...[
                              _PasswordField(
                                controller: _password,
                                obscure: _obscure,
                                onToggleObscure: () => setState(
                                  () => _obscure = !_obscure,
                                ),
                                label: 'Password',
                                hint: 'Enter the existing password',
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'We need the existing password to read '
                                'the PDF before we can strip protection.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!_busy)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: ToolPrimaryButton(
                            label: _mode == _PasswordMode.add
                                ? 'Protect PDF'
                                : 'Remove password',
                            icon: _mode == _PasswordMode.add
                                ? Icons.lock
                                : Icons.lock_open,
                            onTap: _run,
                          ),
                        ),
                    ],
                  ),
          ),
          if (_busy)
            ProgressOverlay(
              title: _mode == _PasswordMode.add
                  ? 'Encrypting'
                  : 'Removing password',
              subtitle: 'Processing on this device — no upload',
              progress: null,
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyState({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ToolEmptyState(
      heroIcon: Icons.lock_outline,
      title: 'Password protect',
      subtitle: 'AES-256 encrypt or unlock',
      primaryLabel: 'Pick a PDF',
      onPrimary: onPick,
      altSources: [
        ToolAltSource(icon: Icons.camera_alt_outlined, label: 'Scan', onTap: onPick),
      ],
    );
  }
}

class _DocSummary extends StatelessWidget {
  final PdfDocument doc;
  final bool isEncrypted;

  const _DocSummary({required this.doc, required this.isEncrypted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEncrypted ? AppColors.warning : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (isEncrypted ? AppColors.warning : AppColors.primary)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEncrypted ? Icons.lock : Icons.picture_as_pdf_outlined,
              color: isEncrypted ? AppColors.warning : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isEncrypted
                      ? 'Encrypted · ${formatBytes(doc.sizeBytes)}'
                      : '${doc.pageCount} pages · ${formatBytes(doc.sizeBytes)}',
                  style: TextStyle(
                    color: isEncrypted
                        ? AppColors.warning
                        : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: isEncrypted
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final String label;
  final String? hint;

  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.label,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppColors.textTertiary,
          ),
          tooltip: obscure ? 'Show password' : 'Hide password',
          onPressed: onToggleObscure,
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final PdfProtectionLevel level;
  final bool selected;
  final VoidCallback onTap;

  const _LevelCard({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        level.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        level.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
