import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/money.dart';
import '../../core/router/app_router.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/async_value_view.dart';
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

  void _clearSelection() => setState(_selected.clear);

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
          : AppBar(
              title: const Text('Movimientos'),
              actions: [
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
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              onPressed: () => context.push(Routes.movementEditor),
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
          if (!filter.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, size: 16),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Filtros activos')),
                  TextButton(
                    onPressed: () => ref
                        .read(transactionFilterProvider.notifier)
                        .state = const TransactionFilter(),
                    child: const Text('Limpiar'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: AsyncValueView(
              value: transactions,
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No hay movimientos que coincidan.'),
                    ),
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
                                context.push(Routes.movementEditor,
                                    extra: t.id);
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
          for (final c in categories)
            ListTile(
              leading: Icon(Icons.circle, color: Color(c.colorValue), size: 16),
              title: Text(c.name),
              onTap: () => Navigator.pop(context, c.id),
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
          for (final a in accounts)
            ListTile(
              leading: Icon(Icons.circle, color: Color(a.colorValue), size: 16),
              title: Text(a.name),
              onTap: () => Navigator.pop(context, a.id),
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
          Text(
            'Neto: ${Money(netCents).formatSigned()}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: netCents < 0 ? scheme.error : Colors.green.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
