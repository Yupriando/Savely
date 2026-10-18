import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/celebration.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';
import '../../widgets/stagger.dart';

void openCategories(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CategoriesScreen()));
}

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  TxType _type = TxType.expense;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kelola kategori')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-category',
        onPressed: () => showCategoryForm(context, type: _type),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Kategori baru'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        children: [
          PillTabs(
            labels: const ['Pengeluaran', 'Pemasukan'],
            index: _type.isIncome ? 1 : 0,
            colors: const [AppColors.expense, AppColors.income],
            onChanged: (i) => setState(() => _type = i == 1 ? TxType.income : TxType.expense),
          ),
          const SizedBox(height: 16),
          AsyncView(
            value: categories,
            onRetry: () => ref.invalidate(categoriesProvider),
            builder: (all) {
              final list = all.where((c) => c.type == _type).toList();
              return Card(
                key: ValueKey(_type),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final c in list)
                      ListTile(
                        onTap: () => showCategoryForm(context, existing: c, type: _type),
                        leading: CategoryIcon(icon: c.icon, color: c.color, size: 40),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                  ].staggered(interval: 30.ms).fadeIn(duration: 250.ms).moveX(begin: 12, end: 0),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<void> showCategoryForm(BuildContext context, {Category? existing, required TxType type}) =>
    showFormSheet<void>(context, _CategoryForm(existing: existing, type: type));

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({this.existing, required this.type});

  final Category? existing;
  final TxType type;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? 'category';
  late String _color = widget.existing != null ? colorHex(widget.existing!.color) : '#10B981';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return showSnack(context, 'Nama kategori wajib diisi', error: true);
    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      if (_isEdit) {
        await api.updateCategory(widget.existing!.id, name: name, icon: _icon, color: _color);
      } else {
        await api.createCategory(name: name, type: widget.type, icon: _icon, color: _color);
      }
      refreshCategories(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, _isEdit ? 'Kategori diperbarui' : 'Kategori "$name" dibuat');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final c = widget.existing!;
    final ok = await confirmDialog(
      context,
      title: 'Hapus kategori?',
      message: 'Kategori "${c.name}" hanya bisa dihapus kalau belum dipakai transaksi atau tagihan rutin.',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).deleteCategory(c.id);
      refreshCategories(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Kategori dihapus');
    } catch (e) {
      if (!mounted) return;
      final inUse = e.toString().contains('masih dipakai');
      showSnack(
        context,
        inUse
            ? 'Kategori ini masih dipakai transaksi. Ubah nama/ikonnya saja, atau pindahkan transaksinya dulu.'
            : e.toString(),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = hexColor(_color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: _isEdit ? 'Ubah kategori' : 'Kategori ${widget.type.label.toLowerCase()} baru',
          onDelete: _isEdit ? _delete : null,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: CategoryIcon(key: ValueKey('$_icon$_color'), icon: _icon, color: color, size: 52),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _name,
                autofocus: !_isEdit,
                maxLength: 50,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Nama kategori', counterText: ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Ikon', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        IconPickerGrid(
          icons: categoryIconChoices,
          selected: _icon,
          color: color,
          onChanged: (v) => setState(() => _icon = v),
        ),
        const SizedBox(height: 18),
        Text('Warna', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ColorPickerRow(selected: _color, onChanged: (v) => setState(() => _color = v)),
        const SizedBox(height: 22),
        SaveButton(label: _isEdit ? 'Simpan perubahan' : 'Buat kategori', saving: _saving, onPressed: _save),
      ],
    );
  }
}
