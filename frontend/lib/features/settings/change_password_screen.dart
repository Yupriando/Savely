import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/providers.dart';
import '../../widgets/celebration.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';

void openChangePassword(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()));
}

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  /// Pesan dari server untuk kolom password lama (mis. "Password lama salah").
  String? _currentError;

  @override
  void initState() {
    super.initState();
    _new.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _currentError = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).changePassword(current: _current.text, newPassword: _new.text);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, 'Password berhasil diganti');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.message.contains('Password lama salah')) {
        setState(() => _currentError = 'Password lama salah');
        _formKey.currentState!.validate();
        showSnack(context, 'Password lama salah', error: true);
      } else {
        showSnack(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = _strength(_new.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Ganti password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: context.colors.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.lock_reset_rounded, size: 40, color: context.colors.primary),
              ).animate().scale(curve: Curves.elasticOut, duration: 700.ms),
            ),
            const SizedBox(height: 14),
            Text(
              'Masukkan password lama untuk memastikan ini memang kamu, lalu buat password baru.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            _PasswordField(
              controller: _current,
              label: 'Password lama',
              icon: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password lama wajib diisi';
                return _currentError;
              },
            ),
            const SizedBox(height: 14),
            _PasswordField(
              controller: _new,
              label: 'Password baru',
              icon: Icons.lock_rounded,
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.length < 6) return 'Minimal 6 karakter';
                if (v == _current.text) return 'Harus berbeda dari password lama';
                return null;
              },
            ),
            const SizedBox(height: 10),
            // Indikator kekuatan password
            AnimatedProgressBar(value: strength.$1, color: strength.$3, height: 6),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _new.text.isEmpty ? 'Gunakan kombinasi huruf, angka & simbol' : strength.$2,
                key: ValueKey(strength.$2 + _new.text.isEmpty.toString()),
                style: context.text.labelSmall?.copyWith(
                  color: _new.text.isEmpty ? context.colors.onSurfaceVariant : strength.$3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _PasswordField(
              controller: _confirm,
              label: 'Ulangi password baru',
              icon: Icons.verified_user_rounded,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              validator: (v) => v != _new.text ? 'Password baru tidak sama' : null,
            ),
            const SizedBox(height: 28),
            SaveButton(label: 'Simpan password baru', saving: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }

  /// (nilai 0..1, label, warna)
  (double, String, Color) _strength(String p) {
    var score = 0;
    if (p.length >= 6) score++;
    if (p.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'\d').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    if (p.length < 6) return (0.15, 'Terlalu pendek', AppColors.expense);
    if (score <= 2) return (0.4, 'Lemah', AppColors.expense);
    if (score == 3) return (0.65, 'Cukup', AppColors.gold);
    return (1, 'Kuat', AppColors.income);
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
    required this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?) validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      autofillHints: const [AutofillHints.password],
      validator: widget.validator,
      decoration: InputDecoration(
        hintText: widget.label,
        prefixIcon: Icon(widget.icon),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Tampilkan' : 'Sembunyikan',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
        ),
      ),
    );
  }
}
