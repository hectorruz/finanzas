import '../../../data/models/account.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/category.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/receipt.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../data/models/transaction.dart';

/// Serialización de los modelos a JSON para la **API de datos** que consume la
/// webapp de escritorio. A diferencia del sync, aquí las claves foráneas viajan
/// como ids locales: la webapp es un cliente fino de *este* dispositivo, así que
/// los ids son estables durante la sesión.
///
/// Regla general de los `apply*`: no tocan `id` ni los campos de sincronización
/// (`uuid`/`updatedAt`/`deletedAt`); los sella el repositorio al guardar.
class ApiSerializer {
  const ApiSerializer();

  // --- Cuentas ---

  Map<String, dynamic> account(Account a, int balanceCents) => {
        'id': a.id,
        'name': a.name,
        'type': a.type.name,
        'currency': a.currency,
        'iconName': a.iconName,
        'colorValue': a.colorValue,
        'note': a.note,
        'initialBalanceCents': a.initialBalanceCents,
        'balanceCents': balanceCents,
        'archived': a.archived,
        'includeInTotal': a.includeInTotal,
        'parentId': a.parentId,
        'sortOrder': a.sortOrder,
      };

  void applyAccount(Account t, Map<String, dynamic> m) {
    t
      ..name = m['name'] as String? ?? t.name
      ..type = enumByName(AccountType.values, m['type'] as String?, t.type)
      ..currency = m['currency'] as String? ?? t.currency
      ..iconName = m['iconName'] as String? ?? t.iconName
      ..colorValue = m['colorValue'] as int? ?? t.colorValue
      ..note = m['note'] as String? ?? t.note
      ..initialBalanceCents = m['initialBalanceCents'] as int? ?? t.initialBalanceCents
      ..archived = m['archived'] as bool? ?? t.archived
      ..includeInTotal = m['includeInTotal'] as bool? ?? t.includeInTotal
      ..parentId = m.containsKey('parentId') ? m['parentId'] as int? : t.parentId
      ..sortOrder = m['sortOrder'] as int? ?? t.sortOrder;
  }

  // --- Categorías ---

  Map<String, dynamic> category(Category c) => {
        'id': c.id,
        'name': c.name,
        'kind': c.kind.name,
        'iconName': c.iconName,
        'colorValue': c.colorValue,
        'isDefault': c.isDefault,
        'parentId': c.parentId,
        'sortOrder': c.sortOrder,
      };

  void applyCategory(Category t, Map<String, dynamic> m) {
    t
      ..name = m['name'] as String? ?? t.name
      ..kind = enumByName(CategoryKind.values, m['kind'] as String?, t.kind)
      ..iconName = m['iconName'] as String? ?? t.iconName
      ..colorValue = m['colorValue'] as int? ?? t.colorValue
      ..isDefault = m['isDefault'] as bool? ?? t.isDefault
      ..parentId = m.containsKey('parentId') ? m['parentId'] as int? : t.parentId
      ..sortOrder = m['sortOrder'] as int? ?? t.sortOrder;
  }

