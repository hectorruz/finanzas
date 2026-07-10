import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../data/models/enums.dart';
import '../web_models.dart';
import '../web_movement_dialog.dart';
import '../web_providers.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_ui.dart';

/// Movimientos: rejilla con barra de filtros completa, orden por columnas,
/// selección múltiple + acciones masivas y panel de detalle (edición en línea).
class WebMovementsPage extends ConsumerStatefulWidget {
  const WebMovementsPage({super.key});

  @override
  ConsumerState<WebMovementsPage> createState() => _WebMovementsPageState();
}

class _WebMovementsPageState extends ConsumerState<WebMovementsPage> {
  final Set<int> _selected = {};
  bool _showFilters = false;

  @override
  Widget build(BuildContext context) {
    final txnsAsync = ref.watch(webTransactionsProvider);
    final filter = ref.watch(webTxFilterProvider);

    return WebPage(
      title: 'Movimientos',
      scrollable: false,
      maxWidth: double.infinity,
      actions: [
        SizedBox(
          width: 240,
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar…',
            ),
            onChanged: (v) => ref
                .read(webTxFilterProvider.notifier)
                .update((f) => f.copyWith(query: v)),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          isSelected: _showFilters || filter.hasContentFilters,
          tooltip: 'Filtros',
          icon: Badge(
            isLabelVisible: filter.hasContentFilters,
            label: Text('${filter.activeCount}'),
            child: const Icon(Icons.tune),
          ),
          onPressed: () => setState(() => _showFilters = !_showFilters),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Refrescar',
          icon: const Icon(Icons.refresh),
          onPressed: () => bumpWebRefresh(ref),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Nuevo'),
          onPressed: () => showDialog(
              context: context, builder: (_) => const WebMovementDialog()),
        ),
      ],
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showFilters) ...[
              const _FilterBar(),
              const SizedBox(height: 12),
            ],
            if (_selected.isNotEmpty) ...[
              _BatchBar(
                selected: _selected,
                onClear: () => setState(_selected.clear),
                onDone: () => setState(_selected.clear),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: txnsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (list) => _body(context, list, filter),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
      BuildContext context, List<TransactionDto> list, WebTxFilter filter) {
    if (list.isEmpty) {
      return WebCard(
        child: WebEmptyState(
          icon: Icons.swap_vert,
          title: filter.query.isEmpty && !filter.hasContentFilters
              ? 'Sin movimientos'
              : 'Nada coincide con el filtro',
          message: filter.query.isEmpty && !filter.hasContentFilters
              ? 'Crea tu primer movimiento con el botón "Nuevo".'
              : null,
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      // limpia selección de ids que ya no están en la lista
      final ids = {for (final t in list) t.id};
      _selected.removeWhere((id) => !ids.contains(id));
      final selectedDto = _selected.length == 1
          ? list.firstWhere((t) => t.id == _selected.first)
          : null;

      final table = WebCard(
        padding: EdgeInsets.zero,
        child: _MovementsTable(
          list: list,
          selected: _selected,
          onToggle: (id, sel) => setState(() {
            if (sel) {
              _selected.add(id);
            } else {
              _selected.remove(id);
            }
          }),
          onSelectAll: (sel) => setState(() {
            if (sel) {
              _selected
                ..clear()
                ..addAll(ids.whereType<int>());
            } else {
              _selected.clear();
            }
          }),
        ),
      );

      if (wide && selectedDto != null) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: table),
            const SizedBox(width: 16),
            SizedBox(
              width: 380,
              child: _DetailPanel(
                key: ValueKey(selectedDto.id),
                dto: selectedDto,
                onClose: () => setState(_selected.clear),
              ),
            ),
          ],
        );
      }
      return table;
    });
  }
}

// ---------------------------------------------------------------------------
// Tabla
// ---------------------------------------------------------------------------

class _MovementsTable extends ConsumerWidget {
  const _MovementsTable({
    required this.list,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
  });

