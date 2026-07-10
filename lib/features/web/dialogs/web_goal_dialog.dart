import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_amount_field.dart';
import '../widgets/web_icon_color_picker.dart';

/// Alta/edición de un objetivo de ahorro (modo aporte mensual o fecha límite).
class WebGoalDialog extends ConsumerStatefulWidget {
  const WebGoalDialog({super.key, this.existing});
  final GoalDto? existing;

  @override
  ConsumerState<WebGoalDialog> createState() => _WebGoalDialogState();
}

class _WebGoalDialogState extends ConsumerState<WebGoalDialog> {
  late final TextEditingController _name;
  int _targetCents = 0;
  int _currentCents = 0;
  int _monthlyCents = 0;
  String _planMode = 'contribution';
  DateTime? _deadline;
  late int _color;
  late String _icon;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _name = TextEditingController(text: g?.name ?? '');
    _targetCents = g?.targetCents ?? 0;
    _currentCents = g?.currentCents ?? 0;
    _monthlyCents = g?.monthlyContributionCents ?? 0;
    _planMode = g?.planMode ?? 'contribution';
    _deadline = g?.deadline;
    _color = g?.colorValue ?? 0xFF4CAF50;
    _icon = g?.iconName ?? 'flag';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  GoalDto _draft() => GoalDto(
        name: 'draft',
        targetCents: _targetCents,
        currentCents: _currentCents,
        monthlyContributionCents: _monthlyCents,
        planMode: _planMode,
        deadline: _deadline,
      );

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Pon un nombre');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final dto = GoalDto(
      name: name,
      targetCents: _targetCents,
      currentCents: _currentCents,
      monthlyContributionCents: _monthlyCents,
      planMode: _planMode,
      deadline: _planMode == 'deadline' ? _deadline : widget.existing?.deadline,
      colorValue: _color,
      iconName: _icon,
      sortOrder: widget.existing?.sortOrder ?? 0,
    );
    final client = ref.read(webClientProvider)!;
    try {
      if (widget.existing != null) {
        await client.updateGoal(widget.existing!.id, dto);
      } else {
        await client.createGoal(dto);
      }
      bumpWebRefresh(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _delete() async {
    final g = widget.existing;
    if (g == null) return;
    await ref.read(webClientProvider)!.deleteGoal(g.id);
    bumpWebRefresh(ref);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final label = _draft().planLabel;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                      widget.existing == null
                          ? 'Nuevo objetivo'
                          : 'Editar objetivo',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (widget.existing != null)
                    IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy ? null : _delete),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 14),
              WebAmountField(
                label: 'Cantidad objetivo',
                initialCents: _targetCents == 0 ? null : _targetCents,
                onChangedCents: (c) => setState(() => _targetCents = c ?? 0),
              ),
              const SizedBox(height: 14),
              WebAmountField(
                label: 'Ahorrado hasta ahora',
                initialCents: _currentCents == 0 ? null : _currentCents,
                onChangedCents: (c) => setState(() => _currentCents = c ?? 0),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'contribution', label: Text('Aporto al mes')),
                  ButtonSegment(value: 'deadline', label: Text('Fecha límite')),
                ],
                selected: {_planMode},
                onSelectionChanged: (s) => setState(() => _planMode = s.first),
              ),
              const SizedBox(height: 14),
              if (_planMode == 'contribution')
                WebAmountField(
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
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          _deadline ?? DateTime(now.year, now.month + 6, now.day),
                      firstDate: now,
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _deadline = picked);
                  },
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
              WebIconColorPicker(
                colorValue: _color,
                iconName: _icon,
                onColor: (c) => setState(() => _color = c),
                onIcon: (i) => setState(() => _icon = i),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? 'Guardando…' : 'Guardar'),
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
