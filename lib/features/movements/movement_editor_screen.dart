import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/enums.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/entity_picker_field.dart';

/// Alta/edición de un movimiento (ingreso, gasto o transferencia).
class MovementEditorScreen extends ConsumerStatefulWidget {
  const MovementEditorScreen({
    super.key,
    this.transactionId,
    this.initialType,
  });

  final int? transactionId;
  final TransactionType? initialType;

  @override
  ConsumerState<MovementEditorScreen> createState() =>
      _MovementEditorScreenState();
}

class _MovementEditorScreenState extends ConsumerState<MovementEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _conceptController = TextEditingController();
  final _noteController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  int? _cents;
  DateTime _date = DateTime.now();
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  bool _loading = true;
  TransactionModel? _existing;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? TransactionType.expense;
    _load();
  }

  Future<void> _load() async {
    if (widget.transactionId != null) {
      final txn = await ref
          .read(transactionRepositoryProvider)
          .getById(widget.transactionId!);
      if (txn != null) {
        _existing = txn;
        _type = txn.type;
        _cents = txn.amountCents;
        _date = txn.date;
        _accountId = txn.accountId;
        _toAccountId = txn.toAccountId;
        _categoryId = txn.categoryId;
        _conceptController.text = txn.concept;
        _noteController.text = txn.note;
      }
    }
    // Cuenta por defecto: la primera disponible.
    final accounts = await ref.read(accountRepositoryProvider).all();
    _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _conceptController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) return;
    if (_type == TransactionType.transfer && _toAccountId == null) {
      _toast('Selecciona la cuenta destino');
      return;
    }

    final txn = _existing ?? TransactionModel();
    txn
      ..type = _type
      ..amountCents = _cents ?? 0
      ..concept = _conceptController.text.trim()
      ..note = _noteController.text.trim()
      ..date = _date
      ..accountId = _accountId!
      ..toAccountId = _type == TransactionType.transfer ? _toAccountId : null
      ..categoryId =
          _type == TransactionType.transfer ? null : _categoryId;

    await ref.read(transactionRepositoryProvider).save(txn);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    await ref.read(transactionRepositoryProvider).delete(_existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
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
        title: Text(_existing == null ? 'Nuevo movimiento' : 'Editar movimiento'),
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
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
                children: [
                  SegmentedButton<TransactionType>(
                    segments: const [
                      ButtonSegment(
                        value: TransactionType.expense,
                        label: Text('Gasto'),
                        icon: Icon(Icons.remove),
                      ),
                      ButtonSegment(
                        value: TransactionType.income,
                        label: Text('Ingreso'),
                        icon: Icon(Icons.add),
                      ),
                      ButtonSegment(
                        value: TransactionType.transfer,
                        label: Text('Transfer.'),
                        icon: Icon(Icons.swap_horiz),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      _categoryId = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    initialCents: _cents,
                    autofocus: _existing == null,
                    onChangedCents: (c) => _cents = c,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _conceptController,
                    decoration: const InputDecoration(
                      labelText: 'Concepto',
                      prefixIcon: Icon(Icons.notes),
                    ),
                  ),
                  const SizedBox(height: 16),
                  EntityPickerField(
                    items: PickerItem.fromAccounts(accounts),
                    value: _accountId,
                    onChanged: (v) => setState(() => _accountId = v),
                    labelText: _type == TransactionType.transfer
                        ? 'Cuenta origen'
                        : 'Cuenta',
                    sheetTitle: 'Selecciona cuenta',
                    prefixIcon: Icons.account_balance_wallet,
                    validator: (v) =>
                        v == null ? 'Selecciona una cuenta' : null,
                  ),
                  if (_type == TransactionType.transfer) ...[
                    const SizedBox(height: 16),
                    EntityPickerField(
                      items: PickerItem.fromAccounts(accounts),
                      value: _toAccountId,
                      onChanged: (v) => setState(() => _toAccountId = v),
                      labelText: 'Cuenta destino',
                      sheetTitle: 'Selecciona cuenta',
                      prefixIcon: Icons.account_balance_wallet,
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    EntityPickerField(
                      items: PickerItem.fromCategories(categories),
                      value: _categoryId,
                      onChanged: (v) => setState(() => _categoryId = v),
                      labelText: 'Categoría',
                      sheetTitle: 'Selecciona categoría',
                      prefixIcon: Icons.category,
                      allowNone: true,
                    ),
                  ],
                  const SizedBox(height: 16),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Fecha'),
                    trailing: Text(
                        DateFormat('d MMM yyyy', 'es').format(_date)),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      prefixIcon: Icon(Icons.sticky_note_2_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }
}
