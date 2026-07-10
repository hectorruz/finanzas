import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';

import '../../../data/models/account.dart';
import '../../../data/models/category.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../data/models/transaction.dart';
import '../../../data/repositories/account_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/goal_repository.dart';
import '../../../data/repositories/merchant_rule_repository.dart';
import '../../../data/repositories/receipt_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../data/report_excel.dart';
import '../../../data/report_pdf.dart';
import '../../../data/report_service.dart';
import '../../receipts/ocr_service.dart';
import '../../receipts/receipt_image_store.dart';
import '../../receipts/receipt_save_service.dart';
import 'api_serializer.dart';

/// API de datos que consume la webapp de escritorio (bajo `/api/*`). Reutiliza
/// los repositorios de la app, así que todo pasa por el mismo camino de escritura
/// (sellado de sync, soft-delete) que la UI del móvil. Ya autenticada por token
/// en el servidor.
class DataApi {
  DataApi(this._isar)
      : _accounts = AccountRepository(_isar),
        _categories = CategoryRepository(_isar),
        _transactions = TransactionRepository(_isar),
        _recurring = RecurringRepository(_isar),
        _goals = GoalRepository(_isar),
        _receipts = ReceiptRepository(_isar),
        _receiptSaver = ReceiptSaveService(_isar),
        _merchantRules = MerchantRuleRepository(_isar),
        _reports = ReportService(_isar),
        _settings = SettingsRepository(_isar);

  final Isar _isar;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final RecurringRepository _recurring;
  final GoalRepository _goals;
  final ReceiptRepository _receipts;
  final ReceiptSaveService _receiptSaver;
  final MerchantRuleRepository _merchantRules;
  final ReportService _reports;
  final SettingsRepository _settings;
  final ApiSerializer _ser = const ApiSerializer();

  static bool handles(String path) => path.startsWith('/api/');

  Future<void> handle(HttpRequest req) async {
    final path = req.uri.path;
    final method = req.method;
    try {
      // Cuentas
      if (method == 'GET' && path == '/api/accounts') return _getAccounts(req);
      if (method == 'POST' && path == '/api/accounts') return _createAccount(req);
      final accId = _idFrom(path, '/api/accounts/');
      if (accId != null && method == 'PUT') return _updateAccount(req, accId);
      if (accId != null && method == 'DELETE') return _deleteAccount(req, accId);

      // Categorías
      if (method == 'GET' && path == '/api/categories') {
        return _getCategories(req);
      }
      if (method == 'POST' && path == '/api/categories') {
        return _createCategory(req);
      }
      final catId = _idFrom(path, '/api/categories/');
      if (catId != null && method == 'PUT') return _updateCategory(req, catId);
      if (catId != null && method == 'DELETE') return _deleteCategory(req, catId);

      // Movimientos
      if (method == 'GET' && path == '/api/transactions') {
        return _getTransactions(req);
      }
      if (method == 'POST' && path == '/api/transactions/batch') {
        return _batchTransactions(req);
      }
      if (method == 'POST' && path == '/api/transactions') {
        return _createTransaction(req);
      }
      final txId = _idFrom(path, '/api/transactions/');
      if (txId != null && method == 'PUT') return _updateTransaction(req, txId);
      if (txId != null && method == 'DELETE') {
        return _deleteTransaction(req, txId);
      }

      // Recurrentes
      if (method == 'GET' && path == '/api/recurring') return _getRecurring(req);
      if (method == 'POST' && path == '/api/recurring') {
        return _createRecurring(req);
      }
      final recId = _idFrom(path, '/api/recurring/');
      if (recId != null && method == 'PUT') return _updateRecurring(req, recId);
      if (recId != null && method == 'DELETE') {
        return _deleteRecurring(req, recId);
      }

      // Objetivos
      if (method == 'GET' && path == '/api/goals') return _getGoals(req);
      if (method == 'POST' && path == '/api/goals') return _createGoal(req);
      final goalId = _idFrom(path, '/api/goals/');
      if (goalId != null && method == 'PUT') return _updateGoal(req, goalId);
      if (goalId != null && method == 'DELETE') return _deleteGoal(req, goalId);

      // Tickets
      if (method == 'GET' && path == '/api/receipts') return _getReceipts(req);
      if (method == 'GET' &&
          path.startsWith('/api/receipts/') &&
          path.endsWith('/image')) {
        final idStr = path.substring(
            '/api/receipts/'.length, path.length - '/image'.length);
        final id = int.tryParse(idStr);
        if (id != null) return _getReceiptImage(req, id);
      }
      if (method == 'POST' && path == '/api/receipts') return _createReceipt(req);
      final receiptId = _idFrom(path, '/api/receipts/');
      if (receiptId != null && method == 'DELETE') {
        return _deleteReceipt(req, receiptId);
      }

      // OCR (la foto la sube el navegador, la procesa el móvil con ML Kit)
      if (method == 'POST' && path == '/api/ocr') return _ocr(req);

      // Informes descargables (el móvil genera el PDF/Excel con ReportService)
      if (method == 'POST' && path == '/api/report/pdf') {
        return _report(req, pdf: true);
      }
      if (method == 'POST' && path == '/api/report/excel') {
        return _report(req, pdf: false);
      }

      // Ajustes
      if (method == 'GET' && path == '/api/settings') return _getSettings(req);
      if (method == 'PUT' && path == '/api/settings') return _putSettings(req);

      _json(req, 404, {'error': 'not_found'});
    } catch (e) {
      _json(req, 500, {'error': '$e'});
    }
  }

