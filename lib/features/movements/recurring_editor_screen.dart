import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../data/models/enums.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/entity_picker_field.dart';

class RecurringEditorScreen extends ConsumerStatefulWidget {
  const RecurringEditorScreen({super.key, this.ruleId});
  final int? ruleId;

  @override
  ConsumerState<RecurringEditorScreen> createState() =>
      _RecurringEditorScreenState();
}

class _RecurringEditorScreenState
    extends ConsumerState<RecurringEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  RecurringFrequency _frequency = RecurringFrequency.monthly;
  int _interval = 1;
  int? _cents;
  DateTime _nextDate = DateTime.now();
  DateTime? _endDate;
  int? _accountId;
  int? _categoryId;
  bool _active = true;
  bool _loading = true;
  RecurringRule? _existing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.ruleId != null) {
      final isar = ref.read(isarProvider);
      final rule = await isar.recurringRules.get(widget.ruleId!);
      if (rule != null) {
        _existing = rule;
        _type = rule.type;
        _frequency = rule.frequency;
        _interval = rule.interval;
        _cents = rule.amountCents;
        _nextDate = rule.nextDate;
        _endDate = rule.endDate;
        _accountId = rule.accountId;
        _categoryId = rule.categoryId;
        _active = rule.active;
        _nameController.text = rule.name;
      }
    }
    final accounts = await ref.read(accountRepositoryProvider).all();
    _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _accountId == null) return;
    final rule = _existing ?? RecurringRule();
    rule
      ..name = _nameController.text.trim()
      ..type = _type
      ..amountCents = _cents ?? 0
      ..concept = _nameController.text.trim()
      ..frequency = _frequency
      ..interval = _interval
      ..nextDate = _nextDate
      ..endDate = _endDate
      ..accountId = _accountId!
      ..categoryId = _type == TransactionType.transfer ? null : _categoryId
      ..active = _active;
    await ref.read(recurringRepositoryProvider).save(rule);
    // Generar de inmediato cualquier ocurrencia ya vencida.
    await ref.read(recurringRepositoryProvider).materializeDue();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    await ref.read(recurringRepositoryProvider).delete(_existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const [])
        .where((c) =>
            c.kind ==
            (_type == TransactionType.income
                ? CategoryKind.income
                : CategoryKind.expense))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Nueva recurrente' : 'Editar recurrente'),
        actions: [
          if (_existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre (p. ej. Netflix, Nómina)',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<TransactionType>(
                    segments: const [
                      ButtonSegment(
                          value: TransactionType.expense,
                          label: Text('Gasto')),
                      ButtonSegment(
                          value: TransactionType.income,
                          label: Text('Ingreso')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) =>
                        setState(() => _type = s.first),
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    initialCents: _cents,
                    onChangedCents: (c) => _cents = c,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<RecurringFrequency>(
                          value: _frequency,
                          decoration:
                              const InputDecoration(labelText: 'Frecuencia'),
                          items: const [
                            DropdownMenuItem(
                                value: RecurringFrequency.daily,
                                child: Text('Diaria')),
                            DropdownMenuItem(
                                value: RecurringFrequency.weekly,
                                child: Text('Semanal')),
                            DropdownMenuItem(
                                value: RecurringFrequency.monthly,
                                child: Text('Mensual')),
                            DropdownMenuItem(
                                value: RecurringFrequency.yearly,
                                child: Text('Anual')),
                          ],
                          onChanged: (v) => setState(
                              () => _frequency = v ?? _frequency),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          initialValue: '$_interval',
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Cada'),
                          onChanged: (v) =>
                              _interval = int.tryParse(v) ?? 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_type != TransactionType.transfer) ...[
                    EntityPickerField(
                      items: PickerItem.fromCategories(categories),
                      value: _categoryId,
                      onChanged: (v) => setState(() => _categoryId = v),
                      labelText: 'Categoría',
                      sheetTitle: 'Selecciona categoría',
                      prefixIcon: Icons.category,
                      allowNone: true,
                    ),
                    const SizedBox(height: 16),
                  ],
                  EntityPickerField(
                    items: PickerItem.fromAccounts(accounts),
                    value: _accountId,
                    onChanged: (v) => setState(() => _accountId = v),
                    labelText: 'Cuenta',
                    sheetTitle: 'Selecciona cuenta',
                    prefixIcon: Icons.account_balance_wallet,
                    validator: (v) => v == null ? 'Selecciona una cuenta' : null,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.event_repeat),
                    title: const Text('Próxima fecha'),
                    trailing: Text(
                        DateFormat('d MMM yyyy', 'es').format(_nextDate)),
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
                  SwitchListTile(
                    value: _active,
                    title: const Text('Activa'),
                    onChanged: (v) => setState(() => _active = v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Guardar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

