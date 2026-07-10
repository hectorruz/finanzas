import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/enums.dart';
import '../analytics/recurring_timeline.dart';
import '../dialogs/web_recurring_dialog.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_pickers.dart';
import '../widgets/web_ui.dart';

/// Recurrentes: reglas de cargos/ingresos periódicos + timeline de próximos
/// movimientos (extra de escritorio).
class WebRecurringPage extends ConsumerWidget {
  const WebRecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(webRecurringProvider);

    return WebPage(
      title: 'Recurrentes',
      actions: [
        IconButton(
          tooltip: 'Refrescar',
          icon: const Icon(Icons.refresh),
          onPressed: () => bumpWebRefresh(ref),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Nueva'),
          onPressed: () => showDialog(
              context: context, builder: (_) => const WebRecurringDialog()),
        ),
      ],
      child: rulesAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Error: $e'),
        data: (rules) {
          if (rules.isEmpty) {
            return WebEmptyState(
              icon: Icons.autorenew,
              title: 'Sin recurrentes',
              message:
                  'Crea cargos o ingresos periódicos (alquiler, nómina, suscripciones…).',
              action: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nueva recurrente'),
                onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const WebRecurringDialog()),
              ),
            );
          }
          return LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final list = _RulesList(rules: rules);
            final timeline = _Timeline(rules: rules);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: list),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: timeline),
                ],
              );
            }
            return Column(children: [list, const SizedBox(height: 16), timeline]);
          });
        },
      ),
    );
  }
}

String frequencyLabel(RecurringDto r) {
  final n = r.interval;
  final one = n == 1;
  switch (r.frequency) {
    case RecurringFrequency.daily:
      return one ? 'Cada día' : 'Cada $n días';
    case RecurringFrequency.weekly:
      return one ? 'Cada semana' : 'Cada $n semanas';
    case RecurringFrequency.monthly:
      return one ? 'Cada mes' : 'Cada $n meses';
    case RecurringFrequency.yearly:
      return one ? 'Cada año' : 'Cada $n años';
  }
}

class _RulesList extends ConsumerWidget {
  const _RulesList({required this.rules});
  final List<RecurringDto> rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(webCategoriesByIdProvider);
    return WebCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final r in rules)
            _ruleTile(context, ref, r, categories),
        ],
      ),
    );
  }

  Widget _ruleTile(BuildContext context, WidgetRef ref, RecurringDto r,
      Map<int, CategoryDto> categories) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = r.type == TransactionType.income;
    final cat = r.categoryId != null ? categories[r.categoryId] : null;
    return ListTile(
      leading: WebColorDot(
        colorValue: cat?.colorValue ?? (isIncome ? 0xFF4CAF50 : 0xFFF44336),
        icon: webIconFor(cat?.iconName ?? 'autorenew',
            fallback: Icons.autorenew),
      ),
      title: Text(r.name,
          style: TextStyle(
              decoration: r.active ? null : TextDecoration.lineThrough)),
      subtitle: Text(
        '${frequencyLabel(r)} · próximo '
        '${DateFormat('d MMM', 'es').format(r.nextDate)}'
        '${r.notifyEnabled ? ' · 🔔' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebMoneyText(
            isIncome ? r.amountCents : -r.amountCents,
            signed: true,
            color: isIncome ? Colors.green : scheme.error,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Switch(
            value: r.active,
            onChanged: (v) async {
              await ref.read(webClientProvider)!.updateRecurring(
                    r.id,
                    RecurringDto(
                      name: r.name,
                      type: r.type,
                      amountCents: r.amountCents,
                      concept: r.concept,
                      frequency: r.frequency,
                      interval: r.interval,
                      nextDate: r.nextDate,
                      endDate: r.endDate,
                      active: v,
                      accountId: r.accountId,
                      categoryId: r.categoryId,
                      notifyEnabled: r.notifyEnabled,
                      notifyDaysBefore: r.notifyDaysBefore,
                      notifyHour: r.notifyHour,
                      notifyMinute: r.notifyMinute,
                    ),
                  );
              bumpWebRefresh(ref);
            },
          ),
        ],
      ),
      onTap: () => showDialog(
          context: context,
          builder: (_) => WebRecurringDialog(existing: r)),
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.rules});
  final List<RecurringDto> rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final to = now.add(const Duration(days: 60));
    final occ = upcomingTimeline(rules, from: now, to: to);
    final income = occ
        .where((o) => o.signedCents > 0)
        .fold<int>(0, (s, o) => s + o.signedCents);
    final expense = occ
        .where((o) => o.signedCents < 0)
        .fold<int>(0, (s, o) => s + o.signedCents);

    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Próximos 60 días',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _mini(context, 'Ingresos', income, Colors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _mini(
                    context, 'Gastos', expense, Theme.of(context).colorScheme.error),
              ),
            ],
          ),
          const Divider(height: 24),
          if (occ.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No hay cargos previstos en los próximos 60 días.'),
            )
          else
            for (final o in occ.take(40)) _occTile(context, o),
        ],
      ),
    );
  }

  Widget _mini(BuildContext context, String label, int cents, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        WebMoneyText(cents,
            signed: true,
            color: color,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }

  Widget _occTile(BuildContext context, RecurringOccurrence o) {
    final income = o.signedCents > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(DateFormat('d MMM', 'es').format(o.date),
                style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: Text(o.rule.name, overflow: TextOverflow.ellipsis),
          ),
          WebMoneyText(
            o.signedCents,
            signed: true,
            color: income ? Colors.green : Theme.of(context).colorScheme.error,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
