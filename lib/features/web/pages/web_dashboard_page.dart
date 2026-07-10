import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/models/enums.dart';
import '../analytics/web_analytics.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../web_router.dart';
import '../widgets/web_charts.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_pickers.dart';
import '../widgets/web_ui.dart';

/// Panel principal: KPIs, gráficas interactivas (recalculadas en cliente),
/// objetivos, cuentas y últimos movimientos. Respeta el modo privacidad y el
/// orden/selección de tarjetas de los ajustes del móvil (`dashboardCards`).
class WebDashboardPage extends ConsumerWidget {
  const WebDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(webAccountsProvider).valueOrNull ?? const [];
    final txnsAsync = ref.watch(webAllTransactionsProvider);
    final categories = ref.watch(webCategoriesByIdProvider);
    final accountsById = ref.watch(webAccountsByIdProvider);
    final goals = ref.watch(webGoalsProvider).valueOrNull ?? const [];
    final settings = ref.watch(webSettingsProvider).valueOrNull ?? SettingsDto();
    final hide = ref.watch(webHideAmountsProvider);

    final cards = settings.dashboardCards;
    bool show(String card) => cards.isEmpty || cards.contains(card);

    final total = accounts
        .where((a) => a.includeInTotal && !a.archived)
        .fold<int>(0, (s, a) => s + a.balanceCents);

    return WebPage(
      title: 'Panel',
      subtitle: DateFormat("EEEE d 'de' MMMM", 'es').format(DateTime.now()),
      actions: [
        IconButton(
          tooltip: 'Refrescar',
          icon: const Icon(Icons.refresh),
          onPressed: () => bumpWebRefresh(ref),
        ),
      ],
      child: txnsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Error: $e'),
        data: (txns) {
          final now = DateTime.now();
          final monthStart = DateTime(now.year, now.month);
          final prevStart = DateTime(now.year, now.month - 1);
          var income = 0, expense = 0, prevExpense = 0;
          for (final t in txns) {
            if (!t.date.isBefore(monthStart)) {
              if (t.type == TransactionType.income) income += t.amountCents;
              if (t.type == TransactionType.expense) expense += t.amountCents;
            } else if (!t.date.isBefore(prevStart)) {
              if (t.type == TransactionType.expense) prevExpense += t.amountCents;
            }
          }
          final expenseChange = monthOverMonthChange(expense, prevExpense);
          final buckets = monthlyTotals(txns, months: 6, now: now);
          final breakdown = categoryBreakdown(txns, categories,
              type: TransactionType.expense, from: monthStart);
          final evolution =
              balanceEvolution(txns, currentTotalCents: total, days: 90, now: now);
          final recent = [...txns]..sort((a, b) => b.date.compareTo(a.date));

          return LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final kpiCols = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 520
                    ? 2
                    : 1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GridView.count(
                  crossAxisCount: kpiCols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 2.3,
                  children: [
                    WebKpiCard(
                      label: 'Balance total',
                      icon: Icons.account_balance_wallet_outlined,
                      value: WebMoneyText(total),
                    ),
                    WebKpiCard(
                      label: 'Ingresos (mes)',
                      icon: Icons.south_west,
                      valueColor: Colors.green,
                      value: WebMoneyText(income),
                    ),
                    WebKpiCard(
                      label: 'Gastos (mes)',
                      icon: Icons.north_east,
                      valueColor: Theme.of(context).colorScheme.error,
                      trailing: expenseChange == null
                          ? null
                          : _DeltaChip(change: expenseChange),
                      value: WebMoneyText(expense),
                    ),
                    WebKpiCard(
                      label: 'Ahorro (mes)',
                      icon: Icons.savings_outlined,
                      valueColor: (income - expense) >= 0
                          ? Colors.green
                          : Theme.of(context).colorScheme.error,
                      value: WebMoneyText(income - expense, signed: true),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Gráficas: donut + barras.
                if (show('monthComparison'))
                  _ResponsiveRow(
                    wide: wide,
                    left: _ChartCard(
                      title: 'Gasto por categoría (mes)',
                      child: WebDonutChart(slices: breakdown, hideAmounts: hide),
                    ),
                    right: _ChartCard(
                      title: 'Ingresos vs. gastos',
                      child:
                          WebIncomeExpenseBars(buckets: buckets, hideAmounts: hide),
                    ),
                  ),
                const SizedBox(height: 16),
                _ChartCard(
                  title: 'Evolución del balance (90 días)',
                  child: WebBalanceLine(points: evolution, hideAmounts: hide),
                ),
                const SizedBox(height: 16),
                _ResponsiveRow(
                  wide: wide,
                  left: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (show('recentMovements'))
                        _RecentCard(
                          recent: recent,
                          categories: categories,
                          accounts: accountsById,
                        ),
                    ],
                  ),
                  right: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (show('goals') && goals.isNotEmpty) ...[
                        _GoalsCard(goals: goals),
                        const SizedBox(height: 16),
                      ],
                      if (show('totalBalance') || show('accountsBalance'))
                        _AccountsCard(accounts: accounts),
                    ],
                  ),
                ),
              ],
            );
          });
        },
      ),
    );
  }
}

