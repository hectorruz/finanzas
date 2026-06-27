import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../core/db/isar_provider.dart';
import 'models/account.dart';
import 'models/app_settings.dart';
import 'models/category.dart';
import 'models/enums.dart';
import 'models/goal.dart';
import 'models/receipt.dart';
import 'models/recurring_rule.dart';
import 'models/transaction.dart';

/// Exporta e importa todos los datos de la app en formato JSON.
class BackupService {
  BackupService(this._isar);
  final Isar _isar;

  static const int _version = 1;

  /// Serializa toda la base de datos a un JSON legible.
  Future<String> exportJson() async {
    final data = <String, dynamic>{
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'accounts': (await _isar.accounts.where().findAll())
          .map(_accountToMap)
          .toList(),
      'categories': (await _isar.categories.where().findAll())
          .map(_categoryToMap)
          .toList(),
      'transactions': (await _isar.transactions.where().findAll())
          .map(_transactionToMap)
          .toList(),
      'recurringRules': (await _isar.recurringRules.where().findAll())
          .map(_recurringToMap)
          .toList(),
      'receipts': (await _isar.receipts.where().findAll())
          .map(_receiptToMap)
          .toList(),
      'goals':
          (await _isar.goals.where().findAll()).map(_goalToMap).toList(),
      'settings': _settingsToMap(await _isar.settings.get(0)),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Escribe el export a un fichero temporal y devuelve su ruta (para compartir).
  Future<File> exportToFile() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/finanzas_backup_$stamp.json');
    await file.writeAsString(await exportJson());
    return file;
  }

  /// Reemplaza todos los datos por los del JSON indicado.
  Future<void> importJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    await _isar.writeTxn(() async {
      await _isar.accounts.clear();
      await _isar.categories.clear();
      await _isar.transactions.clear();
      await _isar.recurringRules.clear();
      await _isar.receipts.clear();
      await _isar.goals.clear();

      await _isar.accounts.putAll(
          _list(data['accounts']).map(_accountFromMap).toList());
      await _isar.categories.putAll(
          _list(data['categories']).map(_categoryFromMap).toList());
      await _isar.transactions.putAll(
          _list(data['transactions']).map(_transactionFromMap).toList());
      await _isar.recurringRules.putAll(
          _list(data['recurringRules']).map(_recurringFromMap).toList());
      await _isar.receipts.putAll(
          _list(data['receipts']).map(_receiptFromMap).toList());
      await _isar.goals
          .putAll(_list(data['goals']).map(_goalFromMap).toList());

      if (data['settings'] != null) {
        await _isar.settings
            .put(_settingsFromMap(data['settings'] as Map<String, dynamic>));
      }
    });
  }

  /// Borra todos los datos de la app.
  Future<void> wipe() async {
    await _isar.writeTxn(() async {
      await _isar.accounts.clear();
      await _isar.categories.clear();
      await _isar.transactions.clear();
      await _isar.recurringRules.clear();
      await _isar.receipts.clear();
      await _isar.goals.clear();
      await _isar.settings.clear();
    });
  }

  // --- Mapeos (toMap / fromMap) ---

