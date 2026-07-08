import 'dart:convert';

import 'package:http/http.dart' as http;

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

  Future<List<AccountDto>> accounts() async {
    final res = await _client.get(_uri('/api/accounts'), headers: _headers);
    _ok(res);
    return (jsonDecode(res.body) as List)
        .map((e) => AccountDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<CategoryDto>> categories() async {
    final res = await _client.get(_uri('/api/categories'), headers: _headers);
    _ok(res);
    return (jsonDecode(res.body) as List)
        .map((e) => CategoryDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<TransactionDto>> transactions({
    DateTime? from,
    DateTime? to,
    String query = '',
  }) async {
    final res = await _client.get(
      _uri('/api/transactions', {
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
        if (query.isNotEmpty) 'q': query,
      }),
      headers: _headers,
    );
    _ok(res);
    return (jsonDecode(res.body) as List)
        .map((e) => TransactionDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<int> createTransaction(TransactionDto tx) async {
    final res = await _client.post(_uri('/api/transactions'),
        headers: _headers, body: jsonEncode(tx.toJson()));
    _ok(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as int;
  }

  Future<void> updateTransaction(int id, TransactionDto tx) async {
    final res = await _client.put(_uri('/api/transactions/$id'),
        headers: _headers, body: jsonEncode(tx.toJson()));
    _ok(res);
  }

  Future<void> deleteTransaction(int id) async {
    final res =
        await _client.delete(_uri('/api/transactions/$id'), headers: _headers);
    _ok(res);
  }

  void close() => _client.close();

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
