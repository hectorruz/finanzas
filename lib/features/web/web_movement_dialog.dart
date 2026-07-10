import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../data/models/enums.dart';
import 'web_models.dart';
import 'web_providers.dart';
import 'widgets/web_amount_field.dart';
import 'widgets/web_pickers.dart';

/// Formulario editable de un movimiento (gasto/ingreso/transferencia). Se usa
/// tanto en el diálogo de alta como en el panel de detalle (edición en línea),
/// con selectores de cuenta/categoría en árbol, nota y fecha.
class WebMovementForm extends ConsumerStatefulWidget {
  const WebMovementForm({
    super.key,
    this.existing,
    this.onDone,
    this.showCancel = true,
  });

  final TransactionDto? existing;

  /// Se invoca tras guardar, borrar o cancelar.
  final VoidCallback? onDone;
  final bool showCancel;

  @override
  ConsumerState<WebMovementForm> createState() => _WebMovementFormState();
}

class _WebMovementFormState extends ConsumerState<WebMovementForm> {
  late TransactionType _type;
  int? _amountCents;
  late TextEditingController _concept;
  late TextEditingController _note;
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
    _amountCents = e?.amountCents;
    _concept = TextEditingController(text: e?.concept ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _date = e?.date ?? DateTime.now();
    _accountId = e?.accountId;
    _toAccountId = e?.toAccountId;
    _categoryId = e?.categoryId;
  }

  @override
  void dispose() {
    _concept.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = _amountCents;
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Importe no válido');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Elige una cuenta');
      return;
    }
    if (_type == TransactionType.transfer) {
      if (_toAccountId == null) {
        setState(() => _error = 'Elige la cuenta destino');
        return;
      }
      if (_toAccountId == _accountId) {
        setState(() => _error = 'Las cuentas deben ser distintas');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final dto = TransactionDto(
      type: _type,
      amountCents: cents,
      concept: _concept.text.trim(),
      note: _note.text.trim(),
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
      bumpWebRefresh(ref);
      widget.onDone?.call();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar movimiento'),
        content: const Text('¿Seguro que quieres borrarlo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(webClientProvider)!.deleteTransaction(id);
      bumpWebRefresh(ref);
      widget.onDone?.call();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTransfer = _type == TransactionType.transfer;
    final kind = _type == TransactionType.income
        ? CategoryKind.income
        : CategoryKind.expense;

    return Column(
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
        const SizedBox(height: 14),
        WebAmountField(
          initialCents: _amountCents,
          autofocus: widget.existing == null,
          onChangedCents: (c) => _amountCents = c,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _concept,
          decoration: const InputDecoration(labelText: 'Concepto'),
        ),
        const SizedBox(height: 12),
        WebAccountPicker(
          label: isTransfer ? 'Cuenta origen' : 'Cuenta',
          value: _accountId,
          onChanged: (v) => setState(() => _accountId = v),
        ),
        if (isTransfer) ...[
          const SizedBox(height: 12),
          WebAccountPicker(
            label: 'Cuenta destino',
            value: _toAccountId,
            excludeId: _accountId,
            onChanged: (v) => setState(() => _toAccountId = v),
          ),
        ] else ...[
          const SizedBox(height: 12),
          WebCategoryPicker(
            value: _categoryId,
            kind: kind,
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Nota (opcional)'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(DateFormat('EEEE d MMM yyyy', 'es').format(_date)),
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
        const SizedBox(height: 16),
        Row(
          children: [
            if (widget.existing?.id != null)
              IconButton(
                tooltip: 'Borrar',
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : _delete,
              ),
            const Spacer(),
            if (widget.showCancel)
              TextButton(
                onPressed: _busy ? null : widget.onDone,
                child: const Text('Cancelar'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Guardando…' : 'Guardar'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Diálogo modal de alta/edición que envuelve [WebMovementForm].
class WebMovementDialog extends StatelessWidget {
  const WebMovementDialog({super.key, this.existing});
  final TransactionDto? existing;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(existing == null ? 'Nuevo movimiento' : 'Editar movimiento',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              WebMovementForm(
                existing: existing,
                onDone: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formatea un importe con signo según el tipo.
String signedAmountLabel(TransactionDto t) {
  final base = Money(t.amountCents).format();
  switch (t.type) {
    case TransactionType.income:
      return '+$base';
    case TransactionType.expense:
      return '-$base';
    case TransactionType.transfer:
      return base;
  }
}
