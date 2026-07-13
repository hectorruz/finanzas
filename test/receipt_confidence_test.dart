import 'dart:ui' show Rect;

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

  group('comercio con geometría', () {
    ParsedReceipt parseLines(List<OcrLine> lines) =>
        ReceiptParser().parse(lines);

    test('nombre grande arriba gana a la dirección/CIF pequeños', () {
      // El nombre (altura 40) destaca sobre el resto (altura 20): se elige por
      // tamaño de fuente aunque no sea una marca conocida.
      final p = parseLines(const [
        OcrLine('SUPERMERCADO LOLA', Rect.fromLTWH(40, 10, 300, 40)),
        OcrLine('C/ Mayor 3', Rect.fromLTWH(40, 60, 120, 20)),
        OcrLine('CIF B12345678', Rect.fromLTWH(40, 85, 140, 20)),
        OcrLine('28001 Madrid', Rect.fromLTWH(40, 110, 120, 20)),
        OcrLine('TOTAL', Rect.fromLTWH(40, 160, 80, 20)),
        OcrLine('5,00', Rect.fromLTWH(300, 160, 60, 20)),
      ]);
      expect(p.merchant, 'Supermercado Lola');
      expect(p.merchantConfident, isTrue);
    });

    test('marca conocida gana aunque no sea la línea más grande', () {
      // "TICKET DE COMPRA" es más grande, pero es ruido de cabecera; la marca
      // "Mercadona", más pequeña, se elige con alta confianza.
      final p = parseLines(const [
        OcrLine('TICKET DE COMPRA', Rect.fromLTWH(40, 10, 300, 40)),
        OcrLine('Mercadona', Rect.fromLTWH(40, 60, 140, 20)),
        OcrLine('C/ del Sol 1', Rect.fromLTWH(40, 85, 120, 20)),
        OcrLine('TOTAL 5,00', Rect.fromLTWH(40, 160, 120, 20)),
      ]);
      expect(p.merchant, 'Mercadona');
      expect(p.merchantConfident, isTrue);
    });

    test('descarta filas con importe o que empiezan por dígito', () {
      final p = parseLines(const [
        OcrLine('Panaderia Rosa', Rect.fromLTWH(40, 10, 220, 24)),
        OcrLine('2 Barras 3,00', Rect.fromLTWH(40, 50, 200, 20)),
        OcrLine('TOTAL 3,00', Rect.fromLTWH(40, 90, 160, 20)),
      ]);
      expect(p.merchant, 'Panaderia Rosa');
    });
  });
}
