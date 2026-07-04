import 'package:flutter/material.dart';

import '../../core/money/money.dart';

/// Abre una calculadora en una hoja inferior y devuelve el resultado en
/// **céntimos** (o `null` si se cancela). Pensada para rellenar campos de
/// importe: admite `+ − × ÷`, decimales y precedencia de operadores.
Future<int?> showCalculatorSheet(
  BuildContext context, {
  int? initialCents,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CalculatorSheet(initialCents: initialCents),
  );
}

class _CalculatorSheet extends StatefulWidget {
  const _CalculatorSheet({this.initialCents});

  final int? initialCents;

  @override
  State<_CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<_CalculatorSheet> {
  late String _expr;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCents;
    _expr = (initial == null || initial == 0)
        ? ''
        : (initial / 100).toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Valor evaluado del expresión actual, o `null` si aún no es válida.
  double? get _result => _evaluate(_expr);

  void _append(String token) {
    setState(() => _expr += token);
  }

  void _backspace() {
    if (_expr.isEmpty) return;
    setState(() => _expr = _expr.substring(0, _expr.length - 1));
  }

  void _clear() => setState(() => _expr = '');

  /// Reemplaza la expresión por su resultado (botón `=`).
  void _collapse() {
    final r = _result;
    if (r == null) return;
    setState(() => _expr = _formatNumber(r));
  }

  void _confirm() {
    final r = _result;
    if (r == null) return;
    Navigator.of(context).pop((r * 100).round());
  }

  String _formatNumber(double value) {
    // Sin decimales innecesarios: 5.0 -> "5", 5.5 -> "5,5".
    var text = value.toStringAsFixed(2);
    if (text.endsWith('00')) {
      text = text.substring(0, text.length - 3);
    } else if (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    return text.replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final preview = result == null
        ? ''
        : Money((result * 100).round()).format();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pantalla: expresión y resultado en euros.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _expr.isEmpty ? '0' : _expr,
                    style: theme.textTheme.headlineMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildRow(['C', '(', ')', '÷']),
            _buildRow(['7', '8', '9', '×']),
            _buildRow(['4', '5', '6', '−']),
            _buildRow(['1', '2', '3', '+']),
            _buildRow([',', '0', '⌫', '=']),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: result == null ? null : _confirm,
              icon: const Icon(Icons.check),
              label: const Text('Usar importe'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          for (final key in keys)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _CalcButton(
                  label: key,
                  onPressed: () => _onKey(key),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onKey(String key) {
    switch (key) {
      case 'C':
        _clear();
      case '⌫':
        _backspace();
      case '=':
        _collapse();
      default:
        _append(key);
    }
  }
}

class _CalcButton extends StatelessWidget {
  const _CalcButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOperator = '÷×−+=('.contains(label) || label == ')';
    final isAction = label == 'C' || label == '⌫';

    final Color? bg;
    final Color? fg;
    if (label == '=') {
      bg = theme.colorScheme.primaryContainer;
      fg = theme.colorScheme.onPrimaryContainer;
    } else if (isOperator) {
      bg = theme.colorScheme.secondaryContainer;
      fg = theme.colorScheme.onSecondaryContainer;
    } else if (isAction) {
      bg = theme.colorScheme.errorContainer;
      fg = theme.colorScheme.onErrorContainer;
    } else {
      bg = theme.colorScheme.surfaceContainerHigh;
      fg = theme.colorScheme.onSurface;
    }

    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: label == '⌫'
            ? const Icon(Icons.backspace_outlined, size: 22)
            : Text(label, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

/// Evalúa una expresión aritmética (`+ − × ÷`, paréntesis, decimales con coma o
/// punto). Devuelve `null` si la expresión no es válida o está incompleta.
double? _evaluate(String input) {
  final normalized = input
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-')
      .replaceAll(',', '.');
  if (normalized.trim().isEmpty) return null;
  try {
    final parser = _ExprParser(normalized);
    return parser.parse();
  } catch (_) {
    return null;
  }
}

/// Analizador descendente recursivo con precedencia:
/// `expr := term (('+'|'-') term)*`,
/// `term := factor (('*'|'/') factor)*`,
/// `factor := number | ('-'|'+') factor | '(' expr ')'`.
class _ExprParser {
  _ExprParser(this.s);

  final String s;
  int _pos = 0;

  double parse() {
    final value = _parseExpr();
    _skipSpaces();
    if (_pos != s.length) throw const FormatException('sobra texto');
    if (value.isNaN || value.isInfinite) throw const FormatException('inválido');
    return value;
  }

  void _skipSpaces() {
    while (_pos < s.length && s[_pos] == ' ') {
      _pos++;
    }
  }

  double _parseExpr() {
    var value = _parseTerm();
    while (true) {
      _skipSpaces();
      if (_pos >= s.length) break;
      final c = s[_pos];
      if (c == '+') {
        _pos++;
        value += _parseTerm();
      } else if (c == '-') {
        _pos++;
        value -= _parseTerm();
      } else {
        break;
      }
    }
    return value;
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipSpaces();
      if (_pos >= s.length) break;
      final c = s[_pos];
      if (c == '*') {
        _pos++;
        value *= _parseFactor();
      } else if (c == '/') {
        _pos++;
        value /= _parseFactor();
      } else {
        break;
      }
    }
    return value;
  }

  double _parseFactor() {
    _skipSpaces();
    if (_pos >= s.length) throw const FormatException('fin inesperado');
    final c = s[_pos];
    if (c == '-') {
      _pos++;
      return -_parseFactor();
    }
    if (c == '+') {
      _pos++;
      return _parseFactor();
    }
    if (c == '(') {
      _pos++;
      final value = _parseExpr();
      _skipSpaces();
      if (_pos >= s.length || s[_pos] != ')') {
        throw const FormatException('falta )');
      }
      _pos++;
      return value;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skipSpaces();
    final start = _pos;
    while (_pos < s.length && (_isDigit(s[_pos]) || s[_pos] == '.')) {
      _pos++;
    }
    if (_pos == start) throw const FormatException('se esperaba número');
    final value = double.tryParse(s.substring(start, _pos));
    if (value == null) throw const FormatException('número inválido');
    return value;
  }

  bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
}
