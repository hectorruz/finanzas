import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.goal?.name ?? '');
    _targetCents = widget.goal?.targetCents ?? 0;
    _currentCents = widget.goal?.currentCents ?? 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final goal = widget.goal ?? Goal();
    goal
      ..name = name
      ..targetCents = _targetCents
      ..currentCents = _currentCents;
    await ref.read(goalRepositoryProvider).save(goal);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (widget.goal == null) return;
    await ref.read(goalRepositoryProvider).delete(widget.goal!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
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
            onChangedCents: (c) => _targetCents = c ?? 0,
          ),
          const SizedBox(height: 16),
          AmountField(
            label: 'Ahorrado hasta ahora',
            initialCents: _currentCents == 0 ? null : _currentCents,
            onChangedCents: (c) => _currentCents = c ?? 0,
          ),
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
    );
  }
}
