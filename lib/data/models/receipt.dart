import 'package:isar_community/isar.dart';

import '../../core/sync/syncable.dart';

part 'receipt.g.dart';

/// Ticket/factura escaneado mediante OCR.
@Collection(accessor: 'receipts')
class Receipt implements Syncable {
  Id id = Isar.autoIncrement;

  /// Metadatos de sincronización (ver [Syncable]).
  @override
  @Index()
  String uuid = '';
  @override
  DateTime updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  DateTime? deletedAt;

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

  /// Cuenta usada en la compra (editable). Puede ser nula en tickets antiguos.
  int? accountId;

  /// Id del movimiento de gasto creado a partir del ticket, si se generó.
  int? transactionId;

  Receipt();
}