  // --- Cuentas ---

  Future<void> _getAccounts(HttpRequest req) async {
    final accounts = await _accounts.all(includeArchived: true);
    final out = <Map<String, dynamic>>[];
    for (final a in accounts) {
      out.add(_ser.account(a, await _accounts.balanceCents(a.id)));
    }
    _jsonList(req, out);
  }

  Future<void> _createAccount(HttpRequest req) async {
    final body = await _readJson(req);
    final acc = Account()..name = '';
    _ser.applyAccount(acc, body);
    final id = await _accounts.save(acc);
    _json(req, 200, {'id': id});
  }

  Future<void> _updateAccount(HttpRequest req, int id) async {
    final existing = await _accounts.getById(id);
    if (existing == null) return _json(req, 404, {'error': 'no_account'});
    _ser.applyAccount(existing, await _readJson(req));
    await _accounts.save(existing);
    _json(req, 200, {'id': id});
  }

  Future<void> _deleteAccount(HttpRequest req, int id) async {
    await _accounts.delete(id);
    _json(req, 200, {'ok': true});
  }

  // --- Categorías ---

  Future<void> _getCategories(HttpRequest req) async {
    final cats = await _isar.categories
        .filter()
        .deletedAtIsNull()
        .sortBySortOrder()
        .findAll();
    _jsonList(req, cats.map(_ser.category).toList());
  }

  Future<void> _createCategory(HttpRequest req) async {
    final body = await _readJson(req);
    final cat = Category()..name = '';
    _ser.applyCategory(cat, body);
    final id = await _categories.save(cat);
    _json(req, 200, {'id': id});
  }

  Future<void> _updateCategory(HttpRequest req, int id) async {
    final existing = await _categories.getById(id);
    if (existing == null) return _json(req, 404, {'error': 'no_category'});
    _ser.applyCategory(existing, await _readJson(req));
    await _categories.save(existing);
    _json(req, 200, {'id': id});
  }

  Future<void> _deleteCategory(HttpRequest req, int id) async {
    await _categories.delete(id);
    _json(req, 200, {'ok': true});
  }

  // --- Movimientos ---

  Future<void> _getTransactions(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final filter = TransactionFilter(
      from: _date(q['from']),
      to: _date(q['to']),
      query: q['q'] ?? '',
      types: _typeSet(q['types']),
      accountIds: _intSet(q['accounts']),
      categoryIds: _intSet(q['categories']),
      minCents: _int(q['min']),
      maxCents: _int(q['max']),
      sort: enumByName(
          TransactionSort.values, q['sort'], TransactionSort.dateDesc),
    );
    final txns = await _transactions.query(filter);
    _jsonList(req, txns.map(_ser.transaction).toList());
  }

  Future<void> _createTransaction(HttpRequest req) async {
    final body = await _readJson(req);
    final txn = TransactionModel();
    _ser.applyTransaction(txn, body);
    final id = await _transactions.save(txn);
    _json(req, 200, {'id': id});
  }

  Future<void> _updateTransaction(HttpRequest req, int id) async {
    final existing = await _transactions.getById(id);
    if (existing == null) return _json(req, 404, {'error': 'no_transaction'});
    _ser.applyTransaction(existing, await _readJson(req));
    await _transactions.save(existing);
    _json(req, 200, {'id': id});
  }

  Future<void> _deleteTransaction(HttpRequest req, int id) async {
    await _transactions.delete(id); // soft-delete (tombstone)
    _json(req, 200, {'ok': true});
  }

  /// Acciones masivas (edición tipo Excel): `{op, ids, categoryId?, accountId?}`.
  Future<void> _batchTransactions(HttpRequest req) async {
    final body = await _readJson(req);
    final op = body['op'] as String? ?? '';
    final ids = _intList(body['ids']);
    switch (op) {
      case 'setCategory':
        await _transactions.bulkSetCategory(ids, body['categoryId'] as int?);
      case 'setAccount':
        final acc = body['accountId'] as int?;
        if (acc == null) return _json(req, 400, {'error': 'no_account'});
        await _transactions.bulkSetAccount(ids, acc);
      case 'delete':
        await _transactions.deleteMany(ids);
      default:
        return _json(req, 400, {'error': 'bad_op'});
    }
    _json(req, 200, {'ok': true, 'count': ids.length});
  }

