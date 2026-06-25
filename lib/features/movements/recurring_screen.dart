import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../core/router/app_router.dart';
import '../../data/models/enums.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../shared/widgets/async_value_view.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurrentes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.recurringEditor),
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: AsyncValueView(
        value: rules,
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Crea movimientos recurrentes como suscripciones o tu sueldo.\n'
                  'Se generarán automáticamente en sus fechas.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              final isExpense = r.type == TransactionType.expense;
              return ListTile(
                leading: CircleAvatar(
                  child: Icon(isExpense ? Icons.south : Icons.north),
                ),
                title: Text(r.name),
                subtitle: Text(
                  '${_frequencyLabel(r)} · Próx: '
                  '${DateFormat('d MMM yyyy', 'es').format(r.nextDate)}'
                  '${r.active ? '' : ' · Pausada'}',
                ),
                trailing: Text(
                  Money(r.amountCents).format(),
                  style: TextStyle(
                    color: isExpense
                        ? Theme.of(context).colorScheme.error
                        : Colors.green.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () =>
                    context.push(Routes.recurringEditor, extra: r.id),
              );
            },
          );
        },
      ),
    );
  }

  String _frequencyLabel(RecurringRule r) {
    final unit = switch (r.frequency) {
      RecurringFrequency.daily => 'día(s)',
      RecurringFrequency.weekly => 'semana(s)',
      RecurringFrequency.monthly => 'mes(es)',
      RecurringFrequency.yearly => 'año(s)',
    };
    return r.interval == 1 ? 'Cada $unit' : 'Cada ${r.interval} $unit';
  }
}
