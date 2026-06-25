import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../data/models/account.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/icon_color_picker.dart';

class AccountEditorScreen extends ConsumerStatefulWidget {
  const AccountEditorScreen({super.key, this.accountId});
  final int? accountId;

  @override
  ConsumerState<AccountEditorScreen> createState() =>
      _AccountEditorScreenState();
}

class _AccountEditorScreenState extends ConsumerState<AccountEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  AccountType _type = AccountType.bank;
  int _initialCents = 0;
  String _iconName = 'account_balance';
  int _colorValue = 0xFF1976D2;
  bool _includeInTotal = true;
  bool _loading = true;
  Account? _existing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.accountId != null) {
      final acc =
          await ref.read(accountRepositoryProvider).getById(widget.accountId!);
      if (acc != null) {
        _existing = acc;
        _nameController.text = acc.name;
        _type = acc.type;
        _initialCents = acc.initialBalanceCents;
        _iconName = acc.iconName;
        _colorValue = acc.colorValue;
        _includeInTotal = acc.includeInTotal;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final acc = _existing ?? Account();
    acc
      ..name = _nameController.text.trim()
      ..type = _type
      ..initialBalanceCents = _initialCents
      ..iconName = _iconName
      ..colorValue = _colorValue
      ..includeInTotal = _includeInTotal;
    await ref.read(accountRepositoryProvider).save(acc);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          'Se eliminarán también todos sus movimientos. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(accountRepositoryProvider).delete(_existing!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Nueva cuenta' : 'Editar cuenta'),
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
                      labelText: 'Nombre',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AccountType>(
                    value: _type,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(
                          value: AccountType.bank, child: Text('Banco')),
                      DropdownMenuItem(
                          value: AccountType.cash, child: Text('Efectivo')),
                      DropdownMenuItem(
                          value: AccountType.investment,
                          child: Text('Inversiones')),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    label: 'Saldo inicial',
                    initialCents: _initialCents == 0 ? null : _initialCents,
                    onChangedCents: (c) => _initialCents = c ?? 0,
                  ),
                  const SizedBox(height: 16),
                  IconColorPicker(
                    iconName: _iconName,
                    colorValue: _colorValue,
                    onIconChanged: (n) => setState(() => _iconName = n),
                    onColorChanged: (c) => setState(() => _colorValue = c),
                  ),
                  SwitchListTile(
                    value: _includeInTotal,
                    title: const Text('Incluir en balance total'),
                    onChanged: (v) => setState(() => _includeInTotal = v),
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
