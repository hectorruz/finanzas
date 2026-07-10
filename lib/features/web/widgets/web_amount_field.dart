import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/money/money.dart';

/// Campo de importe (euros) para la webapp. Expone el valor en **céntimos** vía
/// [onChangedCents]. Acepta coma o punto como separador decimal, igual que el
/// móvil, pero sin calculadora (en escritorio se teclea con el teclado numérico).
class WebAmountField extends StatefulWidget {
  const WebAmountField({
    super.key,
    this.initialCents,
    required this.onChangedCents,
    this.label = 'Importe',
    this.autofocus = false,
    this.controller,
  });

  final int? initialCents;
  final ValueChanged<int?> onChangedCents;
  final String label;
  final bool autofocus;

  /// Controlador opcional (si el diálogo necesita leer/limpiar el texto).
  final TextEditingController? controller;

  @override
  State<WebAmountField> createState() => _WebAmountFieldState();
}

class _WebAmountFieldState extends State<WebAmountField> {
  late final TextEditingController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    if (widget.initialCents != null && _controller.text.isEmpty) {
      _controller.text =
          (widget.initialCents! / 100).toStringAsFixed(2).replaceAll('.', ',');
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: '€',
        prefixIcon: const Icon(Icons.euro),
      ),
      onChanged: (v) => widget.onChangedCents(Money.parseToCents(v)),
    );
  }
}
