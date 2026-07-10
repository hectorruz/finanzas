import 'package:isar_community/isar.dart';

import '../../data/models/enums.dart';
import '../../data/models/receipt.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/merchant_rule_repository.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/transaction_repository.dart';

/// Resultado de guardar un ticket: el id del ticket y el del gasto vinculado.
class ReceiptSaveResult {
  const ReceiptSaveResult(this.receiptId, this.transactionId);
  final int receiptId;
  final int? transactionId;
}

/// Guarda un ticket y (opcionalmente) su gasto vinculado siguiendo el **mismo
/// camino de escritura** que la pantalla de escaneo del móvil (repositorios →
/// sellado de sync + soft-delete), y refuerza la memoria comercio→categoría.
///
/// Extraído de `receipt_scan_screen.dart` para reutilizarlo desde el endpoint
/// `POST /api/receipts` de la webapp. No toca la imagen: el llamador ya la ha
/// persistido y pasa la ruta (o cadena vacía).
class ReceiptSaveService {
  ReceiptSaveService(Isar isar)
      : _receipts = ReceiptRepository(isar),
        _transactions = TransactionRepository(isar),
        _merchantRules = MerchantRuleRepository(isar);

  final ReceiptRepository _receipts;
  final TransactionRepository _transactions;
  final MerchantRuleRepository _merchantRules;

  Future<ReceiptSaveResult> save({
    int? existingReceiptId,
    required String merchant,
    required int totalCents,
    required DateTime date,
    String rawText = '',
    int? categoryId,
    int? accountId,
    bool createExpense = true,
    String imagePath = '',
    bool updateImage = true,
  }) async {
    final receipt = existingReceiptId != null
        ? (await _receipts.getById(existingReceiptId)) ?? Receipt()
        : Receipt();
    if (updateImage) receipt.imagePath = imagePath;
    receipt
      ..merchant = merchant
      ..totalCents = totalCents
      ..date = date
      ..rawText = rawText
      ..categoryId = categoryId
      ..accountId = accountId;
    final receiptId = await _receipts.save(receipt);

    // Crea o sincroniza el gasto vinculado.
    var transactionId = receipt.transactionId;
    if (transactionId != null) {
      final txn = await _transactions.getById(transactionId);
      if (txn != null) {
        txn
          ..type = TransactionType.expense
          ..amountCents = totalCents
          ..concept = merchant
          ..date = date
          ..categoryId = categoryId
          ..accountId = accountId ?? txn.accountId
          ..receiptId = receiptId;
        await _transactions.save(txn);
      } else {
        transactionId = null; // el gasto vinculado ya no existe
      }
    } else if (createExpense && accountId != null) {
      final txn = TransactionModel()
        ..type = TransactionType.expense
        ..amountCents = totalCents
        ..concept = merchant
        ..date = date
        ..accountId = accountId
        ..categoryId = categoryId
        ..receiptId = receiptId;
      transactionId = await _transactions.save(txn);
    }

    // Enlace inverso en el ticket si cambió.
    if (receipt.transactionId != transactionId) {
      receipt.transactionId = transactionId;
      await _receipts.save(receipt);
    }

    // Memoria de correcciones: comercio → categoría.
    if (merchant.trim().isNotEmpty && categoryId != null) {
      await _merchantRules.remember(merchant.trim(), categoryId);
    }

    return ReceiptSaveResult(receiptId, transactionId);
  }
}
