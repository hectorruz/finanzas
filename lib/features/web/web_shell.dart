import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../data/models/enums.dart';
import 'web_models.dart';
import 'web_movement_dialog.dart';
import 'web_providers.dart';

/// Panel de escritorio: navegación lateral + páginas. Optimizado para pantallas
/// anchas (tabla de movimientos, saldos por cuenta).
class WebShell extends ConsumerStatefulWidget {
  const WebShell({super.key});
  @override
  ConsumerState<WebShell> createState() => _WebShellState();
}

class _WebShellState extends ConsumerState<WebShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.account_balance_wallet, size: 28),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IconButton(
                    tooltip: 'Desconectar',
                    icon: const Icon(Icons.logout),
                    onPressed: () =>
                        ref.read(webClientProvider.notifier).state = null,
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.swap_vert), label: Text('Movimientos')),
              NavigationRailDestination(
                  icon: Icon(Icons.account_balance), label: Text('Cuentas')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _index == 0 ? const _MovementsPage() : const _AccountsPage(),
          ),
        ],
      ),
    );
  }
}

class _MovementsPage extends ConsumerWidget {
  const _MovementsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(webTransactionsProvider);
    final accounts = ref.watch(webAccountsByIdProvider);
    final categories = ref.watch(webCategoriesByIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('Movimientos',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      ref.read(webTxQueryProvider.notifier).state = v,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refrescar',
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(webRefreshProvider.notifier).state++,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nuevo'),
                onPressed: () => showDialog(
                    context: context, builder: (_) => const WebMovementDialog()),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: txns.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (list) => list.isEmpty
                ? const Center(child: Text('Sin movimientos.'))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Fecha')),
                          DataColumn(label: Text('Concepto')),
                          DataColumn(label: Text('Categoría')),
                          DataColumn(label: Text('Cuenta')),
                          DataColumn(label: Text('Importe'), numeric: true),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final t in list)
                            _row(context, ref, t, accounts, categories),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  DataRow _row(
    BuildContext context,
    WidgetRef ref,
    TransactionDto t,
    Map<int, AccountDto> accounts,
    Map<int, CategoryDto> categories,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = t.type == TransactionType.income;
    final color = isIncome
        ? Colors.green
        : (t.type == TransactionType.transfer ? scheme.outline : scheme.error);
    return DataRow(cells: [
      DataCell(Text(DateFormat('dd/MM/yyyy').format(t.date))),
      DataCell(Text(t.concept.isEmpty ? '—' : t.concept)),
      DataCell(Text(categories[t.categoryId]?.name ?? '—')),
      DataCell(Text(accounts[t.accountId]?.name ?? '—')),
      DataCell(Text(
        '${isIncome ? '+' : (t.type == TransactionType.transfer ? '' : '-')}'
        '${Money(t.amountCents).format()}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      )),
      DataCell(Row(
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => showDialog(
                context: context,
                builder: (_) => WebMovementDialog(existing: t)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _delete(context, ref, t),
          ),
        ],
      )),
    ]);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, TransactionDto t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar movimiento'),
        content: Text('¿Borrar "${t.concept}"?'),
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
    if (ok != true || t.id == null) return;
    await ref.read(webClientProvider)!.deleteTransaction(t.id!);
    ref.read(webRefreshProvider.notifier).state++;
  }
}

class _AccountsPage extends ConsumerWidget {
  const _AccountsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(webAccountsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Cuentas',
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        const Divider(height: 1),
        Expanded(
          child: accounts.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (list) {
              final total = list
                  .where((a) => a.includeInTotal)
                  .fold<int>(0, (s, a) => s + a.balanceCents);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      title: const Text('Balance total'),
                      trailing: Text(Money(total).format(),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final a in list)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(a.colorValue),
                          child: const Icon(Icons.account_balance,
                              color: Colors.white, size: 20),
                        ),
                        title: Text(a.name),
                        subtitle: a.parentId != null ? const Text('Subcuenta') : null,
                        trailing: Text(Money(a.balanceCents).format(),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