  List<Map<String, dynamic>> _list(dynamic raw) =>
      (raw as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();

  Map<String, dynamic> _accountToMap(Account a) => {
        'id': a.id,
        'name': a.name,
        'type': a.type.name,
        'initialBalanceCents': a.initialBalanceCents,
        'currency': a.currency,
        'iconName': a.iconName,
        'colorValue': a.colorValue,
        'archived': a.archived,
        'includeInTotal': a.includeInTotal,
        'note': a.note,
        'parentId': a.parentId,
        'sortOrder': a.sortOrder,
      };

  Account _accountFromMap(Map<String, dynamic> m) => Account()
    ..id = m['id'] as int
    ..name = m['name'] as String
    ..type = enumByName(AccountType.values, m['type'] as String?, AccountType.bank)
    ..initialBalanceCents = m['initialBalanceCents'] as int? ?? 0
    ..currency = m['currency'] as String? ?? 'EUR'
    ..iconName = m['iconName'] as String? ?? 'account_balance'
    ..colorValue = m['colorValue'] as int? ?? 0xFF1976D2
    ..archived = m['archived'] as bool? ?? false
    ..includeInTotal = m['includeInTotal'] as bool? ?? true
    ..note = m['note'] as String? ?? ''
    ..parentId = m['parentId'] as int?
    ..sortOrder = m['sortOrder'] as int? ?? 0;

  Map<String, dynamic> _categoryToMap(Category c) => {
        'id': c.id,
        'name': c.name,
        'kind': c.kind.name,
        'iconName': c.iconName,
        'colorValue': c.colorValue,
        'isDefault': c.isDefault,
        'parentId': c.parentId,
        'sortOrder': c.sortOrder,
      };

  Category _categoryFromMap(Map<String, dynamic> m) => Category()
    ..id = m['id'] as int
    ..name = m['name'] as String
    ..kind =
        enumByName(CategoryKind.values, m['kind'] as String?, CategoryKind.expense)
    ..iconName = m['iconName'] as String? ?? 'category'
    ..colorValue = m['colorValue'] as int? ?? 0xFF9E9E9E
    ..isDefault = m['isDefault'] as bool? ?? false
    ..parentId = m['parentId'] as int?
    ..sortOrder = m['sortOrder'] as int? ?? 0;

  Map<String, dynamic> _transactionToMap(TransactionModel t) => {
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

  TransactionModel _transactionFromMap(Map<String, dynamic> m) =>
      TransactionModel()
        ..id = m['id'] as int
        ..type = enumByName(
            TransactionType.values, m['type'] as String?, TransactionType.expense)
        ..amountCents = m['amountCents'] as int? ?? 0
        ..concept = m['concept'] as String? ?? ''
        ..date = DateTime.parse(m['date'] as String)
        ..note = m['note'] as String? ?? ''
        ..accountId = m['accountId'] as int? ?? 0
        ..toAccountId = m['toAccountId'] as int?
        ..categoryId = m['categoryId'] as int?
        ..recurringRuleId = m['recurringRuleId'] as int?
        ..receiptId = m['receiptId'] as int?;

  Map<String, dynamic> _recurringToMap(RecurringRule r) => {
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
      };

  RecurringRule _recurringFromMap(Map<String, dynamic> m) => RecurringRule()
    ..id = m['id'] as int
    ..name = m['name'] as String? ?? ''
    ..type = enumByName(
        TransactionType.values, m['type'] as String?, TransactionType.expense)
    ..amountCents = m['amountCents'] as int? ?? 0
    ..concept = m['concept'] as String? ?? ''
    ..frequency = enumByName(RecurringFrequency.values,
        m['frequency'] as String?, RecurringFrequency.monthly)
    ..interval = m['interval'] as int? ?? 1
    ..nextDate = DateTime.parse(m['nextDate'] as String)
    ..endDate = m['endDate'] == null
        ? null
        : DateTime.parse(m['endDate'] as String)
    ..active = m['active'] as bool? ?? true
    ..accountId = m['accountId'] as int? ?? 0
    ..categoryId = m['categoryId'] as int?;

  Map<String, dynamic> _receiptToMap(Receipt r) => {
        'id': r.id,
        'imagePath': r.imagePath,
        'merchant': r.merchant,
        'totalCents': r.totalCents,
        'date': r.date.toIso8601String(),
        'rawText': r.rawText,
        'categoryId': r.categoryId,
        'transactionId': r.transactionId,
      };

  Receipt _receiptFromMap(Map<String, dynamic> m) => Receipt()
    ..id = m['id'] as int
    ..imagePath = m['imagePath'] as String? ?? ''
    ..merchant = m['merchant'] as String? ?? ''
    ..totalCents = m['totalCents'] as int? ?? 0
    ..date = DateTime.parse(m['date'] as String)
    ..rawText = m['rawText'] as String? ?? ''
    ..categoryId = m['categoryId'] as int?
    ..transactionId = m['transactionId'] as int?;

  Map<String, dynamic> _goalToMap(Goal g) => {
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

  Goal _goalFromMap(Map<String, dynamic> m) => Goal()
    ..id = m['id'] as int
    ..name = m['name'] as String? ?? ''
    ..targetCents = m['targetCents'] as int? ?? 0
    ..currentCents = m['currentCents'] as int? ?? 0
    ..iconName = m['iconName'] as String? ?? 'flag'
    ..colorValue = m['colorValue'] as int? ?? 0xFF4CAF50
    ..deadline = m['deadline'] == null
        ? null
        : DateTime.parse(m['deadline'] as String)
    ..monthlyContributionCents = m['monthlyContributionCents'] as int? ?? 0
    ..planMode = m['planMode'] as String? ?? 'contribution'
    ..sortOrder = m['sortOrder'] as int? ?? 0;

  Map<String, dynamic>? _settingsToMap(AppSettings? s) {
    if (s == null) return null;
    return {
      'themeMode': s.themeMode,
      'dynamicColor': s.dynamicColor,
      'amoled': s.amoled,
      'seedColorValue': s.seedColorValue,
      'enabledModules': s.enabledModules,
      'dashboardCards': s.dashboardCards,
      'totalBalanceAccountIds': s.totalBalanceAccountIds,
      'navSections': s.navSections,
      'alwaysShowNavLabels': s.alwaysShowNavLabels,
      'hideAmounts': s.hideAmounts,
    };
  }

  AppSettings _settingsFromMap(Map<String, dynamic> m) {
    final s = AppSettings()
      ..id = 0
      ..themeMode = m['themeMode'] as String? ?? 'system'
      ..dynamicColor = m['dynamicColor'] as bool? ?? true
      ..amoled = m['amoled'] as bool? ?? true
      ..seedColorValue = m['seedColorValue'] as int? ?? 0xFF2196F3
      ..enabledModules =
          (m['enabledModules'] as List<dynamic>? ?? []).cast<String>()
      ..dashboardCards =
          (m['dashboardCards'] as List<dynamic>? ?? []).cast<String>()
      ..totalBalanceAccountIds =
          (m['totalBalanceAccountIds'] as List<dynamic>? ?? []).cast<int>()
      ..alwaysShowNavLabels = m['alwaysShowNavLabels'] as bool? ?? false
      ..hideAmounts = m['hideAmounts'] as bool? ?? false;
    final nav = (m['navSections'] as List<dynamic>?)?.cast<String>();
    if (nav != null && nav.isNotEmpty) s.navSections = nav;
    return s;
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(isarProvider)),
);
