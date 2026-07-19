import '../../core/planning/goal_planning.dart';
import '../../data/models/enums.dart';

/// DTOs planos de la webapp de escritorio. **Desacoplados de Isar** a propósito
/// (no importan `isar_community`) para que compilen en el target web; reutilizan
/// solo los enums, `Money` y la lógica pura de `core/`.

/// Orden de la tabla de movimientos. Los nombres coinciden con `TransactionSort`
/// del servidor (que no se puede importar en el target web porque arrastra Isar),
/// así que el nombre viaja como parámetro y el servidor lo reparsea.
enum WebTxSort { dateDesc, dateAsc, amountDesc, amountAsc }

/// Entidad con jerarquía por `parentId` (cuentas y categorías). Permite un único
/// aplanado de árbol reutilizable ([buildWebTree]) sin duplicar la lógica.
abstract class WebTreeItem {
  int get id;
  String get name;
  int? get parentId;
  int get sortOrder;
}

/// Fila de un árbol aplanado: el elemento y su profundidad (0 = raíz).
class WebTreeRow<T extends WebTreeItem> {
  const WebTreeRow(this.item, this.depth);
  final T item;
  final int depth;
}

/// Aplana una lista jerárquica a orden de árbol (padres antes que hijos),
/// ordenando cada nivel por `sortOrder` y luego por nombre. Los elementos cuyo
/// `parentId` no está en la lista (p. ej. un padre archivado y filtrado) se
/// tratan como raíces para no perderlos.
List<WebTreeRow<T>> buildWebTree<T extends WebTreeItem>(List<T> items) {
  final ids = {for (final it in items) it.id};
  final byParent = <int?, List<T>>{};
  for (final it in items) {
    final parent =
        (it.parentId != null && ids.contains(it.parentId)) ? it.parentId : null;
    (byParent[parent] ??= <T>[]).add(it);
  }
  for (final level in byParent.values) {
    level.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }
  final out = <WebTreeRow<T>>[];
  void visit(int? parentId, int depth) {
    for (final it in byParent[parentId] ?? const []) {
      out.add(WebTreeRow(it, depth));
      visit(it.id, depth + 1);
    }
  }

  visit(null, 0);
  return out;
}

/// Ids de todos los descendientes (hijos, nietos…) de [rootId] en una lista
/// jerárquica. Útil para excluir el subárbol propio al elegir un padre y evitar
/// ciclos.
Set<int> webDescendantIds<T extends WebTreeItem>(int rootId, List<T> items) {
  final childrenOf = <int?, List<int>>{};
  for (final it in items) {
    (childrenOf[it.parentId] ??= <int>[]).add(it.id);
  }
  final result = <int>{};
  void visit(int id) {
    for (final child in childrenOf[id] ?? const <int>[]) {
      if (result.add(child)) visit(child);
    }
  }

  visit(rootId);
  return result;
}

/// Separador de ruta de categoría, igual que el móvil (`category.dart`).
const String kWebCategoryPathSeparator = ' · ';

/// Ruta completa de una categoría (`Padre · Hija`) resolviendo `parentId` sobre
/// el mapa por id. Versión pura para el web (el original importa Isar).
String webCategoryPath(int? categoryId, Map<int, CategoryDto> byId) {
  final parts = <String>[];
  var current = categoryId == null ? null : byId[categoryId];
  final seen = <int>{};
  while (current != null && seen.add(current.id)) {
    parts.add(current.name);
    current = current.parentId == null ? null : byId[current.parentId];
  }
  return parts.reversed.join(kWebCategoryPathSeparator);
}

class AccountDto implements WebTreeItem {
  AccountDto({
    this.id = 0,
    required this.name,
    this.type = AccountType.bank,
    this.currency = 'EUR',
    this.iconName = 'account_balance',
    this.colorValue = 0xFF2196F3,
    this.note = '',
    this.initialBalanceCents = 0,
    this.balanceCents = 0,
    this.archived = false,
    this.includeInTotal = true,
    this.parentId,
    this.bankAccountId,
    this.sortOrder = 0,
    this.depositRateBps,
    this.depositStartDate,
    this.depositEndDate,
    this.depositPayout = DepositPayout.atMaturity,
    this.depositAutoRenew = false,
    this.nominalCents,
  });

  @override
  final int id;
  @override
  final String name;
  final AccountType type;
  final String currency;
  final String iconName;
  final int colorValue;
  final String note;
  final int initialBalanceCents;

  /// Saldo actual calculado por el servidor (solo lectura).
  final int balanceCents;
  final bool archived;
  final bool includeInTotal;
  @override
  final int? parentId;

  /// Banco/cuenta donde está suscrito el depósito o la letra (si no es subcuenta).
  final int? bankAccountId;
  @override
  final int sortOrder;

