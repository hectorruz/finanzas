import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../data/models/goal.dart';
import '../../data/models/receipt.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/models/transaction.dart';
import 'model/entity_change.dart';

/// Resuelve el uuid estable de una fila referenciada por su id local (al
/// **codificar** un cambio saliente). Devuelve null si el id es null o no existe.
typedef UuidOf = String? Function(SyncCollection collection, int? localId);

/// Resuelve el id local de una fila referenciada por su uuid (al **aplicar** un
/// cambio entrante). Devuelve null si el uuid es null o aún no existe localmente.
typedef IdOf = int? Function(SyncCollection collection, String? uuid);

/// Traduce entre las entidades del dominio y [EntityChange], sustituyendo las
/// claves foráneas por uuids en ambos sentidos. No toca Isar: opera sobre
/// objetos y callbacks, para ser puro y testeable.
class SyncCodec {
  const SyncCodec();

  // --- Codificación (entidad local -> cambio para enviar) ---

  EntityChange encodeAccount(Account a, UuidOf uuidOf) => EntityChange(
        collection: SyncCollection.account,
        uuid: a.uuid,
        updatedAt: a.updatedAt,
        deletedAt: a.deletedAt,
        data: {
          'name': a.name,
          'type': a.type.name,
          'initialBalanceCents': a.initialBalanceCents,
          'currency': a.currency,
          'iconName': a.iconName,
          'colorValue': a.colorValue,
          'note': a.note,
          'archived': a.archived,
          'includeInTotal': a.includeInTotal,
          'sortOrder': a.sortOrder,
          'parentUuid': uuidOf(SyncCollection.account, a.parentId),
        },
      );

  EntityChange encodeCategory(Category c, UuidOf uuidOf) => EntityChange(
        collection: SyncCollection.category,
        uuid: c.uuid,
        updatedAt: c.updatedAt,
        deletedAt: c.deletedAt,
        data: {
          'name': c.name,
          'kind': c.kind.name,
          'iconName': c.iconName,
          'colorValue': c.colorValue,
          'isDefault': c.isDefault,
          'sortOrder': c.sortOrder,
          'parentUuid': uuidOf(SyncCollection.category, c.parentId),
        },
      );

  EntityChange encodeTransaction(TransactionModel t, UuidOf uuidOf) =>
      EntityChange(
        collection: SyncCollection.transaction,
        uuid: t.uuid,
        updatedAt: t.updatedAt,
        deletedAt: t.deletedAt,
        data: {
          'type': t.type.name,
          'amountCents': t.amountCents,
          'concept': t.concept,
          'date': t.date.toIso8601String(),
          'note': t.note,
          'accountUuid': uuidOf(SyncCollection.account, t.accountId),
          'toAccountUuid': uuidOf(SyncCollection.account, t.toAccountId),
          'categoryUuid': uuidOf(SyncCollection.category, t.categoryId),
          'recurringRuleUuid':
              uuidOf(SyncCollection.recurringRule, t.recurringRuleId),
          'receiptUuid': uuidOf(SyncCollection.receipt, t.receiptId),
        },
      );

  EntityChange encodeRecurring(RecurringRule r, UuidOf uuidOf) => EntityChange(
        collection: SyncCollection.recurringRule,
        uuid: r.uuid,
        updatedAt: r.updatedAt,
        deletedAt: r.deletedAt,
        data: {
          'name': r.name,
          'type': r.type.name,
          'amountCents': r.amountCents,
          'concept': r.concept,
          'frequency': r.frequency.name,
          'interval': r.interval,
          'nextDate': r.nextDate.toIso8601String(),
          'endDate': r.endDate?.toIso8601String(),
          'active': r.active,
          'accountUuid': uuidOf(SyncCollection.account, r.accountId),
          'categoryUuid': uuidOf(SyncCollection.category, r.categoryId),
        },
      );

  /// Nota: `imagePath` NO viaja (es una ruta local sin sentido en el otro
  /// dispositivo). Las imágenes de ticket no se sincronizan; cada móvil guarda
  /// las suyas. Se sincroniza solo la metadata del ticket.
  EntityChange encodeReceipt(Receipt r, UuidOf uuidOf) => EntityChange(
        collection: SyncCollection.receipt,
        uuid: r.uuid,
        updatedAt: r.updatedAt,
        deletedAt: r.deletedAt,
        data: {
          'merchant': r.merchant,
          'totalCents': r.totalCents,
          'date': r.date.toIso8601String(),
          'rawText': r.rawText,
          'categoryUuid': uuidOf(SyncCollection.category, r.categoryId),
          'accountUuid': uuidOf(SyncCollection.account, r.accountId),
          'transactionUuid': uuidOf(SyncCollection.transaction, r.transactionId),
        },
      );

  EntityChange encodeGoal(Goal g, UuidOf uuidOf) => EntityChange(
        collection: SyncCollection.goal,
        uuid: g.uuid,
        updatedAt: g.updatedAt,
        deletedAt: g.deletedAt,
        data: {
          'name': g.name,
          'targetCents': g.targetCents,
          'currentCents': g.currentCents,
          'iconName': g.iconName,
          'colorValue': g.colorValue,
          'deadline': g.deadline?.toIso8601String(),
          'monthlyContributionCents': g.monthlyContributionCents,
          'planMode': g.planMode,
          'sortOrder': g.sortOrder,
        },
      );

  // --- Aplicación (cambio entrante -> entidad local) ---
  //
  // Escribe los metadatos de sync (uuid/updatedAt/deletedAt) y los campos de
  // dominio sobre [target], resolviendo las FKs con [idOf]. No toca el `id`
  // local (lo gestiona el aplicador: reutiliza el de la fila existente o deja
  // que Isar asigne uno nuevo).

