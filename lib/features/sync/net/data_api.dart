import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';

import '../../../data/models/category.dart';
import '../../../data/models/transaction.dart';
import '../../../data/repositories/account_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import 'api_serializer.dart';

/// API de datos que consume la webapp de escritorio (bajo `/api/*`). Reutiliza
/// los repositorios de la app, así que todo pasa por el mismo camino de escritura
/// (sellado de sync, soft-delete) que la UI del móvil. Ya autenticada por token
/// en el servidor.
class DataApi {
  DataApi(this._isar)
      : _accounts = AccountRepository(_isar),
        _transactions = TransactionRepository(_isar);

  final Isar _isar;
  final AccountRepository _accounts;
  final TransactionRepository _transactions;
  final ApiSerializer _ser = const ApiSerializer();

  static bool handles(String path) => path.startsWith('/api/');

  Future<void> handle(HttpRequest req) async {
    final path = req.uri.path;
    final method = req.method;
    try {
      if (method == 'GET' && path == '/api/accounts') {
        return await _getAccounts(req);
      }
      if (method == 'GET' && path == '/api/categories') {
        return await _getCategories(req);
      }
      if (method == 'GET' && path == '/api/transactions') {
        return await _getTransactions(req);
      }
      if (method == 'POST' && path == '/api/transactions') {
        return await _createTransaction(req);
      }
      final txId = _idFrom(path, '/api/transactions/');
      if (txId != null && method == 'PUT') {
        return await _updateTransaction(req, txId);
      }
      if (txId != null && method == 'DELETE') {
        return await _deleteTransaction(req, txId);
      }
      _json(req, 404, {'error': 'not_found'});
    } catch (e) {
      _json(req, 500, {'error': '$e'});
    }
  }

  Future<void> _getAccounts(HttpRequest req) async {
    final accounts = await _accounts.all(includeArchived: true);
    final out = <Map<String, dynamic>>[];
    for (final a in accounts) {
      out.add(_ser.account(a, await _accounts.balanceCents(a.id)));
    }
    _jsonList(req, out);
  }

  Future<void> _getCategories(HttpRequest req) async {
    final cats = await _isar.categories
        .filter()
        .deletedAtIsNull()
        .sortBySortOrder()
        .findAll();
    _jsonList(req, cats.map(_ser.category).toList());
  }

  Future<void> _getTransactions(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final filter = TransactionFilter(
      from: _date(q['from']),
      to: _date(q['to']),
      query: q['q'] ?? '',
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
    final body = await _readJson(req);
    _ser.applyTransaction(existing, body);
    await _transactions.save(existing);
    _json(req, 200, {'id': id});
  }

  Future<void> _deleteTransaction(HttpRequest req, int id) async {
    await _transactions.delete(id); // soft-delete (tombstone)
    _json(req, 200, {'ok': true});
  }

  // --- utilidades ---

  int? _idFrom(String path, String prefix) {
    if (!path.startsWith(prefix)) return null;
    return int.tryParse(path.substring(prefix.length));
  }

  DateTime? _date(String? s) => (s == null) ? null : DateTime.tryParse(s);

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