  // --- Depósito a plazo (solo si type == AccountType.deposit) ---
  final int? depositRateBps;
  final DateTime? depositStartDate;
  final DateTime? depositEndDate;
  final DepositPayout depositPayout;
  final bool depositAutoRenew;

  /// Importe nominal de la Letra del Tesoro (a cobrar al vencimiento).
  final int? nominalCents;

  bool get isSubaccount => parentId != null;

  static AccountDto fromJson(Map<String, dynamic> m) => AccountDto(
        id: m['id'] as int? ?? 0,
        name: m['name'] as String? ?? '',
        type:
            enumByName(AccountType.values, m['type'] as String?, AccountType.bank),
        currency: m['currency'] as String? ?? 'EUR',
        iconName: m['iconName'] as String? ?? 'account_balance',
        colorValue: m['colorValue'] as int? ?? 0xFF2196F3,
        note: m['note'] as String? ?? '',
        initialBalanceCents: m['initialBalanceCents'] as int? ?? 0,
        balanceCents: m['balanceCents'] as int? ?? 0,
        archived: m['archived'] as bool? ?? false,
        includeInTotal: m['includeInTotal'] as bool? ?? true,
        parentId: m['parentId'] as int?,
        bankAccountId: m['bankAccountId'] as int?,
        sortOrder: m['sortOrder'] as int? ?? 0,
        depositRateBps: m['depositRateBps'] as int?,
        depositStartDate: _parseDate(m['depositStartDate'] as String?),
        depositEndDate: _parseDate(m['depositEndDate'] as String?),
        depositPayout: enumByName(DepositPayout.values,
            m['depositPayout'] as String?, DepositPayout.atMaturity),
        depositAutoRenew: m['depositAutoRenew'] as bool? ?? false,
        nominalCents: m['nominalCents'] as int?,
      );

  static DateTime? _parseDate(String? s) =>
      (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.name,
        'currency': currency,
        'iconName': iconName,
        'colorValue': colorValue,
        'note': note,
        'initialBalanceCents': initialBalanceCents,
        'archived': archived,
        'includeInTotal': includeInTotal,
        'parentId': parentId,
        'bankAccountId': bankAccountId,
        'sortOrder': sortOrder,
        'depositRateBps': depositRateBps,
        'depositStartDate': depositStartDate?.toIso8601String(),
        'depositEndDate': depositEndDate?.toIso8601String(),
        'depositPayout': depositPayout.name,
        'depositAutoRenew': depositAutoRenew,
        'nominalCents': nominalCents,
      };
}

class CategoryDto implements WebTreeItem {
  CategoryDto({
    this.id = 0,
    required this.name,
    this.kind = CategoryKind.expense,
    this.iconName = 'category',
    this.colorValue = 0xFF9E9E9E,
    this.isDefault = false,
    this.parentId,
    this.sortOrder = 0,
  });

  @override
  final int id;
  @override
  final String name;
  final CategoryKind kind;
  final String iconName;
  final int colorValue;
  final bool isDefault;
  @override
  final int? parentId;
  @override
  final int sortOrder;

  bool get isSubcategory => parentId != null;

  static CategoryDto fromJson(Map<String, dynamic> m) => CategoryDto(
        id: m['id'] as int? ?? 0,
        name: m['name'] as String? ?? '',
        kind: enumByName(
            CategoryKind.values, m['kind'] as String?, CategoryKind.expense),
        iconName: m['iconName'] as String? ?? 'category',
        colorValue: m['colorValue'] as int? ?? 0xFF9E9E9E,
        isDefault: m['isDefault'] as bool? ?? false,
        parentId: m['parentId'] as int?,
        sortOrder: m['sortOrder'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        'iconName': iconName,
        'colorValue': colorValue,
        'isDefault': isDefault,
        'parentId': parentId,
        'sortOrder': sortOrder,
      };
}

class TransactionDto {
  TransactionDto({
    this.id,
    required this.type,
    required this.amountCents,
    required this.concept,
    required this.date,
    this.note = '',
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.recurringRuleId,
    this.receiptId,
  });

  final int? id;
  final TransactionType type;
  final int amountCents;
  final String concept;
  final DateTime date;
  final String note;
  final int accountId;
  final int? toAccountId;
  final int? categoryId;
  final int? recurringRuleId;
  final int? receiptId;