  // --- Recurrentes ---

  Future<void> _getRecurring(HttpRequest req) async {
    final rules = await _isar.recurringRules
        .filter()
        .deletedAtIsNull()
        .sortByNextDate()
        .findAll();
    _jsonList(req, rules.map(_ser.recurring).toList());
  }

  Future<void> _createRecurring(HttpRequest req) async {
    final rule = RecurringRule()..name = '';
    _ser.applyRecurring(rule, await _readJson(req));
    final id = await _recurring.save(rule);
    await _recurring.materializeDue();
    _json(req, 200, {'id': id});
  }

  Future<void> _updateRecurring(HttpRequest req, int id) async {
    final existing = await _isar.recurringRules.get(id);
    if (existing == null) return _json(req, 404, {'error': 'no_recurring'});
    _ser.applyRecurring(existing, await _readJson(req));
    await _recurring.save(existing);
    await _recurring.materializeDue();
    _json(req, 200, {'id': id});
  }

  Future<void> _deleteRecurring(HttpRequest req, int id) async {
    await _recurring.delete(id);
    _json(req, 200, {'ok': true});
  }

  // --- Objetivos ---

  Future<void> _getGoals(HttpRequest req) async {
    final goals = await _isar.goals
        .filter()
        .deletedAtIsNull()
        .sortBySortOrder()
        .findAll();
    _jsonList(req, goals.map(_ser.goal).toList());
  }

  Future<void> _createGoal(HttpRequest req) async {
    final goal = Goal()..name = '';
    _ser.applyGoal(goal, await _readJson(req));
    final id = await _goals.save(goal);
    _json(req, 200, {'id': id});
  }

  Future<void> _updateGoal(HttpRequest req, int id) async {
    final existing = await _isar.goals.get(id);
    if (existing == null) return _json(req, 404, {'error': 'no_goal'});
    _ser.applyGoal(existing, await _readJson(req));
    await _goals.save(existing);
    _json(req, 200, {'id': id});
  }

  Future<void> _deleteGoal(HttpRequest req, int id) async {
    await _goals.delete(id);
    _json(req, 200, {'ok': true});
  }

  // --- Tickets ---

  Future<void> _getReceipts(HttpRequest req) async {
    final receipts = await _receipts.all();
    _jsonList(req, receipts.map(_ser.receipt).toList());
  }

  Future<void> _getReceiptImage(HttpRequest req, int id) async {
    final receipt = await _receipts.getById(id);
    final path = receipt?.imagePath ?? '';
    if (path.isEmpty) return _json(req, 404, {'error': 'no_image'});
    final file = File(path);
    if (!await file.exists()) return _json(req, 404, {'error': 'no_image'});
    final bytes = await file.readAsBytes();
    final lower = path.toLowerCase();
    final ct = lower.endsWith('.png')
        ? ContentType('image', 'png')
        : (lower.endsWith('.webp')
            ? ContentType('image', 'webp')
            : ContentType('image', 'jpeg'));
    req.response
      ..statusCode = 200
      ..headers.contentType = ct
      ..add(bytes);
    await req.response.close();
  }

  Future<void> _createReceipt(HttpRequest req) async {
    final body = await _readJson(req);
    final b64 = body['imageBase64'] as String?;
    var imagePath = '';
    final hasImage = b64 != null && b64.isNotEmpty;
    if (hasImage) {
      final ext = (body['imageExt'] as String?) ?? '.jpg';
      imagePath = await persistReceiptImageBytes(base64Decode(b64),
          extension: ext);
    }
    final result = await _receiptSaver.save(
      existingReceiptId: body['existingReceiptId'] as int?,
      merchant: (body['merchant'] as String? ?? '').trim(),
      totalCents: body['totalCents'] as int? ?? 0,
      date: body['date'] == null
          ? DateTime.now()
          : DateTime.parse(body['date'] as String),
      rawText: body['rawText'] as String? ?? '',
      categoryId: body['categoryId'] as int?,
      accountId: body['accountId'] as int?,
      createExpense: body['createExpense'] as bool? ?? true,
      imagePath: imagePath,
      updateImage: hasImage,
    );
    _json(req, 200,
        {'id': result.receiptId, 'transactionId': result.transactionId});
  }

