import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../data/models/enums.dart';
import '../../accounts/deposit_math.dart';
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

  // Campos de depósito (solo si _type == AccountType.deposit).
  late final TextEditingController _rate;
  int? _depositRateBps;
  DateTime? _depositStartDate;
  DateTime? _depositEndDate;
  DepositPayout _depositPayout = DepositPayout.atMaturity;
  bool _depositAutoRenew = false;

  // Banco asociado (depósitos/letras que no sean subcuenta) y nominal (letras).
  int? _bankAccountId;
  int _nominalCents = 0;

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
    _depositRateBps = e?.depositRateBps;
    _rate = TextEditingController(
        text: e?.depositRateBps == null
            ? ''
            : formatRateBps(e!.depositRateBps).replaceAll(' %', ''));
    _depositStartDate = e?.depositStartDate;
    _depositEndDate = e?.depositEndDate;
    _depositPayout = e?.depositPayout ?? DepositPayout.atMaturity;
    _depositAutoRenew = e?.depositAutoRenew ?? false;
    _bankAccountId = e?.bankAccountId;
    _nominalCents = e?.nominalCents ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _parseRate(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) {
      _depositRateBps = null;
      return;
    }
    final pct = double.tryParse(t);
    _depositRateBps = pct == null ? null : (pct * 100).round();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _depositStartDate : _depositEndDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 30),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _depositStartDate = picked;
      } else {
        _depositEndDate = picked;
      }
    });
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
    final isDeposit = _type == AccountType.deposit;
    final isBill = _type == AccountType.treasuryBill;
    final isSub = _parentId != null;
    if (isDeposit) _parseRate(_rate.text);
    final dto = AccountDto(
      name: name,
      type: _type,
      note: _note.text.trim(),
      initialBalanceCents: _initialCents,
      includeInTotal: _includeInTotal,
      archived: _archived,
      parentId: _parentId,
      // El banco solo se guarda si no es subcuenta y es depósito/letra.
      bankAccountId: (!isSub && (isDeposit || isBill)) ? _bankAccountId : null,
      colorValue: _color,
      iconName: _icon,
      sortOrder: widget.existing?.sortOrder ?? 0,
      depositRateBps: isDeposit ? _depositRateBps : null,
      depositStartDate: (isDeposit || isBill) ? _depositStartDate : null,
      depositEndDate: (isDeposit || isBill) ? _depositEndDate : null,
      depositPayout: isDeposit ? _depositPayout : DepositPayout.atMaturity,
      depositAutoRenew: isDeposit && _depositAutoRenew,
      nominalCents: isBill && _nominalCents != 0 ? _nominalCents : null,
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

  /// Campos del depósito (TAE, fechas, liquidación, renovación) + interés bruto
  /// estimado. Réplica web de los del editor móvil.
  List<Widget> _depositFields(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'es');
    _parseRate(_rate.text);
    final interest = estimatedGrossInterestCents(
      principalCents: _initialCents,
      rateBps: _depositRateBps,
      start: _depositStartDate,
      end: _depositEndDate,
    );
    final netInterest = estimatedNetInterestCents(
      principalCents: _initialCents,
      rateBps: _depositRateBps,
      start: _depositStartDate,
      end: _depositEndDate,
    );
    return [
      const SizedBox(height: 12),
      TextField(
        controller: _rate,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'TAE (%)',
          hintText: 'p. ej. 3,75',
        ),
        onChanged: (v) => setState(() => _parseRate(v)),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_available),
        title: const Text('Fecha de apertura'),
        subtitle: Text(_depositStartDate == null
            ? 'Sin definir'
            : df.format(_depositStartDate!)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: () => _pickDate(isStart: true),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_busy),
        title: const Text('Fecha de vencimiento'),
        subtitle: Text(_depositEndDate == null
            ? 'Sin definir'
            : df.format(_depositEndDate!)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: () => _pickDate(isStart: false),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<DepositPayout>(
        value: _depositPayout,
        decoration:
            const InputDecoration(labelText: 'Liquidación de intereses'),
        items: [
          for (final p in DepositPayout.values)
            DropdownMenuItem(value: p, child: Text(p.label)),
        ],
        onChanged: (v) => setState(() => _depositPayout = v ?? _depositPayout),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _depositAutoRenew,
        title: const Text('Renovación automática'),
        onChanged: (v) => setState(() => _depositAutoRenew = v),
      ),
      if (interest > 0)
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.savings_outlined),
                title: const Text('Interés bruto estimado'),
                trailing: Text(
                  Money(interest).format(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Interés neto estimado'),
                subtitle: const Text('Tras retención del 19 % de IRPF'),
                trailing: Text(
                  Money(netInterest).format(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// Campos de una Letra del Tesoro: importe nominal + ganancia bruta estimada.
  List<Widget> _treasuryFields(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'es');
    final gain = treasuryBillGainCents(
      nominalCents: _nominalCents,
      purchaseCents: _initialCents,
    );
    return [
      const SizedBox(height: 8),
      WebAmountField(
        label: 'Importe nominal (al vencimiento)',
        initialCents: _nominalCents == 0 ? null : _nominalCents,
        onChangedCents: (c) => setState(() => _nominalCents = c ?? 0),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_available),
        title: const Text('Fecha de compra'),
        subtitle: Text(_depositStartDate == null
            ? 'Sin definir'
            : df.format(_depositStartDate!)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: () => _pickDate(isStart: true),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_busy),
        title: const Text('Fecha de vencimiento'),
        subtitle: Text(_depositEndDate == null
            ? 'Sin definir'
            : df.format(_depositEndDate!)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: () => _pickDate(isStart: false),
      ),
      if (gain > 0)
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text('Ganancia estimada'),
            subtitle: const Text(
                'Nominal − precio de compra. Sin retención en origen (bruto)'),
            trailing: Text(
              Money(gain).format(),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
    ];
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
    final isDepositOrBill =
        _type == AccountType.deposit || _type == AccountType.treasuryBill;
    // Un depósito/letra no puede ser el banco de otro: se excluyen del selector.
    final bankExclude = {
      ...exclude,
      for (final a in accounts)
        if (a.type == AccountType.deposit ||
            a.type == AccountType.treasuryBill)
          a.id,
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
                  ButtonSegment(
                      value: AccountType.deposit, label: Text('Depósito')),
                  ButtonSegment(
                      value: AccountType.treasuryBill, label: Text('Letra')),
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
              if (isDepositOrBill && _parentId == null) ...[
                const SizedBox(height: 14),
                WebAccountPicker(
                  label: 'Banco donde está suscrito',
                  value: _bankAccountId,
                  includeNone: true,
                  noneLabel: 'Ninguno',
                  excludeIds: bankExclude,
                  onChanged: (v) => setState(() => _bankAccountId = v),
                ),
              ],
              const SizedBox(height: 14),
              WebAmountField(
                label: switch (_type) {
                  AccountType.deposit => 'Capital del depósito',
                  AccountType.treasuryBill => 'Precio de compra',
                  _ => 'Saldo inicial',
                },
                initialCents: _initialCents == 0 ? null : _initialCents,
                onChangedCents: (c) => setState(() => _initialCents = c ?? 0),
              ),
              if (_type == AccountType.deposit) ..._depositFields(context),
              if (_type == AccountType.treasuryBill)
                ..._treasuryFields(context),
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