class _ResponsiveRow extends StatelessWidget {
  const _ResponsiveRow({
    required this.wide,
    required this.left,
    required this.right,
  });
  final bool wide;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(children: [left, const SizedBox(height: 16), right]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.change});
  final double change;

  @override
  Widget build(BuildContext context) {
    final up = change > 0;
    final color = up ? Theme.of(context).colorScheme.error : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12, color: color),
          const SizedBox(width: 2),
          Text('${(change.abs() * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.recent,
    required this.categories,
    required this.accounts,
  });
  final List<TransactionDto> recent;
  final Map<int, CategoryDto> categories;
  final Map<int, AccountDto> accounts;

  @override
  Widget build(BuildContext context) {
    return WebCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Últimos movimientos',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => context.go(WebRoutes.movements),
                child: const Text('Ver todos'),
              ),
            ],
          ),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('Sin movimientos todavía.')),
            )
          else
            for (final t in recent.take(8))
              _recentTile(context, t, categories, accounts),
        ],
      ),
    );
  }

  Widget _recentTile(BuildContext context, TransactionDto t,
      Map<int, CategoryDto> categories, Map<int, AccountDto> accounts) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = t.type == TransactionType.income;
    final isTransfer = t.type == TransactionType.transfer;
    final color =
        isIncome ? Colors.green : (isTransfer ? scheme.outline : scheme.error);
    final cat = t.categoryId != null ? categories[t.categoryId] : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: WebColorDot(
        colorValue: cat?.colorValue ?? 0xFF9E9E9E,
        icon: isTransfer ? Icons.swap_horiz : webIconFor(cat?.iconName ?? 'category'),
      ),
      title: Text(t.concept.isEmpty ? (cat?.name ?? 'Movimiento') : t.concept),
      subtitle: Text(
        '${DateFormat('dd/MM/yyyy').format(t.date)} · '
        '${accounts[t.accountId]?.name ?? '—'}',
      ),
      trailing: WebMoneyText(
        isIncome ? t.amountCents : (isTransfer ? 0 : -t.amountCents),
        signed: !isTransfer,
        color: color,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _GoalsCard extends StatelessWidget {
  const _GoalsCard({required this.goals});
  final List<GoalDto> goals;

  @override
  Widget build(BuildContext context) {
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Objetivos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final g in goals.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(g.name)),
                      Text('${(g.progress * 100).round()}%',
                          style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: g.progress,
                      minHeight: 8,
                      color: Color(g.colorValue),
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

class _AccountsCard extends StatelessWidget {
  const _AccountsCard({required this.accounts});
  final List<AccountDto> accounts;

  @override
  Widget build(BuildContext context) {
    final top = accounts
        .where((a) => !a.archived && a.parentId == null)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cuentas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (top.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Sin cuentas.')),
            )
          else
            for (final a in top)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: WebColorDot(
                  colorValue: a.colorValue,
                  icon: webIconFor(a.iconName, fallback: Icons.account_balance),
                ),
                title: Text(a.name),
                trailing: WebMoneyText(a.balanceCents,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
        ],
      ),
    );
  }
}
