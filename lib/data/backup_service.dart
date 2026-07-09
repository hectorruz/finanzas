import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/db/isar_provider.dart';
import '../core/sync/syncable.dart';
import 'models/account.dart';
import 'models/app_settings.dart';
import 'models/category.dart';
import 'models/enums.dart';
import 'models/goal.dart';
import 'models/merchant_rule.dart';
import 'models/receipt.dart';
import 'models/recurring_rule.dart';
import 'models/transaction.dart';

/// Exporta e importa todos los datos de la app en formato JSON.
class BackupService {
  BackupService(this._isar);
  final Isar _isar;

  /// v2 añade los campos de sincronización (uuid/updatedAt/deletedAt) a cada
  /// entidad. Los backups v1 (sin esos campos) se importan sin problema: el
  /// mapa `_withSync` genera un uuid y usa defaults tolerantes.
  static const int _version = 2;

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

  /// Borra **solo** los datos sincronizables (las 6 colecciones de dominio y la
  /// memoria local de comercios), preservando `settings` (identidad/config de
  /// este dispositivo) y `syncPeers` (los emparejamientos). Se usa al emparejar
  /// con la opción "borrar datos de este dispositivo": deja el móvil limpio para
  /// adoptar los datos del principal sin duplicar los defaults sembrados.
  Future<void> wipeSyncableData() async {
    await _isar.writeTxn(() async {
      await _isar.accounts.clear();
      await _isar.categories.clear();
      await _isar.transactions.clear();
      await _isar.recurringRules.clear();
      await _isar.receipts.clear();
      await _isar.goals.clear();
      await _isar.merchantRules.clear();
    });
  }

  // --- Mapeos (toMap / fromMap) ---

