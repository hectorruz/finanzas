import 'package:intl/intl.dart';

/// Value object que representa una cantidad monetaria como un número entero de
/// **céntimos** (o, en general, la unidad menor de la divisa).
///
/// Almacenar y operar con enteros evita por completo los errores de coma
/// flotante típicos de `double` (p. ej. `0.1 + 0.2 != 0.3`).
class Money implements Comparable<Money> {
  /// Cantidad en céntimos. 1234 == 12,34 €.
  final int cents;

  /// Código ISO de la divisa (por defecto EUR).
  final String currency;

  const Money(this.cents, {this.currency = 'EUR'});

  const Money.zero({this.currency = 'EUR'}) : cents = 0;

  /// Crea [Money] a partir de un valor decimal (p. ej. `12.34`).
  ///
  /// Se redondea al céntimo más cercano. Útil para resultados de cálculos
  /// externos (cotizaciones, conversiones de divisa) que llegan como `double`.
  factory Money.fromDouble(double amount, {String currency = 'EUR'}) {
    return Money((amount * 100).round(), currency: currency);
  }

  /// Parsea texto introducido por el usuario en céntimos.
  ///
  /// Acepta separador decimal coma o punto y separadores de miles. Devuelve
  /// `null` si el texto no es un importe válido.
  /// Ejemplos: "12,34" -> 1234 · "1.234,50" -> 123450 · "5" -> 500.
  static int? parseToCents(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;

    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);

    // Eliminar símbolos de divisa y espacios.
    text = text.replaceAll(RegExp(r'[^\d.,]'), '');
    if (text.isEmpty) return null;

    final lastComma = text.lastIndexOf(',');
    final lastDot = text.lastIndexOf('.');

    String normalized;
    if (lastComma == -1 && lastDot == -1) {
      // Sin separador decimal: son unidades enteras.
      normalized = '$text.00';
    } else {
      // El separador decimal es el último que aparezca (coma o punto).
      final decimalSep = lastComma > lastDot ? ',' : '.';
      final thousandsSep = decimalSep == ',' ? '.' : ',';
      normalized =
          text.replaceAll(thousandsSep, '').replaceAll(decimalSep, '.');
    }

    final value = double.tryParse(normalized);
    if (value == null) return null;
    final cents = (value * 100).round();
    return negative ? -cents : cents;
  }

  double get asDouble => cents / 100.0;

  bool get isNegative => cents < 0;
  bool get isZero => cents == 0;

  Money operator +(Money other) => Money(cents + other.cents, currency: currency);
  Money operator -(Money other) => Money(cents - other.cents, currency: currency);
  Money operator -() => Money(-cents, currency: currency);

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  /// Formatea con símbolo de divisa según el [locale] indicado.
  String format({String locale = 'es_ES'}) {
    final format = NumberFormat.currency(
      locale: locale,
      name: currency,
      symbol: _symbolFor(currency),
    );
    return format.format(asDouble);
  }

  /// Formatea con signo explícito (`+`/`-`), útil para listas de movimientos.
  String formatSigned({String locale = 'es_ES'}) {
    final base = Money(cents.abs(), currency: currency).format(locale: locale);
    if (cents > 0) return '+$base';
    if (cents < 0) return '-$base';
    return base;
  }

  static String _symbolFor(String currency) {
    switch (currency.toUpperCase()) {
      case 'EUR':
        return '€';
      case 'USD':
        return r'$';
      case 'GBP':
        return '£';
      case 'JPY':
        return '¥';
      default:
        return currency;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.cents == cents && other.currency == currency;

  @override
  int get hashCode => Object.hash(cents, currency);

  @override
  String toString() => format();
}
