import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../widgets/celebration.dart';
import '../../widgets/common.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/stagger.dart';
import '../../core/sound.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _user = ref.read(authProvider).valueOrNull;
  late final _name = TextEditingController(text: _user?.fullName ?? '');
  late final _email = TextEditingController(text: _user?.email ?? '');
  final _picker = ImagePicker();

  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  // ---------------- Foto ----------------

  Future<void> _showPhotoOptions() async {
    final hasPhoto = ref.read(authProvider).valueOrNull?.avatarUrl != null;
    final canUseCamera = _picker.supportsImageSource(ImageSource.camera);

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Pilih dari galeri',
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (canUseCamera)
                _SheetOption(
                  icon: Icons.photo_camera_rounded,
                  label: 'Ambil foto',
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
              if (hasPhoto)
                _SheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Hapus foto',
                  color: AppColors.expense,
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ].staggered(interval: 50.ms).fadeIn(duration: 250.ms).moveY(begin: 12, end: 0),
          ),
        ),
      ),
    );

    switch (action) {
      case 'gallery':
        await _pickAndUpload(ImageSource.gallery);
      case 'camera':
        await _pickAndUpload(ImageSource.camera);
      case 'remove':
        await _removePhoto();
    }
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final XFile? file;
    try {
      // Diperkecil di HP supaya upload cepat & di bawah batas 2 MB
      file = await _picker.pickImage(source: source, maxWidth: 600, maxHeight: 600, imageQuality: 85);
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          'Tidak bisa membuka ${source == ImageSource.camera ? 'kamera' : 'galeri'}',
          error: true,
        );
      }
      return;
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      if (mounted) showSnack(context, 'Ukuran foto maksimal 2 MB', error: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      await ref.read(authProvider.notifier).uploadAvatar(bytes, filename: file.name, mimeType: _mimeOf(file));
      if (mounted) showSuccess(context, 'Foto profil diperbarui');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _mimeOf(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) return mime;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _removePhoto() async {
    setState(() => _uploading = true);
    try {
      await ref.read(authProvider.notifier).removeAvatar();
      if (mounted) showSnack(context, 'Foto profil dihapus', sound: Sfx.delete);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------------- Nama & email ----------------

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final current = ref.read(authProvider).valueOrNull;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final nameChanged = name != (current?.fullName ?? '');
    final emailChanged = email.toLowerCase() != (current?.email ?? '').toLowerCase();

    if (!nameChanged && !emailChanged) {
      Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);
    try {
      final user = await ref
          .read(authProvider.notifier)
          .updateProfile(fullName: nameChanged ? name : null, email: emailChanged ? email : null);
      if (!mounted) return;
      if (emailChanged && user.pendingEmail != null) {
        showSnack(context, 'Cek inbox ${user.pendingEmail} untuk konfirmasi email baru');
      } else {
        Navigator.pop(context);
        showSuccess(context, 'Profil disimpan');
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profil')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children:
              [
                    Center(
                      child: Pressable(
                        onTap: _uploading ? null : _showPhotoOptions,
                        child: SizedBox(
                          width: 128,
                          height: 128,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              // Hanya cincin gradien yang berputar pelan, fotonya diam
                              Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(
                                    colors: [
                                      AppColors.emerald,
                                      AppColors.gold,
                                      AppColors.mint,
                                      AppColors.emerald,
                                    ],
                                  ),
                                ),
                              ).animate(onPlay: (c) => c.repeat()).rotate(duration: 8.seconds),
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: context.colors.surface,
                                ),
                              ),
                              Hero(
                                tag: 'avatar',
                                child: UserAvatar(user: user, size: 112),
                              ),
                              if (_uploading)
                                Container(
                                  width: 112,
                                  height: 112,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.45),
                                  ),
                                  alignment: Alignment.center,
                                  child: const CircularProgressIndicator(color: Colors.white),
                                ).animate().fadeIn(duration: 200.ms),
                              Positioned(
                                right: 0,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: context.colors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: context.colors.surface, width: 3),
                                  ),
                                  child: const Icon(
                                    Icons.photo_camera_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ).animate().scale(delay: 300.ms, duration: 400.ms, curve: Curves.elasticOut),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        'Ketuk foto untuk mengganti',
                        style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text('Nama', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Nama kamu',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'Nama wajib diisi';
                        if (value.length > 100) return 'Maksimal 100 karakter';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    Text('Email', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                        hintText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'Email wajib diisi';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                          return 'Format email tidak valid';
                        }
                        return null;
                      },
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      child: user?.pendingEmail == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.mark_email_unread_rounded,
                                      color: AppColors.gold,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Menunggu konfirmasi: ${user!.pendingEmail}',
                                        style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: _saving || _uploading ? null : _save,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text('Simpan'),
                      ),
                    ),
                  ]
                  .staggered(interval: 50.ms)
                  .fadeIn(duration: 350.ms)
                  .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: c),
      ),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