  static TransactionDto fromJson(Map<String, dynamic> m) => TransactionDto(
        id: m['id'] as int?,
        type: enumByName(
            TransactionType.values, m['type'] as String?, TransactionType.expense),
        amountCents: m['amountCents'] as int? ?? 0,
        concept: m['concept'] as String? ?? '',
        date: DateTime.parse(m['date'] as String),
        note: m['note'] as String? ?? '',
        accountId: m['accountId'] as int? ?? 0,
        toAccountId: m['toAccountId'] as int?,
        categoryId: m['categoryId'] as int?,
        recurringRuleId: m['recurringRuleId'] as int?,
        receiptId: m['receiptId'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'amountCents': amountCents,
        'concept': concept,
        'date': date.toIso8601String(),
        'note': note,
        'accountId': accountId,
        'toAccountId': toAccountId,
        'categoryId': categoryId,
      };

  /// Signo según el efecto sobre la cuenta propietaria (solo un ingreso suma).
  int get signedCents => type == TransactionType.income ? amountCents : -amountCents;
}

class RecurringDto {
  RecurringDto({
    this.id = 0,
    required this.name,
    this.type = TransactionType.expense,
    this.amountCents = 0,
    this.concept = '',
    this.frequency = RecurringFrequency.monthly,
    this.interval = 1,
    required this.nextDate,
    this.endDate,
    this.active = true,
    required this.accountId,
    this.categoryId,
    this.notifyEnabled = false,
    this.notifyDaysBefore = 0,
    this.notifyHour = 9,
    this.notifyMinute = 0,
  });

  final int id;
  final String name;
  final TransactionType type;
  final int amountCents;
  final String concept;
  final RecurringFrequency frequency;
  final int interval;
  final DateTime nextDate;
  final DateTime? endDate;
  final bool active;
  final int accountId;
  final int? categoryId;
  final bool notifyEnabled;
  final int notifyDaysBefore;
  final int notifyHour;
  final int notifyMinute;

  static RecurringDto fromJson(Map<String, dynamic> m) => RecurringDto(
        id: m['id'] as int? ?? 0,
        name: m['name'] as String? ?? '',
        type: enumByName(
            TransactionType.values, m['type'] as String?, TransactionType.expense),
        amountCents: m['amountCents'] as int? ?? 0,
        concept: m['concept'] as String? ?? '',
        frequency: enumByName(RecurringFrequency.values,
            m['frequency'] as String?, RecurringFrequency.monthly),
        interval: m['interval'] as int? ?? 1,
        nextDate: DateTime.parse(m['nextDate'] as String),
        endDate: (m['endDate'] as String?) == null
            ? null
            : DateTime.tryParse(m['endDate'] as String),
        active: m['active'] as bool? ?? true,
        accountId: m['accountId'] as int? ?? 0,
        categoryId: m['categoryId'] as int?,
        notifyEnabled: m['notifyEnabled'] as bool? ?? false,
        notifyDaysBefore: m['notifyDaysBefore'] as int? ?? 0,
        notifyHour: m['notifyHour'] as int? ?? 9,
        notifyMinute: m['notifyMinute'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.name,
        'amountCents': amountCents,
        'concept': concept,
        'frequency': frequency.name,
        'interval': interval,
        'nextDate': nextDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'active': active,
        'accountId': accountId,
        'categoryId': categoryId,
        'notifyEnabled': notifyEnabled,
        'notifyDaysBefore': notifyDaysBefore,
        'notifyHour': notifyHour,
        'notifyMinute': notifyMinute,
      };
}

class GoalDto {
  GoalDto({
    this.id = 0,
    required this.name,
    this.targetCents = 0,
    this.currentCents = 0,
    this.iconName = 'flag',
    this.colorValue = 0xFF4CAF50,
    this.deadline,
    this.monthlyContributionCents = 0,
    this.planMode = 'contribution',
    this.sortOrder = 0,
  });

  final int id;
  final String name;
  final int targetCents;
  final int currentCents;
  final String iconName;
  final int colorValue;
  final DateTime? deadline;
  final int monthlyContributionCents;
  final String planMode;
  final int sortOrder;

  // Cálculos derivados, compartidos con el móvil (`core/planning`).
  double get progress => goalProgress(currentCents, targetCents);
  int get remainingCents => goalRemainingCents(currentCents, targetCents);
  int? get monthsToTarget => goalMonthsToTarget(
        planMode: planMode,
        monthlyContributionCents: monthlyContributionCents,
        remainingCents: remainingCents,
      );
  DateTime? get projectedDate => goalProjectedDate(
        planMode: planMode,
        monthlyContributionCents: monthlyContributionCents,
        remainingCents: remainingCents,
      );
  int? get requiredMonthlyCents => goalRequiredMonthlyCents(
        planMode: planMode,
        deadline: deadline,
        remainingCents: remainingCents,
      );
  String? get planLabel => goalPlanLabelFor(
        currentCents: currentCents,
        targetCents: targetCents,
        planMode: planMode,
        monthlyContributionCents: monthlyContributionCents,
        deadline: deadline,
      );

