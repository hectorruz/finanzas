import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backup_target.dart';

/// Sube las copias a un servidor **Nextcloud** por WebDAV (`PUT`) con
/// autenticación `Basic` (se recomienda una *app password* de Nextcloud, no la
/// contraseña principal). Crea la carpeta destino con `MKCOL` si no existe y
/// rota (borra las más antiguas) por `keepLast` mediante `PROPFIND` + `DELETE`.
///
/// No aporta TLS propio: se apoya en el `https://` del servidor Nextcloud. Las
/// credenciales son **locales** de este dispositivo (nunca se exportan ni se
/// sincronizan).
class NextcloudBackupTarget implements BackupTarget {
  NextcloudBackupTarget({
    required String baseUrl,
    required this.user,
    required this.password,
    required String folder,
    this.keepLast = 10,
    http.Client? client,
  })  : _base = _parseBase(baseUrl),
        _folderSegments = folder
            .split('/')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        _client = client ?? http.Client();

  final String user;
  final String password;
  final int keepLast;
  final Uri _base;
  final List<String> _folderSegments;
  final http.Client _client;

  @override
  String get label => 'Nextcloud';

  static Uri _parseBase(String raw) {
    var s = raw.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    return Uri.parse(s);
  }

  Map<String, String> get _authHeaders => {
        'authorization':
            'Basic ${base64Encode(utf8.encode('$user:$password'))}',
      };

  /// Raíz WebDAV del usuario: `<base>/remote.php/dav/files/<user>/`. Conserva
  /// el posible subpath de una instalación bajo directorio (p. ej. `/nextcloud`).
  Uri _filesRoot() {
    final segments = <String>[
      ..._base.pathSegments.where((s) => s.isNotEmpty),
      'remote.php',
      'dav',
      'files',
      user,
    ];
    return _base.replace(pathSegments: segments);
  }

  Uri _fileUri(String filename) {
    final root = _filesRoot();
    return root.replace(pathSegments: [
      ...root.pathSegments,
      ..._folderSegments,
      filename,
    ]);
  }

  @override
  Future<void> upload(String filename, List<int> bytes) async {
    await _ensureFolder();
    final res = await _send(
      'PUT',
      _fileUri(filename),
      bodyBytes: Uint8List.fromList(bytes),
      contentType: 'application/json',
    );
    _ensureOk(res, 'subir la copia');
    await _rotate();
  }

  /// Comprueba las credenciales/carpeta subiendo y borrando un fichero de
  /// prueba minúsculo. Lanza con un mensaje legible si algo falla.
  Future<void> testConnection() async {
    await _ensureFolder();
    final probe = _fileUri('.finanzas_test');
    final put = await _send(
      'PUT',
      probe,
      bodyBytes: Uint8List.fromList(utf8.encode('ok')),
      contentType: 'text/plain',
    );
    _ensureOk(put, 'escribir el fichero de prueba');
    // Borrado best-effort: si no se puede limpiar, la conexión ya se validó.
    try {
      await _send('DELETE', probe);
    } catch (_) {}
  }

  /// Crea la carpeta destino (y cada nivel intermedio) con `MKCOL`. Un 405 o un
  /// 301 significan que ya existe: no es un error.
  Future<void> _ensureFolder() async {
    final root = _filesRoot();
    final acc = <String>[...root.pathSegments];
    for (final segment in _folderSegments) {
      acc.add(segment);
      final res = await _send('MKCOL', root.replace(pathSegments: [...acc]));
      final code = res.statusCode;
      final ok = code == 201 || code == 405 || code == 301 || code == 200;
      if (!ok) {
        _ensureOk(res, 'crear la carpeta "${_folderSegments.join('/')}"');
      }
    }
  }

  /// Conserva como mucho [keepLast] copias en la carpeta remota. Best-effort:
  /// cualquier fallo aquí no invalida la copia ya subida.
  Future<void> _rotate() async {
    if (keepLast <= 0) return;
    try {
      final folder = _filesRoot().replace(pathSegments: [
        ..._filesRoot().pathSegments,
        ..._folderSegments,
      ]);
      final res = await _send(
        'PROPFIND',
        folder,
        body: '<?xml version="1.0"?>'
            '<d:propfind xmlns:d="DAV:"><d:prop><d:getlastmodified/>'
            '</d:prop></d:propfind>',
        contentType: 'application/xml',
        headers: const {'depth': '1'},
      );
      if (res.statusCode != 207) return;
      // Nombres de nuestras copias, ordenados (el nombre lleva la fecha ISO, que
      // ordena igual cronológica que lexicográficamente). El href viene
      // percent-encoded; lo decodificamos para comparar y para reconstruir la
      // URL de borrado lo resolvemos tal cual contra el origen.
      final hrefs = RegExp(r'<[dD]:href>([^<]+)</[dD]:href>')
          .allMatches(res.body)
          .map((m) => m.group(1)!)
          .where((h) {
        final name = Uri.decodeComponent(h.split('/').last);
        return name.startsWith('finanzas_backup_') && name.endsWith('.json');
      }).toList()
        ..sort((a, b) => Uri.decodeComponent(a.split('/').last)
            .compareTo(Uri.decodeComponent(b.split('/').last)));
      final excess = hrefs.length - keepLast;
      for (var i = 0; i < excess; i++) {
        try {
          await _send('DELETE', _filesRoot().resolve(hrefs[i]));
        } catch (_) {}
      }
    } catch (_) {
      // Rotación best-effort.
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Uint8List? bodyBytes,
    String? body,
    String? contentType,
    Map<String, String> headers = const {},
  }) async {
    final req = http.Request(method, uri);
    req.headers.addAll(_authHeaders);
    req.headers.addAll(headers);
    if (contentType != null) req.headers['content-type'] = contentType;
    if (bodyBytes != null) req.bodyBytes = bodyBytes;
    if (body != null) req.body = body;
    final streamed = await _client.send(req);
    return http.Response.fromStream(streamed);
  }

  void _ensureOk(http.Response res, String action) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    final detail = res.statusCode == 401
        ? 'usuario o contraseña incorrectos'
        : res.reasonPhrase ?? '';
    throw Exception('No se pudo $action (HTTP ${res.statusCode} $detail)');
  }
}
