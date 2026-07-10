import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/planning/goal_planning.dart';
import '../dialogs/web_goal_dialog.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_pickers.dart';
import '../widgets/web_ui.dart';

/// Objetivos: tarjetas de progreso + banco de trabajo de planificación
/// (simulador de aporte mensual → fecha estimada).
class WebGoalsPage extends ConsumerStatefulWidget {
  const WebGoalsPage({super.key});

  @override
  ConsumerState<WebGoalsPage> createState() => _WebGoalsPageState();
}

class _WebGoalsPageState extends ConsumerState<WebGoalsPage> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final goalsAsync = ref.watch(webGoalsProvider);

    return WebPage(
      title: 'Objetivos',
      actions: [
        IconButton(
          tooltip: 'Refrescar',
          icon: const Icon(Icons.refresh),
          onPressed: () => bumpWebRefresh(ref),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Nuevo'),
          onPressed: () =>
              showDialog(context: context, builder: (_) => const WebGoalDialog()),
        ),
      ],
      child: goalsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Error: $e'),
        data: (goals) {
          if (goals.isEmpty) {
            return WebEmptyState(
              icon: Icons.flag_outlined,
              title: 'Sin objetivos',
              message: 'Crea objetivos de ahorro y sigue tu progreso.',
              action: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nuevo objetivo'),
                onPressed: () => showDialog(
                    context: context, builder: (_) => const WebGoalDialog()),
              ),
            );
          }
          GoalDto? selected;
          for (final g in goals) {
            if (g.id == _selectedId) {
              selected = g;
              break;
            }
          }

          return LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final cardCols = constraints.maxWidth >= 720
                ? 2
                : 1;
            final grid = GridView.count(
              crossAxisCount: cardCols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 2.6,
              children: [
                for (final g in goals)
                  _GoalCard(
                    goal: g,
                    selected: g.id == _selectedId,
                    onTap: () => setState(() => _selectedId = g.id),
                    onEdit: () => showDialog(
                        context: context,
                        builder: (_) => WebGoalDialog(existing: g)),
                  ),
              ],
            );

            if (wide && selected != null) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: grid),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 360,
                    child: _Workbench(
                      key: ValueKey(selected.id),
                      goal: selected,
                      onClose: () => setState(() => _selectedId = null),
                    ),
                  ),
                ],
              );
            }
            return grid;
          });
        },
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });
  final GoalDto goal;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  WebColorDot(
                    colorValue: goal.colorValue,
                    icon: webIconFor(goal.iconName, fallback: Icons.flag),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(goal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text('${(goal.progress * 100).round()}%',
                      style: Theme.of(context).textTheme.labelLarge),
                  IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: onEdit),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  minHeight: 8,
                  color: Color(goal.colorValue),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  WebMoneyText(goal.currentCents,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(' / ', style: TextStyle(color: scheme.outline)),
                  WebMoneyText(goal.targetCents,
                      style: TextStyle(color: scheme.outline)),
                  const Spacer(),
                  if (goal.planLabel != null)
                    Flexible(
                      child: Text(goal.planLabel!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.primary, fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banco de trabajo: simulador de aporte mensual → fecha estimada de logro.
class _Workbench extends StatefulWidget {
  const _Workbench({super.key, required this.goal, required this.onClose});
  final GoalDto goal;
  final VoidCallback onClose;

  @override
  State<_Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<_Workbench> {
  late int _monthly;

  @override
  void initState() {
    super.initState();
    _monthly = widget.goal.monthlyContributionCents > 0
        ? widget.goal.monthlyContributionCents
        : (widget.goal.remainingCents / 12).round().clamp(1000, 1 << 31);
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final remaining = goal.remainingCents;
    final projected = goalProjectedDate(
      planMode: 'contribution',
      monthlyContributionCents: _monthly,
      remainingCents: remaining,
    );
    final months = goalMonthsToTarget(
      planMode: 'contribution',
      monthlyContributionCents: _monthly,
      remainingCents: remaining,
    );
    // Rango del slider: hasta 3× el aporte inicial o lo que falta en 3 meses.
    final maxMonthly = [
      _monthly * 3,
      (remaining / 3).round(),
      50000,
    ].reduce((a, b) => a > b ? a : b).toDouble();

    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Planificación',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close), onPressed: widget.onClose),
            ],
          ),
          const SizedBox(height: 8),
          Text(goal.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Faltan ${Money(remaining).format()}',
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const Divider(height: 28),
          Text('Simular aporte mensual',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(Money(_monthly).format(),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Slider(
            value: _monthly.toDouble().clamp(0, maxMonthly),
            min: 0,
            max: maxMonthly,
            divisions: 100,
            label: Money(_monthly).format(),
            onChanged: (v) => setState(() => _monthly = v.round()),
          ),
          const SizedBox(height: 8),
          _statRow(context, Icons.event_available, 'Fecha estimada',
              projected == null
                  ? '—'
                  : DateFormat('MMMM yyyy', 'es').format(projected)),
          _statRow(context, Icons.timelapse, 'Meses restantes',
              months == null ? '—' : '$months'),
          if (goal.deadline != null)
            _statRow(
                context,
                Icons.flag,
                'Fecha límite fijada',
                DateFormat('d MMM yyyy', 'es').format(goal.deadline!)),
          if (goal.planMode == 'deadline' && goal.requiredMonthlyCents != null)
            _statRow(context, Icons.savings, 'Aporte necesario/mes',
                Money(goal.requiredMonthlyCents!).format()),
        ],
      ),
    );
  }

  Widget _statRow(
      BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