  static GoalDto fromJson(Map<String, dynamic> m) => GoalDto(
        id: m['id'] as int? ?? 0,
        name: m['name'] as String? ?? '',
        targetCents: m['targetCents'] as int? ?? 0,
        currentCents: m['currentCents'] as int? ?? 0,
        iconName: m['iconName'] as String? ?? 'flag',
        colorValue: m['colorValue'] as int? ?? 0xFF4CAF50,
        deadline: (m['deadline'] as String?) == null
            ? null
            : DateTime.tryParse(m['deadline'] as String),
        monthlyContributionCents: m['monthlyContributionCents'] as int? ?? 0,
        planMode: m['planMode'] as String? ?? 'contribution',
        sortOrder: m['sortOrder'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'targetCents': targetCents,
        'currentCents': currentCents,
        'iconName': iconName,
        'colorValue': colorValue,
        'deadline': deadline?.toIso8601String(),
        'monthlyContributionCents': monthlyContributionCents,
        'planMode': planMode,
        'sortOrder': sortOrder,
      };
}

class ReceiptDto {
  ReceiptDto({
    required this.id,
    required this.merchant,
    required this.totalCents,
    required this.date,
    this.rawText = '',
    this.categoryId,
    this.accountId,
    this.transactionId,
    this.hasImage = false,
  });

  final int id;
  final String merchant;
  final int totalCents;
  final DateTime date;
  final String rawText;
  final int? categoryId;
  final int? accountId;
  final int? transactionId;
  final bool hasImage;

  static ReceiptDto fromJson(Map<String, dynamic> m) => ReceiptDto(
        id: m['id'] as int? ?? 0,
        merchant: m['merchant'] as String? ?? '',
        totalCents: m['totalCents'] as int? ?? 0,
        date: DateTime.parse(m['date'] as String),
        rawText: m['rawText'] as String? ?? '',
        categoryId: m['categoryId'] as int?,
        accountId: m['accountId'] as int?,
        transactionId: m['transactionId'] as int?,
        hasImage: m['hasImage'] as bool? ?? false,
      );
}

/// Resultado del OCR de un ticket (procesado en el móvil vía subida de la foto).
class ParsedReceiptDto {
  ParsedReceiptDto({
    this.merchant,
    this.totalCents,
    this.date,
    this.suggestedCategoryId,
    this.merchantConfident = false,
    this.totalConfident = false,
    this.rawText = '',
  });

  final String? merchant;
  final int? totalCents;
  final DateTime? date;
  final int? suggestedCategoryId;
  final bool merchantConfident;
  final bool totalConfident;
  final String rawText;

  static ParsedReceiptDto fromJson(Map<String, dynamic> m) => ParsedReceiptDto(
        merchant: m['merchant'] as String?,
        totalCents: m['totalCents'] as int?,
        date: (m['date'] as String?) == null
            ? null
            : DateTime.tryParse(m['date'] as String),
        suggestedCategoryId: m['suggestedCategoryId'] as int?,
        merchantConfident: m['merchantConfident'] as bool? ?? false,
        totalConfident: m['totalConfident'] as bool? ?? false,
        rawText: m['rawText'] as String? ?? '',
      );
}

class SettingsDto {
  SettingsDto({
    this.themeMode = 'system',
    this.dynamicColor = true,
    this.amoled = true,
    this.seedColorValue = 0xFF2196F3,
    this.dashboardCards = const [],
    this.webDashboardCards = const [],
    this.totalBalanceAccountIds = const [],
    this.accountsCardIds = const [],
    this.balanceSubtotals = const [],
    this.hideAmounts = false,
    this.reportConfig = '',
  });

  final String themeMode;
  final bool dynamicColor;
  final bool amoled;
  final int seedColorValue;
  final List<String> dashboardCards;
  final List<String> webDashboardCards;
  final List<int> totalBalanceAccountIds;
  final List<int> accountsCardIds;
  final List<String> balanceSubtotals;
  final bool hideAmounts;
  final String reportConfig;

  static SettingsDto fromJson(Map<String, dynamic> m) => SettingsDto(
        themeMode: m['themeMode'] as String? ?? 'system',
        dynamicColor: m['dynamicColor'] as bool? ?? true,
        amoled: m['amoled'] as bool? ?? true,
        seedColorValue: m['seedColorValue'] as int? ?? 0xFF2196F3,
        dashboardCards: _strs(m['dashboardCards']),
        webDashboardCards: _strs(m['webDashboardCards']),
        totalBalanceAccountIds: _ints(m['totalBalanceAccountIds']),
        accountsCardIds: _ints(m['accountsCardIds']),
        balanceSubtotals: _strs(m['balanceSubtotals']),
        hideAmounts: m['hideAmounts'] as bool? ?? false,
        reportConfig: m['reportConfig'] as String? ?? '',
      );

  static List<String> _strs(dynamic v) =>
      (v as List<dynamic>? ?? const []).map((e) => e as String).toList();
  static List<int> _ints(dynamic v) =>
      (v as List<dynamic>? ?? const []).map((e) => e as int).toList();
}
