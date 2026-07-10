import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/enums.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_amount_field.dart';
import '../widgets/web_pickers.dart';

/// Alta/edición de una regla recurrente (frecuencia, cuenta/categoría, próxima
/// fecha, activa y avisos).
class WebRecurringDialog extends ConsumerStatefulWidget {
  const WebRecurringDialog({super.key, this.existing});
  final RecurringDto? existing;

  @override
  ConsumerState<WebRecurringDialog> createState() =>
      _WebRecurringDialogState();
}

class _WebRecurringDialogState extends ConsumerState<WebRecurringDialog> {
  late final TextEditingController _name;
  late final TextEditingController _concept;
  late final TextEditingController _interval;
  TransactionType _type = TransactionType.expense;
  int? _amountCents;
  RecurringFrequency _frequency = RecurringFrequency.monthly;
  DateTime _nextDate = DateTime.now();
  DateTime? _endDate;
  bool _active = true;
  int? _accountId;
  int? _categoryId;
  bool _notify = false;
  int _daysBefore = 1;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _concept = TextEditingController(text: e?.concept ?? '');
    _interval = TextEditingController(text: '${e?.interval ?? 1}');
    _type = e?.type ?? TransactionType.expense;
    _amountCents = e?.amountCents;
    _frequency = e?.frequency ?? RecurringFrequency.monthly;
    _nextDate = e?.nextDate ?? DateTime.now();
    _endDate = e?.endDate;
    _active = e?.active ?? true;
    _accountId = e?.accountId;
    _categoryId = e?.categoryId;
    _notify = e?.notifyEnabled ?? false;
    _daysBefore = e?.notifyDaysBefore ?? 1;
    _time = TimeOfDay(hour: e?.notifyHour ?? 9, minute: e?.notifyMinute ?? 0);
  }

  @override
  void dispose() {
    _name.dispose();
    _concept.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Pon un nombre');
      return;
    }
    if (_amountCents == null || _amountCents! <= 0) {
      setState(() => _error = 'Importe no válido');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Elige una cuenta');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final dto = RecurringDto(
      name: name,
      type: _type,
      amountCents: _amountCents!,
      concept: _concept.text.trim(),
      frequency: _frequency,
      interval: int.tryParse(_interval.text.trim()) ?? 1,
      nextDate: _nextDate,
      endDate: _endDate,
      active: _active,
      accountId: _accountId!,
      categoryId: _type == TransactionType.transfer ? null : _categoryId,
      notifyEnabled: _notify,
      notifyDaysBefore: _daysBefore,
      notifyHour: _time.hour,
      notifyMinute: _time.minute,
    );
    final client = ref.read(webClientProvider)!;
    try {
      if (widget.existing != null) {
        await client.updateRecurring(widget.existing!.id, dto);
      } else {
        await client.createRecurring(dto);
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
    final e = widget.existing;
    if (e == null) return;
    await ref.read(webClientProvider)!.deleteRecurring(e.id);
    bumpWebRefresh(ref);
    if (mounted) Navigator.pop(context);
  }

  String _freqLabel(RecurringFrequency f) => switch (f) {
        RecurringFrequency.daily => 'Días',
        RecurringFrequency.weekly => 'Semanas',
        RecurringFrequency.monthly => 'Meses',
        RecurringFrequency.yearly => 'Años',
      };

  @override
  Widget build(BuildContext context) {
    final kind = _type == TransactionType.income
        ? CategoryKind.income
        : CategoryKind.expense;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                      widget.existing == null
                          ? 'Nueva recurrente'
                          : 'Editar recurrente',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (widget.existing != null)
                    IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy ? null : _delete),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                      value: TransactionType.expense, label: Text('Gasto')),
                  ButtonSegment(
                      value: TransactionType.income, label: Text('Ingreso')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              WebAmountField(
                initialCents: _amountCents,
                onChangedCents: (c) => _amountCents = c,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _concept,
                decoration: const InputDecoration(labelText: 'Concepto'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Cada'),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _interval,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<RecurringFrequency>(
                      initialValue: _frequency,
                      decoration: const InputDecoration(isDense: true),
                      items: [
                        for (final f in RecurringFrequency.values)
                          DropdownMenuItem(value: f, child: Text(_freqLabel(f))),
                      ],
                      onChanged: (v) =>
                          setState(() => _frequency = v ?? _frequency),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              WebAccountPicker(
                value: _accountId,
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 12),
              WebCategoryPicker(
                value: _categoryId,
                kind: kind,
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Próxima fecha'),
                trailing: Text(DateFormat('d MMM yyyy', 'es').format(_nextDate)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _nextDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _nextDate = picked);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy),
                title: const Text('Fecha de fin (opcional)'),
                trailing: Text(_endDate == null
                    ? 'Sin fin'
                    : DateFormat('d MMM yyyy', 'es').format(_endDate!)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? _nextDate,
                    firstDate: _nextDate,
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _endDate = picked);
                },
              ),
              if (_endDate != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _endDate = null),
                    child: const Text('Quitar fecha de fin'),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Avisar antes del cargo'),
                value: _notify,
                onChanged: (v) => setState(() => _notify = v),
              ),
              if (_notify) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _daysBefore,
                        decoration:
                            const InputDecoration(labelText: 'Antelación'),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('El mismo día')),
                          DropdownMenuItem(value: 1, child: Text('1 día antes')),
                          DropdownMenuItem(value: 2, child: Text('2 días antes')),
                          DropdownMenuItem(value: 3, child: Text('3 días antes')),
                          DropdownMenuItem(value: 7, child: Text('1 semana antes')),
                        ],
                        onChanged: (v) => setState(() => _daysBefore = v ?? 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(_time.format(context)),
                      onPressed: () async {
                        final picked = await showTimePicker(
                            context: context, initialTime: _time);
                        if (picked != null) setState(() => _time = picked);
                      },
                    ),
                  ],
                ),
              ],
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