  Future<void> _deleteReceipt(HttpRequest req, int id) async {
    final receipt = await _receipts.getById(id);
    if (receipt != null) {
      await deleteReceiptImage(receipt.imagePath);
      final withExpense = req.uri.queryParameters['expense'] == 'true';
      if (withExpense && receipt.transactionId != null) {
        await _transactions.delete(receipt.transactionId!);
      }
    }
    await _receipts.delete(id);
    _json(req, 200, {'ok': true});
  }

  /// OCR de una foto subida (base64). Corre ML Kit en el móvil y devuelve
  /// `ParsedReceipt` como JSON, con una sugerencia de categoría por memoria de
  /// comercio si existe.
  Future<void> _ocr(HttpRequest req) async {
    final body = await _readJson(req);
    final b64 = body['imageBase64'] as String?;
    if (b64 == null || b64.isEmpty) {
      return _json(req, 400, {'error': 'no_image'});
    }
    final ext = (body['imageExt'] as String?) ?? '.jpg';
    final tmp = await Directory.systemTemp.createTemp('finanzas_ocr');
    final file = File('${tmp.path}${Platform.pathSeparator}scan$ext');
    final ocr = OcrService();
    try {
      await file.writeAsBytes(base64Decode(b64));
      final parsed = await ocr.processImage(file.path);
      final suggestedCategoryId = parsed.merchant == null
          ? null
          : await _merchantRules.categoryFor(parsed.merchant!);
      _json(req, 200, {
        'merchant': parsed.merchant,
        'totalCents': parsed.totalCents,
        'date': parsed.date?.toIso8601String(),
        'suggestedCategoryId': suggestedCategoryId,
        'merchantConfident': parsed.merchantConfident,
        'totalConfident': parsed.totalConfident,
        'rawText': parsed.rawText,
      });
    } finally {
      ocr.dispose();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {/* best-effort */}
    }
  }

  // --- Informes ---

  /// Genera un informe con `ReportService` (mismo motor que el móvil) y
  /// devuelve los **bytes** para descarga directa. El cuerpo trae `from`, `to` y
  /// las claves de `ReportConfig` (las que falten usan sus valores por defecto).
  Future<void> _report(HttpRequest req, {required bool pdf}) async {
    final body = await _readJson(req);
    final from = body['from'] == null
        ? DateTime(DateTime.now().year, DateTime.now().month, 1)
        : DateTime.parse(body['from'] as String);
    final to = body['to'] == null
        ? DateTime.now()
        : DateTime.parse(body['to'] as String);
    final config = ReportConfig.decode(jsonEncode(body));
    final data = await _reports.build(config.toOptions(
      from: DateTime(from.year, from.month, from.day),
      to: DateTime(to.year, to.month, to.day, 23, 59, 59, 999),
    ));
    final file = pdf ? await buildReportPdf(data) : await buildReportExcel(data);
    try {
      final bytes = await file.readAsBytes();
      final name = pdf ? 'informe.pdf' : 'informe.xlsx';
      final ct = pdf
          ? ContentType('application', 'pdf')
          : ContentType('application',
              'vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      req.response
        ..statusCode = 200
        ..headers.contentType = ct
        ..headers.set('Content-Disposition', 'attachment; filename="$name"')
        ..add(bytes);
      await req.response.close();
    } finally {
      try {
        await file.delete();
      } catch (_) {/* best-effort */}
    }
  }

  // --- Ajustes ---

  Future<void> _getSettings(HttpRequest req) async {
    final s = await _settings.getOrCreate();
    _json(req, 200, _ser.settings(s));
  }

  Future<void> _putSettings(HttpRequest req) async {
    final body = await _readJson(req);
    await _settings.update((s) => _ser.applySettings(s, body));
    final s = await _settings.getOrCreate();
    _json(req, 200, _ser.settings(s));
  }

  // --- utilidades ---

  int? _idFrom(String path, String prefix) {
    if (!path.startsWith(prefix)) return null;
    return int.tryParse(path.substring(prefix.length));
  }

  DateTime? _date(String? s) => (s == null) ? null : DateTime.tryParse(s);
  int? _int(String? s) => (s == null) ? null : int.tryParse(s);

  Set<int> _intSet(String? csv) => (csv == null || csv.isEmpty)
      ? const {}
      : csv.split(',').map(int.tryParse).whereType<int>().toSet();

  List<int> _intList(dynamic v) =>
      (v as List<dynamic>? ?? const []).map((e) => e as int).toList();

  Set<TransactionType> _typeSet(String? csv) {
    if (csv == null || csv.isEmpty) return const {};
    final result = <TransactionType>{};
    for (final n in csv.split(',')) {
      for (final t in TransactionType.values) {
        if (t.name == n) {
          result.add(t);
          break;
        }
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    if (body.isEmpty) return {};
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  void _json(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    req.response.close();
  }

  void _jsonList(HttpRequest req, List<Map<String, dynamic>> body) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    req.response.close();
  }
}
