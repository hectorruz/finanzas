import '../../../data/models/account.dart';
import '../../../data/models/category.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/transaction.dart';

/// Serialización de los modelos a JSON para la **API de datos** que consume la
/// webapp de escritorio. A diferencia del sync, aquí las claves foráneas viajan
/// como ids locales: la webapp es un cliente fino de *este* dispositivo, así que
/// los ids son estables durante la sesión.
class ApiSerializer {
  const ApiSerializer();

  Map<String, dynamic> account(Account a, int balanceCents) => {
        'id': a.id,
        'name': a.name,
        'type': a.type.name,
        'currency': a.currency,
        'iconName': a.iconName,
        'colorValue': a.colorValue,
        'initialBalanceCents': a.initialBalanceCents,
        'balanceCents': balanceCents,
        'archived': a.archived,
        'includeInTotal': a.includeInTotal,
        'parentId': a.parentId,
        'sortOrder': a.sortOrder,
      };

  Map<String, dynamic> category(Category c) => {
        'id': c.id,
        'name': c.name,
        'kind': c.kind.name,
        'iconName': c.iconName,
        'colorValue': c.colorValue,
        'parentId': c.parentId,
        'sortOrder': c.sortOrder,
      };

  Map<String, dynamic> transaction(TransactionModel t) => {
        'id': t.id,
        'type': t.type.name,
        'amountCents': t.amountCents,
        'concept': t.concept,
        'date': t.date.toIso8601String(),
        'note': t.note,
        'accountId': t.accountId,
        'toAccountId': t.toAccountId,
        'categoryId': t.categoryId,
      };

  /// Aplica el JSON entrante sobre [target] (alta o edición desde la webapp).
  /// No toca el id ni los campos de sync (los sella el repositorio al guardar).
  void applyTransaction(TransactionModel target, Map<String, dynamic> m) {
    target
      ..type = enumByName(
          TransactionType.values, m['type'] as String?, TransactionType.expense)
      ..amountCents = m['amountCents'] as int? ?? 0
      ..concept = m['concept'] as String? ?? ''
      ..date = m['date'] == null
          ? DateTime.now()
          : DateTime.parse(m['date'] as String)
      ..note = m['note'] as String? ?? ''
      ..accountId = m['accountId'] as int? ?? 0
      ..toAccountId = m['toAccountId'] as int?
      ..categoryId = m['categoryId'] as int?;
  }
}
