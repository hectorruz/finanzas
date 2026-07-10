import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/enums.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_pickers.dart';
import '../widgets/web_ui.dart';

/// Calendario de movimientos: rejilla del mes con el neto por día (verde/rojo),
/// y el detalle del día seleccionado. Extra de escritorio.
class WebCalendarView extends ConsumerStatefulWidget {
  const WebCalendarView({super.key});

  @override
  ConsumerState<WebCalendarView> createState() => _WebCalendarViewState();
}

class _WebCalendarViewState extends ConsumerState<WebCalendarView> {
  late DateTime _month;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shift(int months) => setState(() {
        _month = DateTime(_month.year, _month.month + months);
        _selectedDay = null;
      });

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(webAllTransactionsProvider).valueOrNull ?? const [];
    final categories = ref.watch(webCategoriesByIdProvider);

    // Neto por día del mes visible (transferencias no cuentan al total).
    final netByDay = <int, int>{};
    for (final t in txns) {
      if (t.date.year != _month.year || t.date.month != _month.month) continue;
      final e = t.type == TransactionType.income
          ? t.amountCents
          : (t.type == TransactionType.expense ? -t.amountCents : 0);
      netByDay[t.date.day] = (netByDay[t.date.day] ?? 0) + e;
    }

    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday; // 1=Mon
    final leading = firstWeekday - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebCard(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _shift(-1)),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy', 'es').format(_month),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _shift(1)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final d in const ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
                    Expanded(
                      child: Center(
                        child: Text(d,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: Theme.of(context).colorScheme.outline)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.1,
                children: [
                  for (var i = 0; i < leading; i++) const SizedBox(),
                  for (var day = 1; day <= daysInMonth; day++)
                    _DayCell(
                      day: day,
                      net: netByDay[day],
                      selected: _selectedDay?.day == day,
                      onTap: () => setState(() =>
                          _selectedDay = DateTime(_month.year, _month.month, day)),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_selectedDay != null) ...[
          const SizedBox(height: 16),
          _dayDetail(context, txns, categories),
        ],
      ],
    );
  }

  Widget _dayDetail(BuildContext context, List<TransactionDto> txns,
      Map<int, CategoryDto> categories) {
    final day = _selectedDay!;
    final movements = txns
        .where((t) =>
            t.date.year == day.year &&
            t.date.month == day.month &&
            t.date.day == day.day)
        .toList()
      ..sort((a, b) => b.amountCents.compareTo(a.amountCents));
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(DateFormat('EEEE d MMMM', 'es').format(day),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Sin movimientos este día.'),
            )
          else
            for (final t in movements)
              _movementTile(context, t, categories),
        ],
      ),
    );
  }

  Widget _movementTile(
      BuildContext context, TransactionDto t, Map<int, CategoryDto> categories) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = t.type == TransactionType.income;
    final isTransfer = t.type == TransactionType.transfer;
    final cat = t.categoryId != null ? categories[t.categoryId] : null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: WebColorDot(
        size: 30,
        colorValue: cat?.colorValue ?? 0xFF9E9E9E,
        icon: isTransfer ? Icons.swap_horiz : webIconFor(cat?.iconName ?? 'category'),
      ),
      title: Text(t.concept.isEmpty ? (cat?.name ?? 'Movimiento') : t.concept),
      trailing: WebMoneyText(
        isIncome ? t.amountCents : (isTransfer ? 0 : -t.amountCents),
        signed: !isTransfer,
        color: isIncome
            ? Colors.green
            : (isTransfer ? scheme.outline : scheme.error),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.net,
    required this.selected,
    required this.onTap,
  });
  final int day;
  final int? net;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasData = net != null && net != 0;
    final color = net == null || net == 0
        ? scheme.outline
        : (net! > 0 ? Colors.green : scheme.error);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : (hasData ? color.withValues(alpha: 0.10) : Colors.transparent),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$day',
                    style: Theme.of(context).textTheme.bodyMedium),
                if (hasData)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: WebMoneyText(
                      net!,
                      signed: true,
                      color: color,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
