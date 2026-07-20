import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/icons/app_icons.dart';
import '../../core/money/money.dart';
import '../../data/models/account.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/icon_color_picker.dart';
import 'deposit_math.dart';

/// Argumentos del editor de cuentas pasados por `extra`. Permite distinguir
/// entre editar una cuenta existente y crear una subcuenta de otra.
class AccountEditorArgs {
  const AccountEditorArgs({this.accountId, this.parentId});
  final int? accountId;
  final int? parentId;
}

class AccountEditorScreen extends ConsumerStatefulWidget {
  const AccountEditorScreen({super.key, this.accountId, this.parentId});
  final int? accountId;

  /// Cuenta padre cuando se está creando una subcuenta.
  final int? parentId;

  @override
  ConsumerState<AccountEditorScreen> createState() =>
      _AccountEditorScreenState();
}

class _AccountEditorScreenState extends ConsumerState<AccountEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  AccountType _type = AccountType.bank;
  int _initialCents = 0;
  String _iconName = 'account_balance';
  int _colorValue = 0xFF1976D2;
  bool _includeInTotal = true;
  bool _loading = true;
  Account? _existing;

  // Campos de depósito (solo si _type == AccountType.deposit).
  final _rateController = TextEditingController();
  int? _depositRateBps;
  DateTime? _depositStartDate;
  DateTime? _depositEndDate;
  DepositPayout _depositPayout = DepositPayout.atMaturity;
  bool _depositAutoRenew = false;

  // Banco asociado (depósitos y letras que no sean subcuenta) y nominal (letras).
  int? _bankAccountId;
  int _nominalCents = 0;

  /// ¿Se está editando/creando una subcuenta? Si lo es, el banco es su padre y no
  /// se muestra el selector de banco.
  bool get _isSubaccount => (_existing?.parentId ?? widget.parentId) != null;

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
        _noteController.text = acc.note;
        _depositRateBps = acc.depositRateBps;
        _rateController.text =
            acc.depositRateBps == null ? '' : formatRateBps(acc.depositRateBps).replaceAll(' %', '');
        _depositStartDate = acc.depositStartDate;
        _depositEndDate = acc.depositEndDate;
        _depositPayout = acc.depositPayout;
        _depositAutoRenew = acc.depositAutoRenew;
        _bankAccountId = acc.bankAccountId;
        _nominalCents = acc.nominalCents ?? 0;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  /// Parsea el texto de la TAE ("3,75") a puntos básicos (375). Vacío → null.
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
    final initial =
        (isStart ? _depositStartDate : _depositEndDate) ?? now;
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
    if (!_formKey.currentState!.validate()) return;
    final acc = _existing ?? Account();
    acc
      ..name = _nameController.text.trim()
      ..type = _type
      ..initialBalanceCents = _initialCents
      ..iconName = _iconName
      ..colorValue = _colorValue
      ..includeInTotal = _includeInTotal
      ..note = _noteController.text.trim()
      ..parentId = _existing?.parentId ?? widget.parentId
      // El banco elegido a mano se guarda para depósitos/letras (también si es
      // subcuenta: no tiene por qué ser el padre). En el resto de tipos se limpia.
      ..bankAccountId = (_type == AccountType.deposit ||
              _type == AccountType.treasuryBill)
          ? _bankAccountId
          : null;
    if (_type == AccountType.deposit) {
      _parseRate(_rateController.text);
      acc
        ..depositRateBps = _depositRateBps
        ..depositStartDate = _depositStartDate
        ..depositEndDate = _depositEndDate
        ..depositPayout = _depositPayout
        ..depositAutoRenew = _depositAutoRenew
        ..nominalCents = null;
    } else if (_type == AccountType.treasuryBill) {
      // Letra del Tesoro: reutiliza fechas y precio de compra; sin TAE/liquidación.
      acc
        ..depositRateBps = null
        ..depositStartDate = _depositStartDate
        ..depositEndDate = _depositEndDate
        ..depositPayout = DepositPayout.atMaturity
        ..depositAutoRenew = false
        ..nominalCents = _nominalCents == 0 ? null : _nominalCents;
    } else {
      // Al dejar de ser depósito/letra, limpiamos sus campos para no arrastrar
      // datos obsoletos que confundirían en el detalle o en la sincronización.
      acc
        ..depositRateBps = null
        ..depositStartDate = null
        ..depositEndDate = null
        ..depositPayout = DepositPayout.atMaturity
        ..depositAutoRenew = false
        ..nominalCents = null;
    }
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

  /// Campos específicos del depósito (TAE, fechas, liquidación, renovación) más
  /// el interés bruto estimado. Se muestran solo si el tipo es depósito.
  List<Widget> _depositFields() {
    _parseRate(_rateController.text);
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
      const SizedBox(height: 16),
      TextFormField(
        controller: _rateController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'TAE (%)',
          hintText: 'p. ej. 3,75',
          prefixIcon: Icon(Icons.percent),
        ),
        onChanged: (v) => setState(() => _parseRate(v)),
      ),
      const SizedBox(height: 8),
      ..._datesFields(
        startLabel: 'Fecha de apertura',
        endLabel: 'Fecha de vencimiento',
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<DepositPayout>(
        value: _depositPayout,
        decoration: const InputDecoration(labelText: 'Liquidación de intereses'),
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
        subtitle: const Text('Se renueva al vencer'),
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
                subtitle:
                    const Text('Interés simple sobre el capital y el plazo'),
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

  /// Campos específicos de una Letra del Tesoro: importe nominal + ganancia
  /// bruta estimada (las fechas de compra/vencimiento se muestran en el bloque
  /// común, ver [_datesFields]).
  List<Widget> _treasuryFields() {
    final gain = treasuryBillGainCents(
      nominalCents: _nominalCents,
      purchaseCents: _initialCents,
    );
    return [
      const SizedBox(height: 16),
      AmountField(
        label: 'Importe nominal (al vencimiento)',
        initialCents: _nominalCents == 0 ? null : _nominalCents,
        onChangedCents: (c) => setState(() => _nominalCents = c ?? 0),
        allowZero: true,
      ),
      const SizedBox(height: 8),
      ..._datesFields(
        startLabel: 'Fecha de compra',
        endLabel: 'Fecha de vencimiento',
      ),
      if (gain > 0)
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text('Ganancia estimada'),
            subtitle: const Text(
                'Nominal − precio de compra. Las Letras del Tesoro no tienen '
                'retención en origen (rendimiento bruto)'),
            trailing: Text(
              Money(gain).format(),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
    ];
  }

  /// Los dos date-tiles (compra/apertura y vencimiento), compartidos por
  /// depósitos y letras.
  List<Widget> _datesFields({
    required String startLabel,
    required String endLabel,
  }) {
    final df = DateFormat('d MMM yyyy', 'es');
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_available),
        title: Text(startLabel),
        subtitle: Text(_depositStartDate == null
            ? 'Sin definir'
            : df.format(_depositStartDate!)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: () => _pickDate(isStart: true),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_busy),
        title: Text(endLabel),
        subtitle: Text(_depositEndDate == null
            ? 'Sin definir'
            : df.format(_depositEndDate!)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: () => _pickDate(isStart: false),
      ),
    ];
  }

  /// Selector del banco donde está suscrito el depósito/letra. Se puede elegir
  /// cualquier cuenta banco/efectivo/inversión, también cuando es subcuenta (no
  /// tiene por qué ir a la principal). Si es subcuenta, la opción "sin elegir"
  /// recae en su cuenta padre (comportamiento por defecto).
  Widget _bankAssociation(List<Account> accounts) {
    final parentId = _existing?.parentId ?? widget.parentId;
    final parent = accounts.where((a) => a.id == parentId).firstOrNull;
    final candidates = accounts
        .where((a) =>
            a.id != _existing?.id &&
            a.type != AccountType.deposit &&
            a.type != AccountType.treasuryBill)
        .toList();
    final noneLabel = _isSubaccount
        ? 'Su cuenta padre${parent == null ? '' : ' (${parent.name})'}'
        : 'Ninguno';
    return DropdownButtonFormField<int?>(
      value: candidates.any((a) => a.id == _bankAccountId)
          ? _bankAccountId
          : null,
      decoration: const InputDecoration(
        labelText: 'Banco donde está suscrito',
        prefixIcon: Icon(Icons.account_balance_outlined),
      ),
      items: [
        DropdownMenuItem(value: null, child: Text(noneLabel)),
        for (final a in candidates)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
      onChanged: (v) => setState(() => _bankAccountId = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final isDepositOrBill =
        _type == AccountType.deposit || _type == AccountType.treasuryBill;
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null
            ? (widget.parentId != null ? 'Nueva subcuenta' : 'Nueva cuenta')
            : 'Editar cuenta'),
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
                      DropdownMenuItem(
                          value: AccountType.deposit, child: Text('Depósito')),
                      DropdownMenuItem(
                          value: AccountType.treasuryBill,
                          child: Text('Letra del Tesoro')),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    label: switch (_type) {
                      AccountType.deposit => 'Capital del depósito',
                      AccountType.treasuryBill => 'Precio de compra',
                      _ => 'Saldo inicial',
                    },
                    initialCents: _initialCents == 0 ? null : _initialCents,
                    onChangedCents: (c) =>
                        setState(() => _initialCents = c ?? 0),
                    allowZero: true,
                  ),
                  if (isDepositOrBill) ...[
                    const SizedBox(height: 16),
                    _bankAssociation(accounts),
                  ],
                  if (_type == AccountType.deposit) ..._depositFields(),
                  if (_type == AccountType.treasuryBill) ..._treasuryFields(),
                  const SizedBox(height: 16),
                  IconColorPicker(
                    iconName: _iconName,
                    colorValue: _colorValue,
                    onIconChanged: (n) => setState(() => _iconName = n),
                    onColorChanged: (c) => setState(() => _colorValue = c),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones (opcional)',
                      prefixIcon: Icon(Icons.sticky_note_2_outlined),
                    ),
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
