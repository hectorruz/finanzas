import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/enums.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_amount_field.dart';
import '../widgets/web_pickers.dart';

/// Revisión pre-guardado de un ticket: bien recién escaneado (con [parsed] +
/// [imageBytes]), bien uno existente para editar ([existing]). Resalta los
/// campos de baja confianza y avisa de posibles duplicados.
class WebReceiptDialog extends ConsumerStatefulWidget {
  const WebReceiptDialog({
    super.key,
    this.parsed,
    this.imageBytes,
    this.imageExt = '.jpg',
    this.existing,
  });

  final ParsedReceiptDto? parsed;
  final Uint8List? imageBytes;
  final String imageExt;
  final ReceiptDto? existing;

  @override
  ConsumerState<WebReceiptDialog> createState() => _WebReceiptDialogState();
}

class _WebReceiptDialogState extends ConsumerState<WebReceiptDialog> {
  late final TextEditingController _merchant;
  int _totalCents = 0;
  DateTime _date = DateTime.now();
  int? _categoryId;
  int? _accountId;
  bool _createExpense = true;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.parsed;
    final e = widget.existing;
    _merchant = TextEditingController(text: e?.merchant ?? p?.merchant ?? '');
    _totalCents = e?.totalCents ?? p?.totalCents ?? 0;
    _date = e?.date ?? p?.date ?? DateTime.now();
    _categoryId = e?.categoryId ?? p?.suggestedCategoryId;
    _accountId = e?.accountId;
  }

  @override
  void dispose() {
    _merchant.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_totalCents <= 0) {
      setState(() => _error = 'Importe no válido');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = ref.read(webClientProvider)!;
    try {
      await client.createReceipt(
        existingReceiptId: widget.existing?.id,
        merchant: _merchant.text.trim(),
        totalCents: _totalCents,
        date: _date,
        rawText: widget.existing?.rawText ?? widget.parsed?.rawText ?? '',
        categoryId: _categoryId,
        accountId: _accountId,
        createExpense: _isEdit ? false : _createExpense,
        imageBytes: widget.imageBytes,
        imageExt: widget.imageExt,
      );
      bumpWebRefresh(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  /// Busca un movimiento parecido (mismo importe, fecha ±1 día) para avisar de
  /// un posible duplicado (p. ej. el gasto ya creado por una recurrente).
  TransactionDto? _possibleDuplicate() {
    if (_isEdit) return null;
    final txns = ref.read(webAllTransactionsProvider).valueOrNull ?? const [];
    for (final t in txns) {
      if (t.type != TransactionType.expense) continue;
      if (t.amountCents != _totalCents) continue;
      if (t.date.difference(_date).inDays.abs() <= 1) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.parsed;
    final lowMerchant = p != null && !p.merchantConfident;
    final lowTotal = p != null && !p.totalConfident;
    final noDate = p != null && p.date == null;
    final dup = _possibleDuplicate();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'Editar ticket' : 'Revisar ticket',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                _isEdit
                    ? 'Ajusta los datos del ticket.'
                    : 'Revisa lo detectado antes de guardar.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 16),
              if (widget.imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(widget.imageBytes!,
                      height: 160, width: double.infinity, fit: BoxFit.cover),
                ),
              if (dup != null) ...[
                const SizedBox(height: 12),
                _Banner(
                  color: Colors.orange,
                  icon: Icons.warning_amber,
                  text:
                      'Ya existe un gasto de ${_totalCents ~/ 100} € en una fecha '
                      'parecida ("${dup.concept}"). ¿Es un duplicado?',
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _merchant,
                decoration: InputDecoration(
                  labelText: 'Comercio',
                  suffixIcon: lowMerchant
                      ? const Tooltip(
                          message: 'Detección de baja confianza',
                          child: Icon(Icons.help_outline, color: Colors.orange))
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              WebAmountField(
                label: lowTotal ? 'Total (revisar)' : 'Total',
                initialCents: _totalCents == 0 ? null : _totalCents,
                onChangedCents: (c) => setState(() => _totalCents = c ?? 0),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event,
                    color: noDate ? Colors.orange : null),
                title: const Text('Fecha'),
                subtitle: noDate ? const Text('No detectada') : null,
                trailing: Text(DateFormat('d MMM yyyy', 'es').format(_date)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              const SizedBox(height: 4),
              WebCategoryPicker(
                value: _categoryId,
                kind: CategoryKind.expense,
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 12),
              WebAccountPicker(
                label: 'Cuenta del gasto',
                value: _accountId,
                includeNone: true,
                noneLabel: 'No crear gasto',
                onChanged: (v) => setState(() => _accountId = v),
              ),
              if (!_isEdit)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Crear gasto vinculado'),
                  subtitle: const Text('Requiere elegir una cuenta'),
                  value: _createExpense && _accountId != null,
                  onChanged: _accountId == null
                      ? null
                      : (v) => setState(() => _createExpense = v),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
