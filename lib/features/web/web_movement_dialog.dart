import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../data/models/enums.dart';
import 'web_models.dart';
import 'web_providers.dart';

/// Diálogo de alta/edición de un movimiento desde la webapp.
class WebMovementDialog extends ConsumerStatefulWidget {
  const WebMovementDialog({super.key, this.existing});
  final TransactionDto? existing;

  @override
  ConsumerState<WebMovementDialog> createState() => _WebMovementDialogState();
}

class _WebMovementDialogState extends ConsumerState<WebMovementDialog> {
  late TransactionType _type;
  late TextEditingController _amount;
  late TextEditingController _concept;
  late DateTime _date;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? TransactionType.expense;
    _amount = TextEditingController(
        text: e == null ? '' : (e.amountCents / 100).toStringAsFixed(2));
    _concept = TextEditingController(text: e?.concept ?? '');
    _date = e?.date ?? DateTime.now();
    _accountId = e?.accountId;
    _toAccountId = e?.toAccountId;
    _categoryId = e?.categoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = Money.parseToCents(_amount.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Importe no válido');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Elige una cuenta');
      return;
    }
    if (_type == TransactionType.transfer && _toAccountId == null) {
      setState(() => _error = 'Elige la cuenta destino');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final dto = TransactionDto(
      type: _type,
      amountCents: cents,
      concept: _concept.text.trim(),
      date: _date,
      accountId: _accountId!,
      toAccountId: _type == TransactionType.transfer ? _toAccountId : null,
      categoryId: _type == TransactionType.transfer ? null : _categoryId,
    );
    final client = ref.read(webClientProvider);
    try {
      if (widget.existing?.id != null) {
        await client!.updateTransaction(widget.existing!.id!, dto);
      } else {
        await client!.createTransaction(dto);
      }
      ref.read(webRefreshProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(webAccountsProvider).valueOrNull ?? const [];
    final categories = (ref.watch(webCategoriesProvider).valueOrNull ?? const [])
        .where((c) => c.kind.name == _type.name || _type == TransactionType.transfer)
        .toList();

    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo movimiento' : 'Editar movimiento'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(value: TransactionType.expense, label: Text('Gasto')),
                  ButtonSegment(value: TransactionType.income, label: Text('Ingreso')),
                  ButtonSegment(
                      value: TransactionType.transfer, label: Text('Transf.')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Importe (€)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _concept,
                decoration: const InputDecoration(
                    labelText: 'Concepto', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              _accountDropdown('Cuenta', _accountId, accounts,
                  (v) => setState(() => _accountId = v)),
              if (_type == TransactionType.transfer) ...[
                const SizedBox(height: 12),
                _accountDropdown('Cuenta destino', _toAccountId, accounts,
                    (v) => setState(() => _toAccountId = v)),
              ] else ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Categoría', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sin categoría')),
                    for (final c in categories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat('dd/MM/yyyy').format(_date)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _accountDropdown(String label, int? value, List<AccountDto> accounts,
      ValueChanged<int?> onChanged) {
    return DropdownButtonFormField<int?>(
      initialValue: value,
      isExpanded: true,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final a in accounts)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
      onChanged: onChanged,
    );
  }
}
