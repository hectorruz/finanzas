import 'package:isar_community/isar.dart';

import 'enums.dart';

part 'transaction.g.dart';

/// Un movimiento: ingreso, gasto o transferencia entre cuentas.
///
/// El importe se guarda en céntimos y **siempre positivo**; el signo se deriva
/// del [type]. Para transferencias, [accountId] es la cuenta de origen y
/// [toAccountId] la de destino.
///
/// Se usan ids planos indexados (en lugar de `IsarLink`) para que el filtrado
/// tipo Excel sea simple y eficiente.
@Collection(accessor: 'transactions')
class TransactionModel {
  Id id = Isar.autoIncrement;

  @Enumerated(EnumType.name)
  TransactionType type = TransactionType.expense;

  /// Importe en céntimos, siempre >= 0.
  int amountCents = 0;

  String concept = '';

  @Index()
  DateTime date = DateTime.now();

  String note = '';

  @Index()
  int accountId = 0;

  /// Cuenta destino (solo para transferencias).
  int? toAccountId;

  @Index()
  int? categoryId;

  /// Si proviene de una regla recurrente, su id (para trazabilidad).
  int? recurringRuleId;

  /// Id del ticket escaneado que originó el movimiento, si aplica.
  int? receiptId;

  TransactionModel();

  /// Importe con signo según el efecto sobre la cuenta propietaria ([accountId]).
  /// Solo un ingreso suma; un gasto resta y una transferencia también resta,
  /// porque [accountId] es siempre la cuenta de origen (el dinero sale de ella).
  /// La cuenta destino de una transferencia lo suma aparte en el cálculo de saldo.
  @ignore
  int get signedCents =>
      type == TransactionType.income ? amountCents : -amountCents;
}
