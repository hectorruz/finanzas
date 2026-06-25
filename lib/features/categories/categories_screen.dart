import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/category_repository.dart';
import '../../shared/widgets/async_value_view.dart';
import '../../shared/widgets/icon_color_picker.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categorías'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Gastos'), Tab(text: 'Ingresos')],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _edit(context, ref, null),
          child: const Icon(Icons.add),
        ),
        body: AsyncValueView(
          value: categories,
          data: (list) {
            final expenses =
                list.where((c) => c.kind == CategoryKind.expense).toList();
            final incomes =
                list.where((c) => c.kind == CategoryKind.income).toList();
            return TabBarView(
              children: [
                _CategoryList(items: expenses, onEdit: (c) => _edit(context, ref, c)),
                _CategoryList(items: incomes, onEdit: (c) => _edit(context, ref, c)),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, Category? category) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditor(category: category),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.items, required this.onEdit});
  final List<Category> items;
  final ValueChanged<Category> onEdit;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No hay categorías.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final c = items[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(c.colorValue).withOpacity(0.18),
            child: Icon(iconByName(c.iconName), color: Color(c.colorValue)),
          ),
          title: Text(c.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onEdit(c),
        );
      },
    );
  }
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.category});
  final Category? category;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final TextEditingController _nameController;
  late CategoryKind _kind;
  late String _iconName;
  late int _colorValue;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _nameController = TextEditingController(text: c?.name ?? '');
    _kind = c?.kind ?? CategoryKind.expense;
    _iconName = c?.iconName ?? 'category';
    _colorValue = c?.colorValue ?? kPaletteColors.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final category = widget.category ?? Category();
    category
      ..name = name
      ..kind = _kind
      ..iconName = _iconName
      ..colorValue = _colorValue;
    await ref.read(categoryRepositoryProvider).save(category);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (widget.category == null) return;
    await ref.read(categoryRepositoryProvider).delete(widget.category!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.category == null ? 'Nueva categoría' : 'Editar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (widget.category != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 16),
            SegmentedButton<CategoryKind>(
              segments: const [
                ButtonSegment(
                    value: CategoryKind.expense, label: Text('Gasto')),
                ButtonSegment(
                    value: CategoryKind.income, label: Text('Ingreso')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            IconColorPicker(
              iconName: _iconName,
              colorValue: _colorValue,
              onIconChanged: (n) => setState(() => _iconName = n),
              onColorChanged: (c) => setState(() => _colorValue = c),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
