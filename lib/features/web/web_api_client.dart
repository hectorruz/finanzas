import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../data/models/enums.dart';
import '../sync/net/sync_protocol.dart';
import 'web_models.dart';

/// Cliente HTTP de la webapp de escritorio contra la API del móvil. Reutiliza el
/// mismo emparejamiento por PIN que el sync (obtiene un token) y luego llama a
/// la API de datos `/api/*` con ese token.
class WebApiClient {
  WebApiClient({required this.baseUri, this.token, http.Client? client})
      : _client = client ?? http.Client();

  /// Origen del servidor del móvil, p. ej. `http://192.168.1.42:8422`.
  final Uri baseUri;
  String? token;
  final http.Client _client;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null) SyncProtocol.authHeader: SyncProtocol.bearer(token!),
      };

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(
        path: path,
        queryParameters: (query != null && query.isNotEmpty) ? query : null,
      );

  /// Empareja con el móvil usando el PIN; guarda y devuelve el token.
  Future<String> pair({
    required String pin,
    required String deviceId,
    required String displayName,
  }) async {
    final res = await _client.post(
      _uri(SyncProtocol.pairPath),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(encodePairRequest(
          pin: pin, deviceId: deviceId, displayName: displayName)),
    );
    _ok(res);
    token = (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
    return token!;
  }

  // --- Cuentas ---

  Future<List<AccountDto>> accounts() =>
      _list('/api/accounts', AccountDto.fromJson);

  Future<int> createAccount(AccountDto a) =>
      _create('/api/accounts', a.toJson());

  Future<void> updateAccount(int id, AccountDto a) =>
      _update('/api/accounts/$id', a.toJson());

  Future<void> deleteAccount(int id) => _delete('/api/accounts/$id');

  // --- Categorías ---

  Future<List<CategoryDto>> categories() =>
      _list('/api/categories', CategoryDto.fromJson);

  Future<int> createCategory(CategoryDto c) =>
      _create('/api/categories', c.toJson());

  Future<void> updateCategory(int id, CategoryDto c) =>
      _update('/api/categories/$id', c.toJson());

  Future<void> deleteCategory(int id) => _delete('/api/categories/$id');

  // --- Movimientos ---

  Future<List<TransactionDto>> transactions({
    DateTime? from,
    DateTime? to,
    String query = '',
    Set<TransactionType> types = const {},
    Set<int> accountIds = const {},
    Set<int> categoryIds = const {},
    int? minCents,
    int? maxCents,
    WebTxSort sort = WebTxSort.dateDesc,
  }) {
    return _list(
      '/api/transactions',
      TransactionDto.fromJson,
      query: {
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
        if (query.isNotEmpty) 'q': query,
        if (types.isNotEmpty) 'types': types.map((t) => t.name).join(','),
        if (accountIds.isNotEmpty) 'accounts': accountIds.join(','),
        if (categoryIds.isNotEmpty) 'categories': categoryIds.join(','),
        if (minCents != null) 'min': '$minCents',
        if (maxCents != null) 'max': '$maxCents',
        'sort': sort.name,
      },
    );
  }

  Future<int> createTransaction(TransactionDto tx) =>
      _create('/api/transactions', tx.toJson());

  Future<void> updateTransaction(int id, TransactionDto tx) =>
      _update('/api/transactions/$id', tx.toJson());

  Future<void> deleteTransaction(int id) => _delete('/api/transactions/$id');

  /// Acción masiva sobre varios movimientos (cambiar categoría/cuenta, borrar).
  Future<void> batchTransactions(
    String op,
    List<int> ids, {
    int? categoryId,
    int? accountId,
  }) async {
    final res = await _client.post(
      _uri('/api/transactions/batch'),
      headers: _headers,
      body: jsonEncode({
        'op': op,
        'ids': ids,
        if (categoryId != null) 'categoryId': categoryId,
        if (accountId != null) 'accountId': accountId,
      }),
    );
    _ok(res);
  }

  // --- Recurrentes ---

  Future<List<RecurringDto>> recurring() =>
      _list('/api/recurring', RecurringDto.fromJson);

  Future<int> createRecurring(RecurringDto r) =>
      _create('/api/recurring', r.toJson());

  Future<void> updateRecurring(int id, RecurringDto r) =>
      _update('/api/recurring/$id', r.toJson());

  Future<void> deleteRecurring(int id) => _delete('/api/recurring/$id');

  // --- Objetivos ---

  Future<List<GoalDto>> goals() => _list('/api/goals', GoalDto.fromJson);

  Future<int> createGoal(GoalDto g) => _create('/api/goals', g.toJson());

  Future<void> updateGoal(int id, GoalDto g) =>
      _update('/api/goals/$id', g.toJson());

  Future<void> deleteGoal(int id) => _delete('/api/goals/$id');

  // --- Tickets ---

  Future<List<ReceiptDto>> receipts() =>
      _list('/api/receipts', ReceiptDto.fromJson);

  /// Descarga los bytes de la imagen de un ticket (con token; se pinta con
  /// `Image.memory` porque un `<img>` no puede mandar la cabecera de auth).
  Future<Uint8List> receiptImage(int id) async {
    final res =
        await _client.get(_uri('/api/receipts/$id/image'), headers: _headers);
    _ok(res);
    return res.bodyBytes;
  }

  /// Procesa una foto con el OCR del móvil (ML Kit) y devuelve el resultado.
  Future<ParsedReceiptDto> ocr(Uint8List imageBytes,
      {String imageExt = '.jpg'}) async {
    final res = await _client.post(
      _uri('/api/ocr'),
      headers: _headers,
      body: jsonEncode({
        'imageBase64': base64Encode(imageBytes),
        'imageExt': imageExt,
      }),
    );
    _ok(res);
    return ParsedReceiptDto.fromJson((jsonDecode(res.body) as Map).cast());
  }

  /// Crea (o actualiza) un ticket, opcionalmente con foto y gasto vinculado.
  /// Devuelve el id del ticket.
  Future<int> createReceipt({
    int? existingReceiptId,
    required String merchant,
    required int totalCents,
    required DateTime date,
    String rawText = '',
    int? categoryId,
    int? accountId,
    bool createExpense = true,
    Uint8List? imageBytes,
    String imageExt = '.jpg',
  }) async {
    final res = await _client.post(
      _uri('/api/receipts'),
      headers: _headers,
      body: jsonEncode({
        if (existingReceiptId != null) 'existingReceiptId': existingReceiptId,
        'merchant': merchant,
        'totalCents': totalCents,
        'date': date.toIso8601String(),
        'rawText': rawText,
        'categoryId': categoryId,
        'accountId': accountId,
        'createExpense': createExpense,
        if (imageBytes != null) 'imageBase64': base64Encode(imageBytes),
        if (imageBytes != null) 'imageExt': imageExt,
      }),
    );
    _ok(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as int;
  }

  Future<void> deleteReceipt(int id, {bool withExpense = false}) async {
    final res = await _client.delete(
      _uri('/api/receipts/$id', {if (withExpense) 'expense': 'true'}),
      headers: _headers,
    );
    _ok(res);
  }

  // --- Informes ---

  /// Genera y descarga los bytes de un informe (`format` = 'pdf' | 'excel').
  /// `config` lleva `from`, `to` y las claves de secciones/opciones.
  Future<Uint8List> report(String format, Map<String, dynamic> config) async {
    final res = await _client.post(
      _uri('/api/report/$format'),
      headers: _headers,
      body: jsonEncode(config),
    );
    _ok(res);
    return res.bodyBytes;
  }

  // --- Ajustes ---

  Future<SettingsDto> getSettings() async {
    final res = await _client.get(_uri('/api/settings'), headers: _headers);
    _ok(res);
    return SettingsDto.fromJson((jsonDecode(res.body) as Map).cast());
  }

  /// Aplica un patch parcial de ajustes y devuelve el estado resultante.
  Future<SettingsDto> putSettings(Map<String, dynamic> patch) async {
    final res = await _client.put(_uri('/api/settings'),
        headers: _headers, body: jsonEncode(patch));
    _ok(res);
    return SettingsDto.fromJson((jsonDecode(res.body) as Map).cast());
  }

  void close() => _client.close();

  // --- helpers HTTP ---

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, String>? query,
  }) async {
    final res = await _client.get(_uri(path, query), headers: _headers);
    _ok(res);
    return (jsonDecode(res.body) as List)
        .map((e) => fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<int> _create(String path, Map<String, dynamic> body) async {
    final res =
        await _client.post(_uri(path), headers: _headers, body: jsonEncode(body));
    _ok(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as int;
  }

  Future<void> _update(String path, Map<String, dynamic> body) async {
    final res =
        await _client.put(_uri(path), headers: _headers, body: jsonEncode(body));
    _ok(res);
  }

  Future<void> _delete(String path) async {
    final res = await _client.delete(_uri(path), headers: _headers);
    _ok(res);
  }

  void _ok(http.Response res) {
    if (res.statusCode != 200) {
      throw WebApiException(res.statusCode, res.body);
    }
  }
}

class WebApiException implements Exception {
  WebApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'WebApiException($statusCode): $body';
}