  final List<TransactionDto> list;
  final Set<int> selected;
  final void Function(int id, bool selected) onToggle;
  final void Function(bool selected) onSelectAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(webAccountsByIdProvider);
    final categories = ref.watch(webCategoriesByIdProvider);
    final sort = ref.watch(webTxFilterProvider).sort;
    final sortIndex = (sort == WebTxSort.dateAsc || sort == WebTxSort.dateDesc)
        ? 0
        : 4;
    final ascending = sort == WebTxSort.dateAsc || sort == WebTxSort.amountAsc;

    void setSort(int columnIndex, bool asc) {
      final next = columnIndex == 0
          ? (asc ? WebTxSort.dateAsc : WebTxSort.dateDesc)
          : (asc ? WebTxSort.amountAsc : WebTxSort.amountDesc);
      ref.read(webTxFilterProvider.notifier).update((f) => f.copyWith(sort: next));
    }

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minWidth: MediaQuery.of(context).size.width - 340),
          child: DataTable(
            showCheckboxColumn: true,
            sortColumnIndex: sortIndex,
            sortAscending: ascending,
            onSelectAll: (v) => onSelectAll(v ?? false),
            columns: [
              DataColumn(label: const Text('Fecha'), onSort: setSort),
              const DataColumn(label: Text('Concepto')),
              const DataColumn(label: Text('Categoría')),
              const DataColumn(label: Text('Cuenta')),
              DataColumn(label: const Text('Importe'), numeric: true, onSort: setSort),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final t in list)
                _row(context, ref, t, accounts, categories),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, WidgetRef ref, TransactionDto t,
      Map<int, AccountDto> accounts, Map<int, CategoryDto> categories) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = t.type == TransactionType.income;
    final isTransfer = t.type == TransactionType.transfer;
    final color =
        isIncome ? Colors.green : (isTransfer ? scheme.outline : scheme.error);
    final catName = t.categoryId == null
        ? (isTransfer ? 'Transferencia' : '—')
        : webCategoryPath(t.categoryId, categories);
    final accountName = isTransfer
        ? '${accounts[t.accountId]?.name ?? '—'} → '
            '${accounts[t.toAccountId]?.name ?? '—'}'
        : (accounts[t.accountId]?.name ?? '—');
    return DataRow(
      selected: t.id != null && selected.contains(t.id),
      onSelectChanged:
          t.id == null ? null : (v) => onToggle(t.id!, v ?? false),
      cells: [
        DataCell(Text(DateFormat('dd/MM/yy').format(t.date))),
        DataCell(Text(t.concept.isEmpty ? '—' : t.concept)),
        DataCell(Text(catName, overflow: TextOverflow.ellipsis)),
        DataCell(Text(accountName, overflow: TextOverflow.ellipsis)),
        DataCell(WebMoneyText(
          isIncome ? t.amountCents : (isTransfer ? 0 : -t.amountCents),
          signed: !isTransfer,
          color: color,
          style: const TextStyle(fontWeight: FontWeight.w600),
        )),
        DataCell(IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: 'Editar',
          onPressed: () => showDialog(
              context: context,
              builder: (_) => WebMovementDialog(existing: t)),
        )),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Panel de detalle (edición en línea)
// ---------------------------------------------------------------------------

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({super.key, required this.dto, required this.onClose});
  final TransactionDto dto;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return WebCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Detalle', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close), onPressed: onClose),
              ],
            ),
            const SizedBox(height: 8),
            WebMovementForm(existing: dto, onDone: onClose, showCancel: false),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Acciones masivas
// ---------------------------------------------------------------------------

