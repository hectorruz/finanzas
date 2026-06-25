import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/market/yahoo_service.dart';
import '../../core/money/money.dart';
import '../../data/models/holding.dart';
import '../../data/repositories/holding_repository.dart';

const _currencies = ['EUR', 'USD', 'GBP', 'CHF', 'JPY'];

/// Alta/edición de una posición de inversión.
///
/// El precio puede introducirse en otra divisa; al guardar se convierte a EUR
/// (los importes se almacenan siempre en céntimos de EUR). La cantidad admite
/// fracciones y se guarda como entero escalado (×10⁶) sin pérdida de precisión.
class HoldingEditorScreen extends ConsumerStatefulWidget {
  const HoldingEditorScreen({super.key, this.holdingId});
  final int? holdingId;

  @override
  ConsumerState<HoldingEditorScreen> createState() =>
      _HoldingEditorScreenState();
}

class _HoldingEditorScreenState extends ConsumerState<HoldingEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tickerController = TextEditingController();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _sellPriceController = TextEditingController();

  String _buyCurrency = 'EUR';
  String _sellCurrency = 'EUR';
  DateTime _purchaseDate = DateTime.now();
  DateTime? _sellDate;
  bool _sold = false;
  bool _loading = true;
  bool _fetching = false;
  Holding? _existing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.holdingId != null) {
      final list = await ref.read(holdingRepositoryProvider).all();
      final matches = list.where((e) => e.id == widget.holdingId);
      final h = matches.isEmpty ? null : matches.first;
      if (h != null) {
        _existing = h;
        _tickerController.text = h.ticker;
        _nameController.text = h.name;
        _quantityController.text = _trimDouble(h.quantity);
        _buyPriceController.text = (h.buyPriceCents / 100).toStringAsFixed(2);
        _buyCurrency = 'EUR';
        if (h.sellPriceCents != null) {
          _sold = true;
          _sellPriceController.text =
              (h.sellPriceCents! / 100).toStringAsFixed(2);
          _sellDate = h.sellDate;
        }
        _purchaseDate = h.purchaseDate;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tickerController.dispose();
    _nameController.dispose();
    _quantityController.dispose();
    _buyPriceController.dispose();
    _sellPriceController.dispose();
    super.dispose();
  }

  Future<void> _fetchQuote() async {
    final ticker = _tickerController.text.trim();
    if (ticker.isEmpty) return;
    setState(() => _fetching = true);
    try {
      final quote = await ref.read(yahooServiceProvider).fetchQuote(ticker);
      if (!mounted) return;
      setState(() {
        if (_nameController.text.isEmpty) {
          _nameController.text = quote.shortName ?? quote.ticker;
        }
        _buyCurrency = quote.currency;
        if (_buyPriceController.text.isEmpty) {
          _buyPriceController.text = quote.price.toStringAsFixed(2);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${quote.ticker}: ${quote.price.toStringAsFixed(2)} '
            '${quote.currency}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener la cotización: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<int> _toEurCents(String text, String currency) async {
    final cents = Money.parseToCents(text) ?? 0;
    if (currency.toUpperCase() == 'EUR') return cents;
    final rate =
        await ref.read(yahooServiceProvider).fetchFxRate(currency, 'EUR');
    return (cents * rate).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final quantity = double.tryParse(
            _quantityController.text.trim().replaceAll(',', '.')) ??
        0;
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introduce una cantidad válida.')),
      );
      return;
    }

    final buyEur = await _toEurCents(_buyPriceController.text, _buyCurrency);
    int? sellEur;
    if (_sold) {
      sellEur = await _toEurCents(_sellPriceController.text, _sellCurrency);
    }

    final holding = _existing ?? Holding();
    holding
      ..ticker = _tickerController.text.trim().toUpperCase()
      ..name = _nameController.text.trim()
      ..quantity = quantity
      ..buyPriceCents = buyEur
      ..buyCurrency = _buyCurrency
      ..purchaseDate = _purchaseDate
      ..sellPriceCents = _sold ? sellEur : null
      ..sellCurrency = _sold ? _sellCurrency : null
      ..sellDate = _sold ? (_sellDate ?? DateTime.now()) : null;

    await ref.read(holdingRepositoryProvider).save(holding);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    await ref.read(holdingRepositoryProvider).delete(_existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  String _trimDouble(double v) {
    final s = v.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Nueva inversión' : 'Editar inversión'),
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
                    controller: _tickerController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Ticker (p. ej. AAPL, VWCE.DE)',
                      prefixIcon: const Icon(Icons.tag),
                      suffixIcon: _fetching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Obtener cotización',
                              icon: const Icon(Icons.cloud_download),
                              onPressed: _fetchQuote,
                            ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre (opcional)',
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad (admite decimales)',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    validator: (v) {
                      final q = double.tryParse(
                          (v ?? '').trim().replaceAll(',', '.'));
                      return (q == null || q <= 0) ? 'Cantidad inválida' : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _PriceRow(
                    label: 'Precio de compra (por unidad)',
                    controller: _buyPriceController,
                    currency: _buyCurrency,
                    onCurrencyChanged: (c) =>
                        setState(() => _buyCurrency = c),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Fecha de compra'),
                    trailing: Text(DateFormat('d MMM yyyy', 'es')
                        .format(_purchaseDate)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _purchaseDate,
                        firstDate: DateTime(1990),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _purchaseDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _sold,
                    title: const Text('Posición vendida'),
                    onChanged: (v) => setState(() => _sold = v),
                  ),
                  if (_sold) ...[
                    _PriceRow(
                      label: 'Precio de venta (por unidad)',
                      controller: _sellPriceController,
                      currency: _sellCurrency,
                      onCurrencyChanged: (c) =>
                          setState(() => _sellCurrency = c),
                    ),
                  ],
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
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.controller,
    required this.currency,
    required this.onCurrencyChanged,
  });

  final String label;
  final TextEditingController controller;
  final String currency;
  final ValueChanged<String> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.attach_money),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: DropdownButtonFormField<String>(
            value: currency,
            decoration: const InputDecoration(labelText: 'Divisa'),
            items: [
              for (final c in _currencies)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => onCurrencyChanged(v ?? 'EUR'),
          ),
        ),
      ],
    );
  }
}
