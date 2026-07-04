import 'dart:ui' show Rect;

import 'package:finanzas/features/receipts/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<OcrLine> plain(List<String> rows) => [for (final r in rows) OcrLine(r)];

void main() {
  final parser = ReceiptParser();

  group('Tickets reales (texto en orden de lectura)', () {
    test('McDonald\'s: "TOTAL (IVA Incluido)" no se descarta por "iva"', () {
      final rows = [
        "Restaurante McDonald's",
        'Aeropuerto Madrid Barajas T4',
        'Zona Aire Local T1 14',
        '28042 Madrid',
        "McDonald's Sistemas de España, INC",
        'C/ Somera 5',
        '28023 Madrid',
        'C.I.F N-4001649-E',
        'Factura simplificada',
        'Num: 0451201306202400086',
        'Pedido:0086 Caja:24 20/06/2013 14:36',
        'UND ARTICULO TOTAL',
        '1 TOMAR 0.00',
        '1 COCA MEN GR 0.00',
        '1 MENU GR CUARTO 6.90',
        '1 CHICK-CHEESE 1.30',
        '1 PAT LUXE MENU GR 0.00',
        'Para tomar',
        'TOTAL (IVA Incluido) 8.20',
        'TCR (8.20) 8.20',
        'IVA',
        'IVA 10.00% de 7.45 = 0.75',
        'GRACIAS POR SU VISITA',
      ];
      final parsed = parser.parse(plain(rows));
      // Antes: se excluía la fila del total por contener "iva" y ganaba el
      // "10.00" del desglose de IVA.
      expect(parsed.totalCents, 820);
      expect(parsed.date, DateTime(2013, 6, 20));
      expect(parsed.suggestedCategory, 'Ocio');
    });

    test('Picasso: el NIF "37.722.103" no genera importes', () {
      final rows = [
        'Picasso',
        'MALLORCA, 422 08013 BARCELONA',
        'TELF.:93 246 53 49',
        'NIF: 37.722.103- X',
        'MESA 21 COMENSALES 2',
        'FACTURA 506947',
        '26/07/2016',
        'Cant. Descripcion P.U. Total',
        '2 CAFE CON LECHE 4.10 8.20',
        'TOTAL 8.20',
        'BASE IMPONIBLE 7.45 IVA 10% 0.75',
        '... GRACIAS POR SU VISITA ...',
        'MEDIODIA NOE/INGRID CAJA 2',
      ];
      final parsed = parser.parse(plain(rows));
      expect(parsed.totalCents, 820);
      expect(parsed.merchant, 'Picasso');
      expect(parsed.date, DateTime(2016, 7, 26));
    });

    test('Carrefour express: TOTAAL holandés, CASH/TERUG excluidos', () {
      final rows = [
        'Carrefour express',
        'EXPRESS BTW BE 0806.012.590',
        'ST-KATELIJNESTRAAT 76 BRUGGE 050/33.64.11',
        '1 DUVEL TRIPEL 33CL 1,85 1,85',
        'L+ 1 LEEGGOED 0,10 0,10',
        '1 WESTMALLE XXW 24X 1,09 1,09',
        'L+ 1 LEEGGOED 0,10 0,10',
        '1 ROCHEFORT 33CL 1,62 1,62',
        'L+ 1 LEEGGOED 0,10 0,10',
        '1 ORVAL TRAPPIST 33C 1,72 1,72',
        'L+ 1 LEEGGOED 0,10 0,10',
        '1 ROCHEFORT 33CL 2,25 2,25',
        'L+ 1 LEEGGOED 0,10 0,10',
        '1 ROCHEFORT 6D 33CL 1,59 1,59',
        'L+ 1 LEEGGOED 0,10 0,10',
        '6 ART. TOTAAL 10,72',
        'CASH 10,75',
        'TERUG 0,03',
        'maand t vrij 8 u t 19 u zat en zo 8.30u t 19u',
        'dank u voor uw bezoek en tot binnenkort',
        '90366568 26/08/2013 11:00 1375 03 0149 23203358',
      ];
      final parsed = parser.parse(plain(rows));
      // Antes: "BTW BE 0806.012.590" producía un candidato de 806,01 €.
      expect(parsed.totalCents, 1072);
      expect(parsed.date, DateTime(2013, 8, 26));
      expect(parsed.suggestedCategory, 'Alimentación');
    });

    test('La Nicoletta: Subtotal/Efectivo/Cambio no ganan al Total', () {
      final rows = [
        'Restaurante La Nicoletta',
        'Técnicas de Hostelería Fuencarral, S.L.',
        'C/ Juan Ramón Jiménez 12 entreplanta',
        '28036 MADRID',
        'Tfno: 91 716 02 17 FAX: 91 716 02 18',
        'C.I.F.: B-86484722',
        'Mesa número: 231',
        'Comensales 2',
        '2 Pan y Aperitivo 3,18',
        '1 COCA COLA 2,00',
        '1 AGUA MINERAL 1/2 2,09',
        '1 Rissoto Espárragos Verdes 8,86',
        '1 Lasaña de verduras asadas 9,77',
        'Subtotal------------------------ 25,90',
        'Iva 10% 25,90 2,59',
        'Total ------- 28,49',
        'Efectivo........................ 20,00',
        'Efectivo........................ 5,00',
        'Efectivo........................ 4,00',
        'Cambio',
        'Efectivo...... 0,51',
        'Le atendió: Camarero 7',
        'Fra. Simplificada: 12958',
        'Oper. Caja Ticket Fecha/Hora/Turno',
        '00027 00004 29497 29/03/2014 16:15:38 1',
        'IVA Incluido',
      ];
      final parsed = parser.parse(plain(rows));
      expect(parsed.totalCents, 2849);
      expect(parsed.date, DateTime(2014, 3, 29));
      expect(parsed.suggestedCategory, 'Ocio');
    });
  });

  group('Tickets reales (columnas en bloques separados)', () {
    test('McDonald\'s con etiquetas e importes en bloques distintos', () {
      final rows = [
        "Restaurante McDonald's",
        'Factura simplificada',
        'Pedido:0086 Caja:24 20/06/2013 14:36',
        '1 TOMAR',
        '1 COCA MEN GR',
        '1 MENU GR CUARTO',
        '1 CHICK-CHEESE',
        '1 PAT LUXE MENU GR',
        '0.00',
        '0.00',
        '6.90',
        '1.30',
        '0.00',
        'Para tomar',
        'TOTAL (IVA Incluido)',
        'TCR',
        '8.20',
        '8.20',
        'IVA 10.00% de 7.45 = 0.75',
      ];
      expect(parser.parse(plain(rows)).totalCents, 820);
    });

    test('bloque de etiquetas + bloque de importes emparejados por posición',
        () {
      final rows = [
        'Bar Manolo',
        '2 Cañas 3,00',
        '1 Ración bravas 6,50',
        'Subtotal',
        'TOTAL',
        'Efectivo',
        'Cambio',
        '25,90',
        '28,49',
        '30,00',
        '1,51',
      ];
      expect(ReceiptParser.detectTotalCents(rows), 2849);
    });
  });

  group('detectTotalCents (sintéticos)', () {
    test('subtotal, efectivo y cambio pierden contra el total', () {
      expect(
        ReceiptParser.detectTotalCents([
          'Cerveza 3,50',
          'Tapa 12,00',
          'Subtotal 25,90',
          'TOTAL 28,50',
          'Efectivo 30,00',
          'Cambio 1,50',
        ]),
        2850,
      );
    });

    test('separador de miles', () {
      expect(ReceiptParser.detectTotalCents(['TOTAL 1.234,56']), 123456);
    });

    test('puntos de relleno pegados al importe', () {
      expect(ReceiptParser.detectTotalCents(['TOTAL.......28,49']), 2849);
    });

    test('sin etiqueta: gana el máximo, pero nunca una fila de pago', () {
      expect(
        ReceiptParser.detectTotalCents([
          'Cerveza 3,50',
          'Tapa 12,00',
          'Efectivo 20,00',
        ]),
        1200,
      );
    });

    test('tarjeta vale de último recurso pero pierde contra el total', () {
      expect(
        ReceiptParser.detectTotalCents(['TOTAL 15,00', 'Tarjeta 15,00']),
        1500,
      );
      expect(ReceiptParser.detectTotalCents(['Tarjeta 15,00']), 1500);
    });

    test('NIF, CIF, BTW y teléfonos no generan candidatos', () {
      expect(
        ReceiptParser.detectTotalCents([
          'NIF: 37.722.103- X',
          'BTW BE 0806.012.590',
          'TELF.:93 246 53 49',
          'C.I.F.: B-86484722',
        ]),
        null,
      );
    });

    test('fechas, horas, porcentajes y unidades no son importes', () {
      expect(
        ReceiptParser.detectTotalCents([
          '04.07.26 16:15',
          'zo 8.30u t 19u',
          'IVA 21% 4,20',
        ]),
        null,
      );
    });

    test('cabecera de columnas no cuenta como etiqueta de total', () {
      expect(
        ReceiptParser.detectTotalCents([
          'Cant. Descripcion P.U. Total',
          '2 CAFE CON LECHE 4.10 8.20',
        ]),
        820,
      );
    });

    test('importes a cero y tickets vacíos', () {
      expect(ReceiptParser.detectTotalCents(['Bolsa 0,00']), null);
      expect(ReceiptParser.detectTotalCents([]), null);
    });
  });

  group('reconstructRows (geometría)', () {
    test('reagrupa etiqueta e importe de la misma fila física', () {
      final lines = [
        const OcrLine('8,20', Rect.fromLTWH(300, 101, 60, 20)),
        const OcrLine('IVA 10%', Rect.fromLTWH(10, 140, 80, 20)),
        const OcrLine('TOTAL', Rect.fromLTWH(10, 100, 110, 20)),
      ];
      expect(
        ReceiptParser.reconstructRows(lines),
        ['TOTAL 8,20', 'IVA 10%'],
      );
    });

    test('tolera ligera inclinación (media móvil de la fila)', () {
      final lines = [
        const OcrLine('a', Rect.fromLTWH(0, 90, 40, 20)),
        const OcrLine('b', Rect.fromLTWH(50, 96, 40, 20)),
        const OcrLine('c', Rect.fromLTWH(100, 102, 40, 20)),
        const OcrLine('d', Rect.fromLTWH(0, 120, 40, 20)),
      ];
      expect(ReceiptParser.reconstructRows(lines), ['a b c', 'd']);
    });

    test('sin geometría se conserva el orden de entrada', () {
      final lines = [
        const OcrLine('segunda'),
        const OcrLine('primera', Rect.fromLTWH(0, 0, 10, 10)),
      ];
      expect(ReceiptParser.reconstructRows(lines), ['segunda', 'primera']);
    });

    test('parse extremo a extremo con bloques desordenados', () {
      final lines = [
        const OcrLine('Bar Pepe', Rect.fromLTWH(60, 10, 120, 22)),
        // Bloque derecho (importes) llega antes que el izquierdo.
        const OcrLine('4,50', Rect.fromLTWH(300, 50, 50, 20)),
        const OcrLine('9,00', Rect.fromLTWH(300, 80, 50, 20)),
        const OcrLine('2 Menús', Rect.fromLTWH(10, 51, 90, 20)),
        const OcrLine('TOTAL', Rect.fromLTWH(10, 81, 80, 20)),
      ];
      final parsed = parser.parse(lines);
      expect(parsed.totalCents, 900);
      expect(parsed.merchant, 'Bar Pepe');
    });
  });
}
