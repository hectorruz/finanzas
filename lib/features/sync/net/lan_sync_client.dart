import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/entity_change.dart';
import 'sync_protocol.dart';

class PairResult {
  PairResult({required this.token, required this.deviceId, required this.displayName});
  final String token;
  final String deviceId;
  final String displayName;
}

class ChangelogResult {
  ChangelogResult({required this.sessionId, required this.summary});
  final String sessionId;
  final Map<String, int> summary;
}

class SessionResult {
  SessionResult({required this.status, this.authoritative, this.newWatermark});
  final SyncSessionStatus status;
  final List<EntityChange>? authoritative;
  final DateTime? newWatermark;
}

/// Cliente HTTP del vinculado hacia el servidor del admin en la LAN.
class LanSyncClient {
  LanSyncClient({required this.host, required this.port, this.token, http.Client? client})
      : _client = client ?? http.Client();

  final String host;
  final int port;
  String? token;
  final http.Client _client;

  Uri _uri(String path) => Uri(scheme: 'http', host: host, port: port, path: path);

  Map<String, String> get _authHeaders => {
        'content-type': 'application/json',
        if (token != null) SyncProtocol.authHeader: SyncProtocol.bearer(token!),
      };

  /// Empareja con el admin usando el PIN. Guarda y devuelve el token.
  Future<PairResult> pair({
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
    _ensureOk(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    token = m['token'] as String;
    return PairResult(
      token: token!,
      deviceId: m['deviceId'] as String,
      displayName: m['displayName'] as String? ?? 'Dispositivo',
    );
  }

  /// Envía el changelog propio y obtiene el id de la sesión de revisión abierta
  /// en el admin.
  Future<ChangelogResult> pushChangelog({
    required String deviceId,
    required List<EntityChange> changes,
  }) async {
    final res = await _client.post(
      _uri(SyncProtocol.changelogPath),
      headers: _authHeaders,
      body: jsonEncode(
          encodeChangelogRequest(deviceId: deviceId, changes: changes)),
    );
    _ensureOk(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return ChangelogResult(
      sessionId: m['sessionId'] as String,
      summary: (m['summary'] as Map?)?.map((k, v) => MapEntry('$k', v as int)) ??
          const {},
    );
  }

  Future<SessionResult> pollSession(String sessionId) async {
    final res =
        await _client.get(_uri(SyncProtocol.sessionPath(sessionId)), headers: _authHeaders);
    _ensureOk(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final status = SyncSessionStatus.values
        .firstWhere((s) => s.name == m['status'], orElse: () => SyncSessionStatus.pending);
    return SessionResult(
      status: status,
      authoritative:
          m['authoritative'] == null ? null : decodeChanges(m['authoritative']),
      newWatermark: m['newWatermark'] == null
          ? null
          : DateTime.parse(m['newWatermark'] as String),
    );
  }

  void close() => _client.close();

  void _ensureOk(http.Response res) {
    if (res.statusCode == 200) return;
    throw LanSyncException(res.statusCode, res.body);
  }
}

class LanSyncException implements Exception {
  LanSyncException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'LanSyncException($statusCode): $body';
}
