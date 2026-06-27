import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/goal_repository.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/async_value_view.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Objetivos')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView(
        value: goals,
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Crea objetivos de ahorro y sigue tu progreso.'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final g = list[i];
              return Card(
                child: ListTile(
                  title: Text(g.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: g.progress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 4),
                      Text(
                          '${Money(g.currentCents).format()} / '
                          '${Money(g.targetCents).format()}'),
                      if (goalPlanLabel(g) != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            goalPlanLabel(g)!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onTap: () => _edit(context, ref, g),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Goal? goal) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GoalEditor(goal: goal),
    );
  }
}

/// Texto de planificación para mostrar bajo el progreso (lista y dashboard).
String? goalPlanLabel(Goal g) {
  if (g.remainingCents <= 0) return '¡Objetivo conseguido!';
  if (g.planMode == 'contribution') {
    final months = g.monthsToTarget;
    final date = g.projectedDate;
    if (months == null || date == null) return null;
    final when = DateFormat('MMM yyyy', 'es').format(date);
    return 'Lo alcanzas en ~$months ${months == 1 ? 'mes' : 'meses'} ($when)';
  } else {
    final monthly = g.requiredMonthlyCents;
    if (monthly == null) return null;
    return 'Necesitas ${Money(monthly).format()}/mes';
  }
}

class _GoalEditor extends ConsumerStatefulWidget {
  const _GoalEditor({this.goal});
  final Goal? goal;

  @override
  ConsumerState<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<_GoalEditor> {
  late final TextEditingController _nameController;
  int _targetCents = 0;
  int _currentCents = 0;
  int _monthlyCents = 0;
  String _planMode = 'contribution';
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _nameController = TextEditingController(text: g?.name ?? '');
    _targetCents = g?.targetCents ?? 0;
    _currentCents = g?.currentCents ?? 0;
    _monthlyCents = g?.monthlyContributionCents ?? 0;
    _planMode = g?.planMode ?? 'contribution';
    _deadline = g?.deadline;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Goal _draft() => Goal()
    ..name = 'draft'
    ..targetCents = _targetCents
    ..currentCents = _currentCents
    ..monthlyContributionCents = _monthlyCents
    ..deadline = _deadline
    ..planMode = _planMode;

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final goal = widget.goal ?? Goal();
    goal
      ..name = name
      ..targetCents = _targetCents
      ..currentCents = _currentCents
      ..monthlyContributionCents = _monthlyCents
      ..planMode = _planMode
      ..deadline = _planMode == 'deadline' ? _deadline : goal.deadline;
    await ref.read(goalRepositoryProvider).save(goal);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (widget.goal == null) return;
    await ref.read(goalRepositoryProvider).delete(widget.goal!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime(now.year, now.month + 6, now.day),
      firstDate: now,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  @override
  Widget build(BuildContext context) {
    final label = goalPlanLabel(_draft());
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.goal == null ? 'Nuevo objetivo' : 'Editar objetivo',
                    style: Theme.of(context).textTheme.titleLarge),
                if (widget.goal != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 16),
            AmountField(
              label: 'Cantidad objetivo',
              initialCents: _targetCents == 0 ? null : _targetCents,
              onChangedCents: (c) => setState(() => _targetCents = c ?? 0),
            ),
            const SizedBox(height: 16),
            AmountField(
              label: 'Ahorrado hasta ahora',
              initialCents: _currentCents == 0 ? null : _currentCents,
              onChangedCents: (c) => setState(() => _currentCents = c ?? 0),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'contribution', label: Text('Aporto al mes')),
                ButtonSegment(value: 'deadline', label: Text('Fecha límite')),
              ],
              selected: {_planMode},
              onSelectionChanged: (s) => setState(() => _planMode = s.first),
            ),
            const SizedBox(height: 16),
            if (_planMode == 'contribution')
              AmountField(
                label: 'Aporto al mes',
                initialCents: _monthlyCents == 0 ? null : _monthlyCents,
                onChangedCents: (c) => setState(() => _monthlyCents = c ?? 0),
              )
            else
              ListTile(
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                      color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.event),
                title: const Text('Fecha límite'),
                trailing: Text(_deadline == null
                    ? 'Elegir'
                    : DateFormat('d MMM yyyy', 'es').format(_deadline!)),
                onTap: _pickDeadline,
              ),
            if (label != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.insights,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
