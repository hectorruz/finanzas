import 'package:finanzas/features/receipts/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flags de confianza del parser: la pantalla de revisión resalta los campos
/// de baja confianza para que nada se guarde a ciegas.
void main() {
  ParsedReceipt parse(List<String> rows) =>
      ReceiptParser().parse([for (final r in rows) OcrLine(r)]);

  test('total etiquetado → confianza alta', () {
    final p = parse(['Mercadona SA', 'Leche 1,20', 'TOTAL 12,50']);
    expect(p.totalCents, 1250);
    expect(p.totalConfident, isTrue);
  });

  test('total por fallback (sin etiqueta) → confianza baja', () {
    final p = parse(['Mercadona SA', 'Leche 1,20', 'Pan 12,50']);
    expect(p.totalCents, isNotNull);
    expect(p.totalConfident, isFalse);
  });

  test('sin importes → total nulo y sin confianza', () {
    final p = parse(['Mercadona SA', 'gracias por su visita']);
    expect(p.totalCents, isNull);
    expect(p.totalConfident, isFalse);
  });

  test('comercio de cabecera plausible → confianza alta', () {
    final p = parse(['Mercadona SA', 'TOTAL 12,50']);
    expect(p.merchant, 'Mercadona Sa');
    expect(p.merchantConfident, isTrue);
  });

  test('comercio por fallback (primera fila rara) → confianza baja', () {
    // Todas las primeras filas empiezan por dígito: ninguna cabecera plausible.
    final p = parse(['12345 99', '678-90', '9 C1 T2', '5 A1 B2']);
    expect(p.merchantConfident, isFalse);
  });

  test('fecha ausente se refleja como null', () {
    final p = parse(['Mercadona SA', 'TOTAL 12,50']);
    expect(p.date, isNull);
  });
}
