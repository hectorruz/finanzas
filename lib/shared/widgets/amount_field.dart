import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money/money.dart';

/// Campo de texto para introducir importes en euros.
///
/// Expone el valor ya convertido a **céntimos** mediante [onChangedCents].
/// Acepta coma o punto como separador decimal.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    this.initialCents,
    required this.onChangedCents,
    this.label = 'Importe',
    this.autofocus = false,
  });

  final int? initialCents;
  final ValueChanged<int?> onChangedCents;
  final String label;
  final bool autofocus;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCents;
    _controller = TextEditingController(
      text: initial == null
          ? ''
          : (initial / 100).toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      autofocus: widget.autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: '€',
        prefixIcon: const Icon(Icons.euro),
      ),
      validator: (value) {
        final cents = Money.parseToCents(value ?? '');
        if (cents == null || cents <= 0) return 'Introduce un importe válido';
        return null;
      },
      onChanged: (value) => widget.onChangedCents(Money.parseToCents(value)),
    );
  }
}