  List<Map<String, dynamic>> _list(dynamic raw) =>
      (raw as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();

  static const Uuid _uuid = Uuid();

  /// Campos de sincronización comunes a toda entidad [Syncable], para mezclar
  /// (`...`) en cada `toMap`.
  Map<String, dynamic> _syncToMap(Syncable e) => {
        'uuid': e.uuid,
        'updatedAt': e.updatedAt.toIso8601String(),
        'deletedAt': e.deletedAt?.toIso8601String(),
      };

  /// Rellena los campos de sincronización de [e] desde el mapa [m] y devuelve la
  /// propia entidad (para encadenar en los `fromMap` con cuerpo de flecha).
  /// Si el backup es v1 (sin `uuid`), genera uno para no perder la identidad.
  T _withSync<T extends Syncable>(T e, Map<String, dynamic> m) {
    final uuid = m['uuid'] as String?;
    e.uuid = (uuid == null || uuid.isEmpty) ? _uuid.v4() : uuid;
    final updated = m['updatedAt'] as String?;
    e.updatedAt = updated == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.parse(updated);
    final deleted = m['deletedAt'] as String?;
    e.deletedAt = deleted == null ? null : DateTime.parse(deleted);
    return e;
  }

  Map<String, dynamic> _accountToMap(Account a) => {
        'id': a.id,
        ..._syncToMap(a),
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

  Account _accountFromMap(Map<String, dynamic> m) => _withSync(
      Account()
        ..id = m['id'] as int
        ..name = m['name'] as String
        ..type =
            enumByName(AccountType.values, m['type'] as String?, AccountType.bank)
        ..initialBalanceCents = m['initialBalanceCents'] as int? ?? 0
        ..currency = m['currency'] as String? ?? 'EUR'
        ..iconName = m['iconName'] as String? ?? 'account_balance'
        ..colorValue = m['colorValue'] as int? ?? 0xFF1976D2
        ..archived = m['archived'] as bool? ?? false
        ..includeInTotal = m['includeInTotal'] as bool? ?? true
        ..note = m['note'] as String? ?? ''
        ..parentId = m['parentId'] as int?
        ..sortOrder = m['sortOrder'] as int? ?? 0,
      m);

  Map<String, dynamic> _categoryToMap(Category c) => {
        'id': c.id,
        ..._syncToMap(c),
        'name': c.name,
        'kind': c.kind.name,
        'iconName': c.iconName,
        'colorValue': c.colorValue,
        'isDefault': c.isDefault,
        'parentId': c.parentId,
        'sortOrder': c.sortOrder,
      };

  Category _categoryFromMap(Map<String, dynamic> m) => _withSync(
      Category()
        ..id = m['id'] as int
        ..name = m['name'] as String
        ..kind = enumByName(
            CategoryKind.values, m['kind'] as String?, CategoryKind.expense)
        ..iconName = m['iconName'] as String? ?? 'category'
        ..colorValue = m['colorValue'] as int? ?? 0xFF9E9E9E
        ..isDefault = m['isDefault'] as bool? ?? false
        ..parentId = m['parentId'] as int?
        ..sortOrder = m['sortOrder'] as int? ?? 0,
      m);

  Map<String, dynamic> _transactionToMap(TransactionModel t) => {
        'id': t.id,
        ..._syncToMap(t),
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

  TransactionModel _transactionFromMap(Map<String, dynamic> m) => _withSync(
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
        ..receiptId = m['receiptId'] as int?,
      m);

  Map<String, dynamic> _recurringToMap(RecurringRule r) => {
        'id': r.id,
        ..._syncToMap(r),
        'name': r.name,
        'type': r.type.name,
        'amountCents': r.amountCents,
        'concept': r.concept,
        'frequency': r.frequency.name,
        'interval': r.interval,
        'nextDate': r.nextDate.toIso8601String(),
        'endDate': r.endDate?.toIso8601String(),
        'active': r.active,
        'notifyEnabled': r.notifyEnabled,
        'notifyDaysBefore': r.notifyDaysBefore,
        'notifyHour': r.notifyHour,
        'notifyMinute': r.notifyMinute,
        'accountId': r.accountId,
        'categoryId': r.categoryId,
      };

  RecurringRule _recurringFromMap(Map<String, dynamic> m) => _withSync(
      RecurringRule()
        ..id = m['id'] as int
        ..name = m['name'] as String? ?? ''
        ..type = enumByName(TransactionType.values, m['type'] as String?,
            TransactionType.expense)
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
        ..notifyEnabled = m['notifyEnabled'] as bool? ?? false
        ..notifyDaysBefore = m['notifyDaysBefore'] as int? ?? 0
        ..notifyHour = m['notifyHour'] as int? ?? 9
        ..notifyMinute = m['notifyMinute'] as int? ?? 0
        ..accountId = m['accountId'] as int? ?? 0
        ..categoryId = m['categoryId'] as int?,
      m);

  Map<String, dynamic> _receiptToMap(Receipt r) => {
        'id': r.id,
        ..._syncToMap(r),
        'imagePath': r.imagePath,
        'merchant': r.merchant,
        'totalCents': r.totalCents,
        'date': r.date.toIso8601String(),
        'rawText': r.rawText,
        'categoryId': r.categoryId,
        'transactionId': r.transactionId,
      };

  Receipt _receiptFromMap(Map<String, dynamic> m) => _withSync(
      Receipt()
        ..id = m['id'] as int
        ..imagePath = m['imagePath'] as String? ?? ''
        ..merchant = m['merchant'] as String? ?? ''
        ..totalCents = m['totalCents'] as int? ?? 0
        ..date = DateTime.parse(m['date'] as String)
        ..rawText = m['rawText'] as String? ?? ''
        ..categoryId = m['categoryId'] as int?
        ..transactionId = m['transactionId'] as int?,
      m);

  Map<String, dynamic> _goalToMap(Goal g) => {
        'id': g.id,
        ..._syncToMap(g),
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

  Goal _goalFromMap(Map<String, dynamic> m) => _withSync(
      Goal()
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
        ..sortOrder = m['sortOrder'] as int? ?? 0,
      m);

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
      'accountsCardIds': s.accountsCardIds,
      'balanceSubtotals': s.balanceSubtotals,
      'navSections': s.navSections,
      'alwaysShowNavLabels': s.alwaysShowNavLabels,
      'hideAmounts': s.hideAmounts,
      'dataVersion': s.dataVersion,
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
      ..accountsCardIds =
          (m['accountsCardIds'] as List<dynamic>? ?? []).cast<int>()
      ..balanceSubtotals =
          (m['balanceSubtotals'] as List<dynamic>? ?? []).cast<String>()
      ..alwaysShowNavLabels = m['alwaysShowNavLabels'] as bool? ?? false
      ..hideAmounts = m['hideAmounts'] as bool? ?? false
      ..dataVersion = m['dataVersion'] as int? ?? 0;
    final nav = (m['navSections'] as List<dynamic>?)?.cast<String>();
    if (nav != null && nav.isNotEmpty) s.navSections = nav;
    return s;
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(isarProvider)),
);
