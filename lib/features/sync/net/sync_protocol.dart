import '../model/entity_change.dart';

/// Contrato de red del sync LAN. El transporte es HTTP plano sobre la red local:
/// **no va cifrado**, así que toda petición (menos el emparejamiento) exige el
/// token de emparejamiento en la cabecera `Authorization: Bearer <token>`. En
/// una red doméstica es aceptable; queda la puerta abierta a TLS autofirmado.
class SyncProtocol {
  static const int defaultPort = 8422;

  /// Emparejamiento: sin token, autenticado por PIN de 6 dígitos.
  static const pairPath = '/pair';

  /// El vinculado envía su changelog; el admin abre una sesión de revisión.
  static const changelogPath = '/sync/changelog';

  /// El vinculado sondea el estado de la sesión hasta que el admin confirma.
  static String sessionPath(String id) => '/sync/session/$id';

  static const authHeader = 'authorization';
  static String bearer(String token) => 'Bearer $token';
  static String? tokenFromHeader(String? header) {
    if (header == null) return null;
    const p = 'Bearer ';
    return header.startsWith(p) ? header.substring(p.length) : header;
  }
}

/// Estado de una sesión de sincronización vista por el vinculado.
enum SyncSessionStatus { pending, ready, rejected }

// --- Serialización de payloads ---

Map<String, dynamic> encodePairRequest({
  required String pin,
  required String deviceId,
  required String displayName,
}) =>
    {'pin': pin, 'deviceId': deviceId, 'displayName': displayName};

Map<String, dynamic> encodePairResponse({
  required String token,
  required String deviceId,
  required String displayName,
}) =>
    {'token': token, 'deviceId': deviceId, 'displayName': displayName};

Map<String, dynamic> encodeChangelogRequest({
  required String deviceId,
  required List<EntityChange> changes,
}) =>
    {
      'deviceId': deviceId,
      'changes': changes.map((c) => c.toJson()).toList(),
    };

List<EntityChange> decodeChanges(dynamic raw) =>
    (raw as List<dynamic>? ?? const [])
        .map((e) => EntityChange.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

Map<String, dynamic> encodeSessionResponse({
  required SyncSessionStatus status,
  List<EntityChange>? authoritative,
  DateTime? newWatermark,
  Map<String, int>? summary,
}) =>
    {
      'status': status.name,
      if (summary != null) 'summary': summary,
      if (authoritative != null)
        'authoritative': authoritative.map((c) => c.toJson()).toList(),
      if (newWatermark != null) 'newWatermark': newWatermark.toIso8601String(),
    };
