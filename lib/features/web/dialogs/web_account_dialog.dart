import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/enums.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_amount_field.dart';
import '../widgets/web_icon_color_picker.dart';
import '../widgets/web_pickers.dart';

/// Alta/edición de una cuenta (con subcuentas, tipo, archivar, incluir en total).
class WebAccountDialog extends ConsumerStatefulWidget {
  const WebAccountDialog({super.key, this.existing, this.parentId});
  final AccountDto? existing;

  /// Preselecciona una cuenta padre (al crear una subcuenta desde el árbol).
  final int? parentId;

  @override
  ConsumerState<WebAccountDialog> createState() => _WebAccountDialogState();
}

class _WebAccountDialogState extends ConsumerState<WebAccountDialog> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late AccountType _type;
  int? _parentId;
  int _initialCents = 0;
  bool _includeInTotal = true;
  bool _archived = false;
  late int _color;
  late String _icon;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? AccountType.bank;
    _parentId = e?.parentId ?? widget.parentId;
    _initialCents = e?.initialBalanceCents ?? 0;
    _includeInTotal = e?.includeInTotal ?? true;
    _archived = e?.archived ?? false;
    _color = e?.colorValue ?? 0xFF2196F3;
    _icon = e?.iconName ?? 'account_balance';
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

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
    final dto = AccountDto(
      name: name,
      type: _type,
      note: _note.text.trim(),
      initialBalanceCents: _initialCents,
      includeInTotal: _includeInTotal,
      archived: _archived,
      parentId: _parentId,
      colorValue: _color,
      iconName: _icon,
      sortOrder: widget.existing?.sortOrder ?? 0,
    );
    final client = ref.read(webClientProvider)!;
    try {
      if (widget.existing != null) {
        await client.updateAccount(widget.existing!.id, dto);
      } else {
        await client.createAccount(dto);
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar cuenta'),
        content: Text(
            '¿Borrar "${e.name}"? Sus subcuentas y movimientos también se '
            'borrarán.'),
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
    await ref.read(webClientProvider)!.deleteAccount(e.id);
    bumpWebRefresh(ref);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(webAccountsProvider).valueOrNull ?? const [];
    final exclude = widget.existing == null
        ? <int>{}
        : {
            widget.existing!.id,
            ...webDescendantIds(widget.existing!.id, accounts),
          };

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(widget.existing == null ? 'Nueva cuenta' : 'Editar cuenta',
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
              SegmentedButton<AccountType>(
                segments: const [
                  ButtonSegment(value: AccountType.bank, label: Text('Banco')),
                  ButtonSegment(value: AccountType.cash, label: Text('Efectivo')),
                  ButtonSegment(
                      value: AccountType.investment, label: Text('Inversión')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 14),
              WebAccountPicker(
                label: 'Cuenta padre (opcional)',
                value: _parentId,
                includeNone: true,
                noneLabel: 'Ninguna (cuenta principal)',
                excludeIds: exclude,
                onChanged: (v) => setState(() => _parentId = v),
              ),
              const SizedBox(height: 14),
              WebAmountField(
                label: 'Saldo inicial',
                initialCents: _initialCents == 0 ? null : _initialCents,
                onChangedCents: (c) => _initialCents = c ?? 0,
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Incluir en el balance total'),
                value: _includeInTotal,
                onChanged: (v) => setState(() => _includeInTotal = v),
              ),
              if (widget.existing != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Archivada'),
                  value: _archived,
                  onChanged: (v) => setState(() => _archived = v),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
              ),
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
