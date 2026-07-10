import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/enums.dart';
import '../dialogs/web_category_dialog.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_pickers.dart';
import '../widgets/web_ui.dart';

/// Categorías: dos árboles (Gastos e Ingresos) con CRUD y subcategorías.
class WebCategoriesPage extends ConsumerWidget {
  const WebCategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(webCategoriesProvider);

    return WebPage(
      title: 'Categorías',
      actions: [
        IconButton(
          tooltip: 'Refrescar',
          icon: const Icon(Icons.refresh),
          onPressed: () => bumpWebRefresh(ref),
        ),
      ],
      child: categoriesAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Error: $e'),
        data: (_) => LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          if (wide) {
            return const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _CategoryPanel(kind: CategoryKind.expense)),
                SizedBox(width: 16),
                Expanded(child: _CategoryPanel(kind: CategoryKind.income)),
              ],
            );
          }
          return const Column(
            children: [
              _CategoryPanel(kind: CategoryKind.expense),
              SizedBox(height: 16),
              _CategoryPanel(kind: CategoryKind.income),
            ],
          );
        }),
      ),
    );
  }
}

class _CategoryPanel extends ConsumerWidget {
  const _CategoryPanel({required this.kind});
  final CategoryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpense = kind == CategoryKind.expense;
    final tree = ref.watch(isExpense
        ? webExpenseCategoryTreeProvider
        : webIncomeCategoryTreeProvider);
    final scheme = Theme.of(context).colorScheme;

    return WebCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(isExpense ? Icons.south_east : Icons.north_east,
                  color: isExpense ? scheme.error : Colors.green),
              const SizedBox(width: 8),
              Text(isExpense ? 'Gastos' : 'Ingresos',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Añadir'),
                onPressed: () => showDialog(
                    context: context,
                    builder: (_) => WebCategoryDialog(kind: kind)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (tree.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('Sin categorías.')),
            )
          else
            for (final row in tree) _row(context, row),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WebTreeRow<CategoryDto> row) {
    final c = row.item;
    return Padding(
      padding: EdgeInsets.only(left: row.depth * 22.0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        dense: true,
        leading: WebColorDot(
          size: 32,
          colorValue: c.colorValue,
          icon: webIconFor(c.iconName),
        ),
        title: Text(c.name),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => showDialog(
            context: context,
            builder: (_) => v == 'edit'
                ? WebCategoryDialog(kind: kind, existing: c)
                : WebCategoryDialog(kind: kind, parentId: c.id),
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Editar')),
            PopupMenuItem(value: 'sub', child: Text('Añadir subcategoría')),
          ],
        ),
      ),
    );
  }
}