  // --- Movimientos ---

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
        'recurringRuleId': t.recurringRuleId,
        'receiptId': t.receiptId,
      };

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

  // --- Recurrentes ---

  Map<String, dynamic> recurring(RecurringRule r) => {
        'id': r.id,
        'name': r.name,
        'type': r.type.name,
        'amountCents': r.amountCents,
        'concept': r.concept,
        'frequency': r.frequency.name,
        'interval': r.interval,
        'nextDate': r.nextDate.toIso8601String(),
        'endDate': r.endDate?.toIso8601String(),
        'active': r.active,
        'accountId': r.accountId,
        'categoryId': r.categoryId,
        'notifyEnabled': r.notifyEnabled,
        'notifyDaysBefore': r.notifyDaysBefore,
        'notifyHour': r.notifyHour,
        'notifyMinute': r.notifyMinute,
      };

  void applyRecurring(RecurringRule t, Map<String, dynamic> m) {
    t
      ..name = m['name'] as String? ?? t.name
      ..type = enumByName(TransactionType.values, m['type'] as String?, t.type)
      ..amountCents = m['amountCents'] as int? ?? t.amountCents
      ..concept = m['concept'] as String? ?? t.concept
      ..frequency = enumByName(
          RecurringFrequency.values, m['frequency'] as String?, t.frequency)
      ..interval = m['interval'] as int? ?? t.interval
      ..nextDate = m['nextDate'] == null
          ? t.nextDate
          : DateTime.parse(m['nextDate'] as String)
      ..endDate = m.containsKey('endDate')
          ? _date(m['endDate'] as String?)
          : t.endDate
      ..active = m['active'] as bool? ?? t.active
      ..accountId = m['accountId'] as int? ?? t.accountId
      ..categoryId =
          m.containsKey('categoryId') ? m['categoryId'] as int? : t.categoryId
      ..notifyEnabled = m['notifyEnabled'] as bool? ?? t.notifyEnabled
      ..notifyDaysBefore = m['notifyDaysBefore'] as int? ?? t.notifyDaysBefore
      ..notifyHour = m['notifyHour'] as int? ?? t.notifyHour
      ..notifyMinute = m['notifyMinute'] as int? ?? t.notifyMinute;
  }

  // --- Objetivos ---

  Map<String, dynamic> goal(Goal g) => {
        'id': g.id,
        'name': g.name,
        'targetCents': g.targetCents,
        'currentCents': g.currentCents,
        'iconName': g.iconName,
        'colorValue': g.colorValue,
        'deadline': g.deadline?.toIso8601String(),
        'monthlyContributionCents': g.monthlyContributionCents,
        'planMode': g.planMode,
        'sortOrder': g.sortOrder,
      };

  void applyGoal(Goal t, Map<String, dynamic> m) {
    t
      ..name = m['name'] as String? ?? t.name
      ..targetCents = m['targetCents'] as int? ?? t.targetCents
      ..currentCents = m['currentCents'] as int? ?? t.currentCents
      ..iconName = m['iconName'] as String? ?? t.iconName
      ..colorValue = m['colorValue'] as int? ?? t.colorValue
      ..deadline =
          m.containsKey('deadline') ? _date(m['deadline'] as String?) : t.deadline
      ..monthlyContributionCents =
          m['monthlyContributionCents'] as int? ?? t.monthlyContributionCents
      ..planMode = m['planMode'] as String? ?? t.planMode
      ..sortOrder = m['sortOrder'] as int? ?? t.sortOrder;
  }

  // --- Tickets ---

  Map<String, dynamic> receipt(Receipt r) => {
        'id': r.id,
        'merchant': r.merchant,
        'totalCents': r.totalCents,
        'date': r.date.toIso8601String(),
        'rawText': r.rawText,
        'categoryId': r.categoryId,
        'accountId': r.accountId,
        'transactionId': r.transactionId,
        'hasImage': r.imagePath.isNotEmpty,
      };

  // --- Ajustes (subconjunto que gestiona la webapp) ---

  Map<String, dynamic> settings(AppSettings s) => {
        'themeMode': s.themeMode,
        'dynamicColor': s.dynamicColor,
        'amoled': s.amoled,
        'seedColorValue': s.seedColorValue,
        'dashboardCards': s.dashboardCards,
        'webDashboardCards': s.webDashboardCards,
        'totalBalanceAccountIds': s.totalBalanceAccountIds,
        'accountsCardIds': s.accountsCardIds,
        'balanceSubtotals': s.balanceSubtotals,
        'hideAmounts': s.hideAmounts,
        'reportConfig': s.reportConfig,
      };

  /// Aplica solo las claves presentes (patch parcial).
  void applySettings(AppSettings t, Map<String, dynamic> m) {
    if (m.containsKey('themeMode')) t.themeMode = m['themeMode'] as String;
    if (m.containsKey('dynamicColor')) t.dynamicColor = m['dynamicColor'] as bool;
    if (m.containsKey('amoled')) t.amoled = m['amoled'] as bool;
    if (m.containsKey('seedColorValue')) {
      t.seedColorValue = m['seedColorValue'] as int;
    }
    if (m.containsKey('dashboardCards')) {
      t.dashboardCards = _strings(m['dashboardCards']);
    }
    if (m.containsKey('webDashboardCards')) {
      t.webDashboardCards = _strings(m['webDashboardCards']);
    }
    if (m.containsKey('totalBalanceAccountIds')) {
      t.totalBalanceAccountIds = _intList(m['totalBalanceAccountIds']);
    }
    if (m.containsKey('accountsCardIds')) {
      t.accountsCardIds = _intList(m['accountsCardIds']);
    }
    if (m.containsKey('balanceSubtotals')) {
      t.balanceSubtotals = _strings(m['balanceSubtotals']);
    }
    if (m.containsKey('hideAmounts')) t.hideAmounts = m['hideAmounts'] as bool;
    if (m.containsKey('reportConfig')) {
      t.reportConfig = m['reportConfig'] as String? ?? '';
    }
  }

  // --- utilidades ---

  static DateTime? _date(String? s) =>
      (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

  static List<String> _strings(dynamic v) =>
      (v as List<dynamic>? ?? const []).map((e) => e as String).toList();

  static List<int> _intList(dynamic v) =>
      (v as List<dynamic>? ?? const []).map((e) => e as int).toList();
}