  void applyAccount(Account target, EntityChange c, IdOf idOf) {
    final d = c.data;
    target
      ..uuid = c.uuid
      ..updatedAt = c.updatedAt
      ..deletedAt = c.deletedAt
      ..name = d['name'] as String? ?? ''
      ..type = enumByName(AccountType.values, d['type'] as String?, AccountType.bank)
      ..initialBalanceCents = d['initialBalanceCents'] as int? ?? 0
      ..currency = d['currency'] as String? ?? 'EUR'
      ..iconName = d['iconName'] as String? ?? 'account_balance'
      ..colorValue = d['colorValue'] as int? ?? 0xFF2196F3
      ..note = d['note'] as String? ?? ''
      ..archived = d['archived'] as bool? ?? false
      ..includeInTotal = d['includeInTotal'] as bool? ?? true
      ..sortOrder = d['sortOrder'] as int? ?? 0
      ..parentId = idOf(SyncCollection.account, d['parentUuid'] as String?);
  }

  void applyCategory(Category target, EntityChange c, IdOf idOf) {
    final d = c.data;
    target
      ..uuid = c.uuid
      ..updatedAt = c.updatedAt
      ..deletedAt = c.deletedAt
      ..name = d['name'] as String? ?? ''
      ..kind =
          enumByName(CategoryKind.values, d['kind'] as String?, CategoryKind.expense)
      ..iconName = d['iconName'] as String? ?? 'category'
      ..colorValue = d['colorValue'] as int? ?? 0xFF9E9E9E
      ..isDefault = d['isDefault'] as bool? ?? false
      ..sortOrder = d['sortOrder'] as int? ?? 0
      ..parentId = idOf(SyncCollection.category, d['parentUuid'] as String?);
  }

  void applyTransaction(TransactionModel target, EntityChange c, IdOf idOf) {
    final d = c.data;
    target
      ..uuid = c.uuid
      ..updatedAt = c.updatedAt
      ..deletedAt = c.deletedAt
      ..type = enumByName(
          TransactionType.values, d['type'] as String?, TransactionType.expense)
      ..amountCents = d['amountCents'] as int? ?? 0
      ..concept = d['concept'] as String? ?? ''
      ..date = DateTime.parse(d['date'] as String)
      ..note = d['note'] as String? ?? ''
      ..accountId = idOf(SyncCollection.account, d['accountUuid'] as String?) ?? 0
      ..toAccountId = idOf(SyncCollection.account, d['toAccountUuid'] as String?)
      ..categoryId = idOf(SyncCollection.category, d['categoryUuid'] as String?)
      ..recurringRuleId =
          idOf(SyncCollection.recurringRule, d['recurringRuleUuid'] as String?)
      ..receiptId = idOf(SyncCollection.receipt, d['receiptUuid'] as String?);
  }

  void applyRecurring(RecurringRule target, EntityChange c, IdOf idOf) {
    final d = c.data;
    target
      ..uuid = c.uuid
      ..updatedAt = c.updatedAt
      ..deletedAt = c.deletedAt
      ..name = d['name'] as String? ?? ''
      ..type = enumByName(
          TransactionType.values, d['type'] as String?, TransactionType.expense)
      ..amountCents = d['amountCents'] as int? ?? 0
      ..concept = d['concept'] as String? ?? ''
      ..frequency = enumByName(RecurringFrequency.values, d['frequency'] as String?,
          RecurringFrequency.monthly)
      ..interval = d['interval'] as int? ?? 1
      ..nextDate = DateTime.parse(d['nextDate'] as String)
      ..endDate =
          d['endDate'] == null ? null : DateTime.parse(d['endDate'] as String)
      ..active = d['active'] as bool? ?? true
      ..accountId = idOf(SyncCollection.account, d['accountUuid'] as String?) ?? 0
      ..categoryId = idOf(SyncCollection.category, d['categoryUuid'] as String?);
  }

  /// No escribe `imagePath` (no se sincroniza); conserva el que ya tuviera la
  /// fila local si es una actualización.
  void applyReceipt(Receipt target, EntityChange c, IdOf idOf) {
    final d = c.data;
    target
      ..uuid = c.uuid
      ..updatedAt = c.updatedAt
      ..deletedAt = c.deletedAt
      ..merchant = d['merchant'] as String? ?? ''
      ..totalCents = d['totalCents'] as int? ?? 0
      ..date = DateTime.parse(d['date'] as String)
      ..rawText = d['rawText'] as String? ?? ''
      ..categoryId = idOf(SyncCollection.category, d['categoryUuid'] as String?)
      ..accountId = idOf(SyncCollection.account, d['accountUuid'] as String?)
      ..transactionId =
          idOf(SyncCollection.transaction, d['transactionUuid'] as String?);
  }

  void applyGoal(Goal target, EntityChange c, IdOf idOf) {
    final d = c.data;
    target
      ..uuid = c.uuid
      ..updatedAt = c.updatedAt
      ..deletedAt = c.deletedAt
      ..name = d['name'] as String? ?? ''
      ..targetCents = d['targetCents'] as int? ?? 0
      ..currentCents = d['currentCents'] as int? ?? 0
      ..iconName = d['iconName'] as String? ?? 'flag'
      ..colorValue = d['colorValue'] as int? ?? 0xFF4CAF50
      ..deadline =
          d['deadline'] == null ? null : DateTime.parse(d['deadline'] as String)
      ..monthlyContributionCents = d['monthlyContributionCents'] as int? ?? 0
      ..planMode = d['planMode'] as String? ?? 'contribution'
      ..sortOrder = d['sortOrder'] as int? ?? 0;
  }
}
