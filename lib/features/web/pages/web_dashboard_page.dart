import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/models/enums.dart';
import '../analytics/recurring_timeline.dart';
import '../analytics/web_analytics.dart';
import '../web_dashboard_cards.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../web_router.dart';
import '../widgets/web_charts.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_pickers.dart';
import '../widgets/web_ui.dart';

/// Panel principal: KPIs, gráficas interactivas (recalculadas en cliente),
/// objetivos, cuentas y últimos movimientos. Qué tarjetas se muestran y en qué
/// orden lo decide `AppSettings.webDashboardCards` (independiente del inicio del
/// móvil; ver `web_dashboard_cards.dart`). Respeta el modo privacidad.
class WebDashboardPage extends ConsumerWidget {
  const WebDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(webAccountsProvider).valueOrNull ?? const [];
    final txnsAsync = ref.watch(webAllTransactionsProvider);
    final categories = ref.watch(webCategoriesByIdProvider);
    final accountsById = ref.watch(webAccountsByIdProvider);
    final goals = ref.watch(webGoalsProvider).valueOrNull ?? const [];
    final recurring = ref.watch(webRecurringProvider).valueOrNull ?? const [];
    final settings = ref.watch(webSettingsProvider).valueOrNull ?? SettingsDto();
    final hide = ref.watch(webHideAmountsProvider);

    final rawKeys = settings.webDashboardCards.isEmpty
        ? kDefaultWebDashboard
        : settings.webDashboardCards;
    final keys = rawKeys.where((k) => webCardByKey(k) != null).toList();
    final kpiKeys = keys.where(webCardIsKpi).toList();
    final blockKeys = keys.where((k) => !webCardIsKpi(k)).toList();

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
          final upcoming = upcomingTimeline(recurring,
              from: now, to: now.add(const Duration(days: 30)));
          final savingsRate = income == 0 ? null : (income - expense) / income;

          return LayoutBuilder(builder: (context, constraints) {
            final scheme = Theme.of(context).colorScheme;
            final baseCols = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 520
                    ? 2
                    : 1;
            final kpiCols = kpiKeys.isEmpty
                ? 1
                : (kpiKeys.length < baseCols ? kpiKeys.length : baseCols);

            Widget kpiFor(String key) {
              switch (key) {
                case 'kpiTotalBalance':
                  return WebKpiCard(
                    label: 'Balance total',
                    icon: Icons.account_balance_wallet_outlined,
                    value: WebMoneyText(total),
                  );
                case 'kpiIncome':
                  return WebKpiCard(
                    label: 'Ingresos (mes)',
                    icon: Icons.south_west,
                    valueColor: Colors.green,
                    value: WebMoneyText(income),
                  );
                case 'kpiExpense':
                  return WebKpiCard(
                    label: 'Gastos (mes)',
                    icon: Icons.north_east,
                    valueColor: scheme.error,
                    trailing: expenseChange == null
                        ? null
                        : _DeltaChip(change: expenseChange),
                    value: WebMoneyText(expense),
                  );
                case 'kpiSavings':
                  return WebKpiCard(
                    label: 'Ahorro (mes)',
                    icon: Icons.savings_outlined,
                    valueColor:
                        (income - expense) >= 0 ? Colors.green : scheme.error,
                    value: WebMoneyText(income - expense, signed: true),
                  );
                case 'kpiSavingsRate':
                  return WebKpiCard(
                    label: 'Tasa de ahorro',
                    icon: Icons.percent,
                    valueColor: (savingsRate ?? 0) >= 0
                        ? Colors.green
                        : scheme.error,
                    value: Text(savingsRate == null
                        ? '—'
                        : '${(savingsRate * 100).round()}%'),
                  );
                default:
                  return const SizedBox.shrink();
              }
            }

            // Devuelve null para omitir la tarjeta (p. ej. objetivos sin datos),
            // así no queda un hueco de separación vacío.
            Widget? blockFor(String key) {
              switch (key) {
                case 'categoryDonut':
                  return _ChartCard(
                    title: 'Gasto por categoría (mes)',
                    child: WebDonutChart(slices: breakdown, hideAmounts: hide),
                  );
                case 'incomeExpenseBars':
                  return _ChartCard(
                    title: 'Ingresos vs. gastos',
                    child: WebIncomeExpenseBars(
                        buckets: buckets, hideAmounts: hide),
                  );
                case 'balanceLine':
                  return _ChartCard(
                    title: 'Evolución del balance (90 días)',
                    child: WebBalanceLine(points: evolution, hideAmounts: hide),
                  );
                case 'topCategories':
                  return _TopCategoriesCard(slices: breakdown);
                case 'upcomingRecurring':
                  return _UpcomingRecurringCard(
                      occurrences: upcoming, accounts: accountsById);
                case 'recentMovements':
                  return _RecentCard(
                    recent: recent,
                    categories: categories,
                    accounts: accountsById,
                  );
                case 'goals':
                  return goals.isEmpty ? null : _GoalsCard(goals: goals);
                case 'accounts':
                  return _AccountsCard(accounts: accounts);
                default:
                  return null;
              }
            }

            final blocks = [
              for (final k in blockKeys)
                if (blockFor(k) case final w?) w,
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (kpiKeys.isNotEmpty)
                  GridView.count(
                    crossAxisCount: kpiCols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 2.3,
                    children: [for (final k in kpiKeys) kpiFor(k)],
                  ),
                for (final w in blocks) ...[
                  const SizedBox(height: 16),
                  w,
                ],
              ],
            );
          });
        },
      ),
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

class _TopCategoriesCard extends StatelessWidget {
  const _TopCategoriesCard({required this.slices});
  final List<CategorySlice> slices;

  @override
  Widget build(BuildContext context) {
    final top = [...slices]
      ..sort((a, b) => b.totalCents.compareTo(a.totalCents));
    final shown = top.take(6).toList();
    final maxCents = shown.isEmpty ? 0 : shown.first.totalCents;
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Top categorías de gasto (mes)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Sin gastos este mes.')),
            )
          else
            for (final s in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(s.label,
                                overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        WebMoneyText(s.totalCents,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: maxCents == 0 ? 0 : s.totalCents / maxCents,
                        minHeight: 6,
                        color: Color(s.colorValue),
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
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

class _UpcomingRecurringCard extends StatelessWidget {
  const _UpcomingRecurringCard({
    required this.occurrences,
    required this.accounts,
  });
  final List<RecurringOccurrence> occurrences;
  final Map<int, AccountDto> accounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = occurrences.take(8).toList();
    return WebCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Próximos recurrentes (30 días)',
              style: Theme.of(context).textTheme.titleMedium),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('Sin cargos próximos.')),
            )
          else
            for (final o in shown)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: WebColorDot(
                  colorValue: o.rule.type == TransactionType.income
                      ? 0xFF4CAF50
                      : 0xFFF44336,
                  icon: o.rule.type == TransactionType.income
                      ? Icons.south_west
                      : Icons.north_east,
                ),
                title: Text(
                    o.rule.concept.isEmpty ? o.rule.name : o.rule.concept),
                subtitle: Text('${DateFormat('dd/MM/yyyy').format(o.date)} · '
                    '${accounts[o.rule.accountId]?.name ?? '—'}'),
                trailing: WebMoneyText(
                  o.signedCents,
                  signed: true,
                  color: o.rule.type == TransactionType.income
                      ? Colors.green
                      : scheme.error,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
        ],
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
