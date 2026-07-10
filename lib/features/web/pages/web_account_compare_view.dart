import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/enums.dart';
import '../web_providers.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_ui.dart';

/// Comparativa de cuentas lado a lado dentro de un rango: ingresos, gastos, neto
/// y nº de movimientos por cuenta (las transferencias cuentan como entrada/salida
/// de la cuenta implicada). Extra de escritorio.
class WebAccountCompareView extends ConsumerWidget {
  const WebAccountCompareView({super.key, required this.from, required this.to});
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(webAccountsProvider).valueOrNull ?? const [];
    final txns = ref.watch(webAllTransactionsProvider).valueOrNull ?? const [];

    final income = <int, int>{};
    final expense = <int, int>{};
    final count = <int, int>{};
    for (final t in txns) {
      if (t.date.isBefore(from) || t.date.isAfter(to)) continue;
      switch (t.type) {
        case TransactionType.income:
          income[t.accountId] = (income[t.accountId] ?? 0) + t.amountCents;
          count[t.accountId] = (count[t.accountId] ?? 0) + 1;
        case TransactionType.expense:
          expense[t.accountId] = (expense[t.accountId] ?? 0) + t.amountCents;
          count[t.accountId] = (count[t.accountId] ?? 0) + 1;
        case TransactionType.transfer:
          expense[t.accountId] = (expense[t.accountId] ?? 0) + t.amountCents;
          count[t.accountId] = (count[t.accountId] ?? 0) + 1;
          if (t.toAccountId != null) {
            income[t.toAccountId!] =
                (income[t.toAccountId!] ?? 0) + t.amountCents;
            count[t.toAccountId!] = (count[t.toAccountId!] ?? 0) + 1;
          }
      }
    }

    final rows = accounts.where((a) => !a.archived).toList()
      ..sort((a, b) {
        final na = (income[a.id] ?? 0) - (expense[a.id] ?? 0);
        final nb = (income[b.id] ?? 0) - (expense[b.id] ?? 0);
        return nb.compareTo(na);
      });

    if (rows.isEmpty) {
      return const WebCard(
        child: WebEmptyState(
          icon: Icons.account_balance_outlined,
          title: 'Sin cuentas que comparar',
        ),
      );
    }

    final maxAbsNet = rows.fold<int>(1, (m, a) {
      final net = ((income[a.id] ?? 0) - (expense[a.id] ?? 0)).abs();
      return net > m ? net : m;
    });

    return WebCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minWidth: MediaQuery.of(context).size.width - 340),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Cuenta')),
              DataColumn(label: Text('Ingresos'), numeric: true),
              DataColumn(label: Text('Gastos'), numeric: true),
              DataColumn(label: Text('Neto'), numeric: true),
              DataColumn(label: Text('Nº'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final a in rows)
                () {
                  final inc = income[a.id] ?? 0;
                  final exp = expense[a.id] ?? 0;
                  final net = inc - exp;
                  return DataRow(cells: [
                    DataCell(Text(a.name)),
                    DataCell(WebMoneyText(inc,
                        color: Colors.green,
                        style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(WebMoneyText(exp,
                        color: Theme.of(context).colorScheme.error,
                        style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(WebMoneyText(net,
                        signed: true,
                        color: net >= 0
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text('${count[a.id] ?? 0}')),
                    DataCell(_NetBar(net: net, maxAbs: maxAbsNet)),
                  ]);
                }(),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetBar extends StatelessWidget {
  const _NetBar({required this.net, required this.maxAbs});
  final int net;
  final int maxAbs;

  @override
  Widget build(BuildContext context) {
    final frac = (net.abs() / maxAbs).clamp(0.0, 1.0);
    final color =
        net >= 0 ? Colors.green : Theme.of(context).colorScheme.error;
    return SizedBox(
      width: 90,
      child: Align(
        alignment: net >= 0 ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          height: 8,
          width: 90 * frac,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
