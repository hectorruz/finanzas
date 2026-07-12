import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../core/router/app_router.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/lookups.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/async_value_view.dart';
import '../../shared/widgets/money_text.dart';
import 'movement_detail_sheet.dart';
import 'movements_filter_sheet.dart';
import 'transaction_tile.dart';

class MovementsScreen extends ConsumerStatefulWidget {
  const MovementsScreen({super.key});

  @override
  ConsumerState<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends ConsumerState<MovementsScreen> {
  final Set<int> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  bool _searching = false;
  final _searchController = TextEditingController();

  void _clearSelection() => setState(_selected.clear);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    final filter = ref.read(transactionFilterProvider);
    ref.read(transactionFilterProvider.notifier).state =
        filter.copyWith(query: value);
  }

  void _closeSearch() {
    setState(() => _searching = false);
    _searchController.clear();
    _setQuery('');
  }

  /// Limpia todos los filtros (incluida la búsqueda) y cierra la barra de búsqueda.
  void _clearAllFilters() {
    ref.read(transactionFilterProvider.notifier).state =
        const TransactionFilter();
    _searchController.clear();
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(filteredTransactionsProvider);
    final filter = ref.watch(transactionFilterProvider);

    return Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
              title: Text('${_selected.length} seleccionados'),
              actions: [
                IconButton(
                  tooltip: 'Cambiar categoría',
                  icon: const Icon(Icons.label_outline),
                  onPressed: _bulkCategory,
                ),
                IconButton(
                  tooltip: 'Mover de cuenta',
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  onPressed: _bulkAccount,
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _bulkDelete,
                ),
              ],
            )
          : _searching
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _closeSearch,
                  ),
                  title: TextField(
                    controller: _searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Buscar concepto, categoría o cuenta…',
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _setQuery('');
                                setState(() {});
                              },
                            ),
                    ),
                    onChanged: (v) {
                      _setQuery(v);
                      setState(() {}); // refresca el botón de limpiar
                    },
                  ),
                )
              : AppBar(
                  title: const Text('Movimientos'),
                  actions: [
                    IconButton(
                      tooltip: 'Buscar',
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        _searchController.text = filter.query;
                        setState(() => _searching = true);
                      },
                    ),
                    IconButton(
                      tooltip: 'Recurrentes',
                      icon: const Icon(Icons.autorenew),
                      onPressed: () => context.push(Routes.recurring),
                    ),
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        IconButton(
                          tooltip: 'Filtros',
                          icon: const Icon(Icons.filter_list),
                          onPressed: _openFilters,
                        ),
                        if (!filter.isEmpty)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: CircleAvatar(
                              radius: 4,
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'scan',
            tooltip: 'Escanear ticket',
            onPressed: () => context.push(Routes.receiptScan),
            child: const Icon(Icons.document_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add',
            tooltip: 'Nuevo movimiento',
            onPressed: () => context.push(Routes.movementEditor),
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterChipsBar(filter: filter),
          Expanded(
            child: AsyncValueView(
              value: transactions,
              data: (list) {
                if (list.isEmpty) {
                  return _EmptyState(
                    filtered: !filter.isEmpty,
                    onClear: _clearAllFilters,
                  );
                }
                final total = list.fold<int>(0, (s, t) => s + t.signedCents);
                return Column(
                  children: [
                    _SummaryBar(count: list.length, netCents: total),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final t = list[i];
                          return TransactionTile(
                            txn: t,
                            selected: _selected.contains(t.id),
                            onTap: () {
                              if (_selecting) {
                                _toggle(t.id);
                              } else {
                                showMovementDetailSheet(context, t.id);
                              }
                            },
                            onLongPress: () => _toggle(t.id),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const MovementsFilterSheet(),
    );
  }

  Future<void> _bulkDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar movimientos'),
        content: Text('¿Eliminar ${_selected.length} movimientos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(transactionRepositoryProvider)
          .deleteMany(_selected.toList());
      _clearSelection();
    }
  }

  Future<void> _bulkCategory() async {
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    final chosen = await showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        children: [
          const ListTile(title: Text('Asignar categoría')),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Sin categoría'),
            onTap: () => Navigator.pop(context, -1),
          ),
          for (final e in flattenCategories(categories))
            ListTile(
              contentPadding:
                  EdgeInsets.only(left: 16 + e.depth * 24.0, right: 16),
              leading: Icon(Icons.circle,
                  color: Color(e.value.colorValue),
                  size: e.depth == 0 ? 16 : 12),
              title: Text(e.value.name),
              onTap: () => Navigator.pop(context, e.value.id),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await ref
        .read(transactionRepositoryProvider)
        .bulkSetCategory(_selected.toList(), chosen == -1 ? null : chosen);
    _clearSelection();
  }

  Future<void> _bulkAccount() async {
    final accounts = ref.read(accountsProvider).valueOrNull ?? const [];
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        children: [
          const ListTile(title: Text('Mover a la cuenta')),
          for (final e in flattenAccounts(accounts))
            ListTile(
              contentPadding:
                  EdgeInsets.only(left: 16 + e.depth * 24.0, right: 16),
              leading: Icon(Icons.circle,
                  color: Color(e.value.colorValue),
                  size: e.depth == 0 ? 16 : 12),
              title: Text(e.value.name),
              onTap: () => Navigator.pop(context, e.value.id),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await ref
        .read(transactionRepositoryProvider)
        .bulkSetAccount(_selected.toList(), chosen);
    _clearSelection();
  }
}

String _typeLabel(TransactionType t) => switch (t) {
      TransactionType.income => 'Ingresos',
      TransactionType.expense => 'Gastos',
      TransactionType.transfer => 'Transferencias',
    };

/// Barra de chips que representa los filtros activos (salvo la búsqueda de
/// texto, que ya la refleja la barra de búsqueda). Cada chip se puede quitar.
class _FilterChipsBar extends ConsumerWidget {
  const _FilterChipsBar({required this.filter});
  final TransactionFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsById = ref.watch(accountsByIdProvider);
    final categoriesById = ref.watch(categoriesByIdProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);

    final chips = <Widget>[
      for (final t in filter.types)
        InputChip(
          label: Text(_typeLabel(t)),
          onDeleted: () => notifier.state =
              filter.copyWith(types: {...filter.types}..remove(t)),
        ),
      for (final id in filter.accountIds)
        InputChip(
          avatar: const Icon(Icons.account_balance_wallet_outlined, size: 16),
          label: Text(accountsById[id]?.name ?? 'Cuenta'),
          onDeleted: () => notifier.state =
              filter.copyWith(accountIds: {...filter.accountIds}..remove(id)),
        ),
      for (final id in filter.categoryIds)
        InputChip(
          avatar: const Icon(Icons.label_outline, size: 16),
          label: Text(categoriesById[id]?.name ?? 'Categoría'),
          onDeleted: () => notifier.state = filter.copyWith(
              categoryIds: {...filter.categoryIds}..remove(id)),
        ),
      if (filter.minCents != null || filter.maxCents != null)
        InputChip(
          label: Text(_amountLabel(filter.minCents, filter.maxCents)),
          onDeleted: () => notifier.state = filter.copyWith(clearAmounts: true),
        ),
      if (filter.from != null || filter.to != null)
        InputChip(
          avatar: const Icon(Icons.calendar_today, size: 14),
          label: Text(_dateLabel(filter.from, filter.to)),
          onDeleted: () => notifier.state = filter.copyWith(clearDates: true),
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: -4, children: chips),
          ),
          TextButton(
            onPressed: () => notifier.state = const TransactionFilter(),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
  }

  String _amountLabel(int? min, int? max) {
    String fmt(int c) => Money(c).format();
    if (min != null && max != null) return '${fmt(min)} – ${fmt(max)}';
    if (min != null) return '≥ ${fmt(min)}';
    return '≤ ${fmt(max!)}';
  }

  String _dateLabel(DateTime? from, DateTime? to) {
    final f = DateFormat('d/M/yy');
    if (from != null && to != null) {
      return '${f.format(from)} – ${f.format(to)}';
    }
    if (from != null) return 'Desde ${f.format(from)}';
    return 'Hasta ${f.format(to!)}';
  }
}

/// Estado vacío: distingue "sin resultados de búsqueda/filtro" de "sin datos".
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onClear});
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(filtered ? Icons.search_off : Icons.receipt_long_outlined,
                size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'Sin resultados para tu búsqueda.'
                  : 'No hay movimientos todavía.',
              textAlign: TextAlign.center,
            ),
            if (filtered) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear_all),
                label: const Text('Limpiar filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.count, required this.netCents});
  final int count;
  final int netCents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: scheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$count movimientos'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Neto: ', style: TextStyle(fontWeight: FontWeight.w600)),
              MoneyText(
                netCents,
                signed: true,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: netCents < 0 ? scheme.error : Colors.green.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
