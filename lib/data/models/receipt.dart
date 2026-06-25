import 'package:isar_community/isar.dart';

part 'receipt.g.dart';

/// Ticket/factura escaneado mediante OCR.
@Collection(accessor: 'receipts')
class Receipt {
  Id id = Isar.autoIncrement;

  /// Ruta local de la imagen capturada.
  String imagePath = '';

  /// Comercio detectado (editable por el usuario).
  @Index(caseSensitive: false)
  String merchant = '';

  /// Importe total en céntimos.
  int totalCents = 0;

  @Index()
  DateTime date = DateTime.now();

  /// Texto completo reconocido por el OCR (para reprocesar o buscar).
  String rawText = '';

  int? categoryId;

  /// Id del movimiento de gasto creado a partir del ticket, si se generó.
  int? transactionId;

  Receipt();
}
