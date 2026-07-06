import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/money.dart';
import '../../core/router/app_router.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/async_value_view.dart';
import '../../shared/widgets/money_text.dart';
import '../accounts/account_editor_screen.dart';
import '../home_shell.dart';
import '../movements/movement_detail_sheet.dart';
import '../movements/transaction_tile.dart';
import '../settings/goals_screen.dart';
import 'dashboard_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final cards = settings.cards;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          IconButton(
            tooltip: settings.hideAmounts ? 'Mostrar importes' : 'Ocultar importes',
            icon: Icon(
                settings.hideAmounts ? Icons.visibility_off : Icons.visibility),
            onPressed: () => ref
                .read(settingsRepositoryProvider)
                .update((s) => s.hideAmounts = !s.hideAmounts),
          ),
          IconButton(
            tooltip: 'Configurar inicio',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push(Routes.dashboardConfig),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'scan_home',
            tooltip: 'Escanear ticket',
            onPressed: () => context.push(Routes.receiptScan),
            child: const Icon(Icons.document_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add_home',
            tooltip: 'Nuevo movimiento',
            onPressed: () => context.push(Routes.movementEditor),
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(totalBalanceProvider);
          ref.invalidate(balanceSubtotalsProvider);
          ref.invalidate(monthComparisonProvider);
          ref.invalidate(recentTransactionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildCard(context, ref, card, settings.goalsEnabled),
              ),
            if (cards.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay tarjetas activas. Toca el icono de ajustes para '
                  'configurar tu pantalla de inicio.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    DashboardCardType card,
    bool goalsEnabled,
  ) {
    switch (card) {
      case DashboardCardType.totalBalance:
        return const _TotalBalanceCard();
      case DashboardCardType.accountsBalance:
        return const _AccountsBalanceCard();
      case DashboardCardType.monthComparison:
        return const _MonthComparisonCard();
      case DashboardCardType.recentMovements:
        return const _RecentMovementsCard();
      case DashboardCardType.quickAdd:
        return const _QuickAddCard();
      case DashboardCardType.scanReceipt:
        return const _ScanReceiptCard();
      case DashboardCardType.goals:
        return goalsEnabled ? const _GoalsCard() : const SizedBox.shrink();
    }
  }
}

class _TotalBalanceCard extends ConsumerWidget {
  const _TotalBalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(totalBalanceProvider);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.accounts),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet,
                      size: 20, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Balance total',
                        style: TextStyle(color: scheme.onPrimaryContainer)),
                  ),
                  Icon(Icons.chevron_right,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.6)),
                ],
              ),
              const SizedBox(height: 8),
              AsyncValueView(
                value: total,
                data: (cents) => MoneyText(
                  cents,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const _BalanceSubtotals(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtotales configurables mostrados bajo el balance total, más pequeños.
class _BalanceSubtotals extends ConsumerWidget {
  const _BalanceSubtotals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(balanceSubtotalsProvider).valueOrNull ?? const [];
    if (subs.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in subs)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      s.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MoneyText(
                    s.cents,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
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

class _AccountsBalanceCard extends ConsumerWidget {
  const _AccountsBalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(accountsCardRowsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.account_balance_wallet,
              title: 'Cuentas',
              onTap: () => context.push(Routes.accounts),
            ),
            AsyncValueView(
              value: rows,
              data: (list) => Column(
                children: [
                  for (final row in list)
                    ListTile(
                      contentPadding:
                          EdgeInsets.only(left: row.depth * 24.0),
                      dense: true,
                      leading: Icon(Icons.circle,
                          size: row.depth == 0 ? 14 : 10,
                          color: Color(row.account.colorValue)),
                      title: Text(row.account.name),
                      trailing: MoneyText(row.rolledCents),
                      onTap: () => context.push(
                        Routes.accountEditor,
                        extra: AccountEditorArgs(accountId: row.account.id),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthComparisonCard extends ConsumerWidget {
  const _MonthComparisonCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparison = ref.watch(monthComparisonProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.calendar_month,
              title: 'Este mes',
              onTap: () => ref
                  .read(requestedNavSectionProvider.notifier)
                  .state = NavSection.movements,
            ),
            AsyncValueView(
              value: comparison,
              data: (c) {
                final change = c.expenseChangePercent;
                final scheme = Theme.of(context).colorScheme;
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Ingresos'),
                        MoneyText(c.currentIncome,
                            style: TextStyle(color: Colors.green.shade600)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Gastos'),
                        MoneyText(c.currentExpense,
                            style: TextStyle(color: scheme.error)),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('vs. mes pasado'),
                        if (change == null)
                          const Text('—')
                        else
                          Text(
                            '${change >= 0 ? '+' : ''}'
                            '${change.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: change > 0
                                  ? scheme.error
                                  : Colors.green.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentMovementsCard extends ConsumerWidget {
  const _RecentMovementsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTransactionsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _CardHeader(
                icon: Icons.history,
                title: 'Últimos movimientos',
                onTap: () => ref
                    .read(requestedNavSectionProvider.notifier)
                    .state = NavSection.movements,
              ),
            ),
            AsyncValueView(
              value: recent,
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aún no hay movimientos.'),
                  );
                }
                return Column(
                  children: [
                    for (final t in list)
                      TransactionTile(
                        txn: t,
                        dense: true,
                        onTap: () => showMovementDetailSheet(context, t.id),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddCard extends StatelessWidget {
  const _QuickAddCard();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: Colors.green.shade600,
            ),
            onPressed: () => context.push(
              Routes.movementEditor,
              extra: TransactionType.income,
            ),
            icon: const Icon(Icons.add),
            label: const Text('Ingreso'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => context.push(Routes.movementEditor),
            icon: const Icon(Icons.remove),
            label: const Text('Gasto'),
          ),
        ),
      ],
    );
  }
}

class _ScanReceiptCard extends StatelessWidget {
  const _ScanReceiptCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.document_scanner)),
        title: const Text('Escanear ticket'),
        subtitle: const Text('Detecta importe, comercio y categoría'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.receiptScan),
      ),
    );
  }
}

class _GoalsCard extends ConsumerWidget {
  const _GoalsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.flag,
              title: 'Objetivos',
              onTap: () => ref
                  .read(requestedNavSectionProvider.notifier)
                  .state = NavSection.goals,
            ),
            AsyncValueView(
              value: goals,
              data: (list) {
                if (list.isEmpty) {
                  return const Text('Crea objetivos desde Ajustes.');
                }
                return Column(
                  children: [
                    for (final g in list)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(g.name),
                                Consumer(
                                  builder: (context, ref, _) =>
                                      ref.watch(hideAmountsProvider)
                                          ? const Text(kHiddenAmount)
                                          : Text(
                                              '${Money(g.currentCents).format()} / '
                                              '${Money(g.targetCents).format()}'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: g.progress,
                              borderRadius: BorderRadius.circular(8),
                              minHeight: 8,
                            ),
                            if (goalPlanLabel(g) != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  goalPlanLabel(g)!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.title, this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.outline),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}