class _BatchBar extends ConsumerWidget {
  const _BatchBar({
    required this.selected,
    required this.onClear,
    required this.onDone,
  });
  final Set<int> selected;
  final VoidCallback onClear;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.close), onPressed: onClear),
            Text('${selected.length} seleccionados',
                style: TextStyle(color: scheme.onSecondaryContainer)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.label_outline),
              label: const Text('Categoría'),
              onPressed: () => _setCategory(context, ref),
            ),
            TextButton.icon(
              icon: const Icon(Icons.account_balance_outlined),
              label: const Text('Cuenta'),
              onPressed: () => _setAccount(context, ref),
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Borrar'),
              onPressed: () => _delete(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setCategory(BuildContext context, WidgetRef ref) async {
    final categories = ref.read(webCategoriesByIdProvider);
    final choice = await showDialog<_IdChoice>(
      context: context,
      builder: (_) => _PickDialog(
        title: 'Asignar categoría',
        options: [
          const _PickOption(null, 'Sin categoría'),
          ...(categories.values.toList()
                ..sort((a, b) => webCategoryPath(a.id, categories)
                    .compareTo(webCategoryPath(b.id, categories))))
              .map((c) => _PickOption(c.id, webCategoryPath(c.id, categories))),
        ],
      ),
    );
    if (choice == null) return;
    await ref
        .read(webClientProvider)!
        .batchTransactions('setCategory', selected.toList(),
            categoryId: choice.id);
    bumpWebRefresh(ref);
    onDone();
  }

  Future<void> _setAccount(BuildContext context, WidgetRef ref) async {
    final accounts = ref.read(webAccountsByIdProvider);
    final list = accounts.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final choice = await showDialog<_IdChoice>(
      context: context,
      builder: (_) => _PickDialog(
        title: 'Mover a la cuenta',
        options: [for (final a in list) _PickOption(a.id, a.name)],
      ),
    );
    if (choice?.id == null) return;
    await ref
        .read(webClientProvider)!
        .batchTransactions('setAccount', selected.toList(),
            accountId: choice!.id);
    bumpWebRefresh(ref);
    onDone();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar movimientos'),
        content: Text('¿Borrar ${selected.length} movimientos seleccionados?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(webClientProvider)!
        .batchTransactions('delete', selected.toList());
    bumpWebRefresh(ref);
    onDone();
  }
}

/// Resultado de un `_PickDialog` (envuelto para distinguir "sin selección" de
/// cancelar el diálogo).
class _IdChoice {
  const _IdChoice(this.id);
  final int? id;
}

class _PickOption {
  const _PickOption(this.id, this.label);
  final int? id;
  final String label;
}

class _PickDialog extends StatelessWidget {
  const _PickDialog({required this.title, required this.options});
  final String title;
  final List<_PickOption> options;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        height: 420,
        child: ListView(
          children: [
            for (final o in options)
              ListTile(
                title: Text(o.label),
                onTap: () => Navigator.pop(context, _IdChoice(o.id)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de filtros
// ---------------------------------------------------------------------------

class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar();

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  final _min = TextEditingController();
  final _max = TextEditingController();

  @override
  void initState() {
    super.initState();
    final f = ref.read(webTxFilterProvider);
    if (f.minCents != null) {
      _min.text = (f.minCents! / 100).toStringAsFixed(2).replaceAll('.', ',');
    }
    if (f.maxCents != null) {
      _max.text = (f.maxCents! / 100).toStringAsFixed(2).replaceAll('.', ',');
    }
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _update(WebTxFilter Function(WebTxFilter) fn) =>
      ref.read(webTxFilterProvider.notifier).update(fn);

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(webTxFilterProvider);
    final accounts = ref.watch(webAccountsByIdProvider);
    final categories = ref.watch(webCategoriesByIdProvider);

    return WebCard(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Tipos
          for (final type in TransactionType.values)
            FilterChip(
              label: Text(_typeLabel(type)),
              selected: f.types.contains(type),
              onSelected: (sel) => _update((x) {
                final next = {...x.types};
                sel ? next.add(type) : next.remove(type);
                return x.copyWith(types: next);
              }),
            ),
          const _VDiv(),
          // Cuentas
          OutlinedButton.icon(
            icon: const Icon(Icons.account_balance_outlined, size: 18),
            label: Text(f.accountIds.isEmpty
                ? 'Cuentas'
                : 'Cuentas (${f.accountIds.length})'),
            onPressed: () async {
              final sel = await _multiSelect(
                context,
                'Filtrar por cuenta',
                {for (final a in accounts.values) a.id: a.name},
                f.accountIds,
              );
              if (sel != null) _update((x) => x.copyWith(accountIds: sel));
            },
          ),
          // Categorías
          OutlinedButton.icon(
            icon: const Icon(Icons.category_outlined, size: 18),
            label: Text(f.categoryIds.isEmpty
                ? 'Categorías'
                : 'Categorías (${f.categoryIds.length})'),
            onPressed: () async {
              final sel = await _multiSelect(
                context,
                'Filtrar por categoría',
                {
                  for (final c in categories.values)
                    c.id: webCategoryPath(c.id, categories)
                },
                f.categoryIds,
              );
              if (sel != null) _update((x) => x.copyWith(categoryIds: sel));
            },
          ),
          const _VDiv(),
          // Rango de importe
          SizedBox(
            width: 110,
            child: TextField(
              controller: _min,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  isDense: true, labelText: 'Mín €'),
              onChanged: (v) =>
                  _update((x) => x.copyWith(minCents: Money.parseToCents(v))),
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _max,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  isDense: true, labelText: 'Máx €'),
              onChanged: (v) =>
                  _update((x) => x.copyWith(maxCents: Money.parseToCents(v))),
            ),
          ),
          const _VDiv(),
          // Rango de fechas
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(f.from == null && f.to == null
                ? 'Fechas'
                : '${f.from == null ? '…' : DateFormat('dd/MM/yy').format(f.from!)}'
                    ' – '
                    '${f.to == null ? '…' : DateFormat('dd/MM/yy').format(f.to!)}'),
            onPressed: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDateRange: (f.from != null && f.to != null)
                    ? DateTimeRange(start: f.from!, end: f.to!)
                    : null,
              );
              if (range != null) {
                _update((x) => x.copyWith(
                    from: range.start,
                    to: DateTime(range.end.year, range.end.month,
                        range.end.day, 23, 59, 59)));
              }
            },
          ),
          const _VDiv(),
          // Orden
          DropdownButton<WebTxSort>(
            value: f.sort,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                  value: WebTxSort.dateDesc, child: Text('Fecha ↓')),
              DropdownMenuItem(value: WebTxSort.dateAsc, child: Text('Fecha ↑')),
              DropdownMenuItem(
                  value: WebTxSort.amountDesc, child: Text('Importe ↓')),
              DropdownMenuItem(
                  value: WebTxSort.amountAsc, child: Text('Importe ↑')),
            ],
            onChanged: (v) =>
                v == null ? null : _update((x) => x.copyWith(sort: v)),
          ),
          if (f.hasContentFilters)
            TextButton.icon(
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Limpiar'),
              onPressed: () {
                _min.clear();
                _max.clear();
                ref.read(webTxFilterProvider.notifier).update((x) => x.cleared());
              },
            ),
        ],
      ),
    );
  }

  String _typeLabel(TransactionType t) => switch (t) {
        TransactionType.income => 'Ingresos',
        TransactionType.expense => 'Gastos',
        TransactionType.transfer => 'Transferencias',
      };
}

class _VDiv extends StatelessWidget {
  const _VDiv();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 28, child: VerticalDivider(width: 1));
}

/// Diálogo de selección múltiple genérico (id → etiqueta). Devuelve el nuevo
/// conjunto o `null` si se cancela.
Future<Set<int>?> _multiSelect(
  BuildContext context,
  String title,
  Map<int, String> options,
  Set<int> current,
) {
  final selected = {...current};
  final entries = options.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return showDialog<Set<int>>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          height: 420,
          child: ListView(
            children: [
              for (final e in entries)
                CheckboxListTile(
                  value: selected.contains(e.key),
                  title: Text(e.value),
                  onChanged: (v) => setState(() {
                    (v ?? false) ? selected.add(e.key) : selected.remove(e.key);
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, <int>{}),
              child: const Text('Quitar filtro')),
          FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Aplicar')),
        ],
      ),
    ),
  );
}
