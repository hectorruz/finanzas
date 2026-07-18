/// Destino Nextcloud, por WebDAV plano sobre `package:http`.
///
/// No hace falta ninguna librería de Nextcloud: son cinco verbos (MKCOL, PUT,
/// PROPFIND, GET, DELETE) con autenticación Basic. La contraseña debe ser una
/// **contraseña de aplicación** (Ajustes → Seguridad en Nextcloud), no la de la
/// cuenta: se puede revocar sin cambiar la contraseña real y evita el 2FA.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_backup_provider.dart';

class NextcloudBackupProvider implements CloudBackupProvider {
  NextcloudBackupProvider({
    required String baseUrl,
    required this.user,
    required this.password,
    required this.folder,
    http.Client? client,
  })  : base = parseBaseUrl(baseUrl),
        _client = client ?? http.Client();

  final Uri base;
  final String user;
  final String password;
  final String folder;
  final http.Client _client;

  @override
  String get label => 'Nextcloud';

  /// Normaliza lo que teclea la persona: `cloud.example.com`,
  /// `https://cloud.example.com/`, `https://cloud.example.com/index.php/apps/…`.
  ///
  /// Si no hay esquema se asume **https**. Un `http://` explícito se respeta (hay
  /// quien tiene la instancia en la LAN), pero la UI avisa de que la contraseña
  /// viajaría en claro.
  static Uri parseBaseUrl(String raw) {
    var s = raw.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) {
      throw CloudBackupException('Falta la dirección de Nextcloud.');
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) {
      throw CloudBackupException('La dirección de Nextcloud no es válida: $raw');
    }
    return uri;
  }

  /// Raíz WebDAV del usuario: `<base>/remote.php/dav/files/<user>/<folder>`.
  Uri get folderUri => _join(base, [
        'remote.php',
        'dav',
        'files',
        user,
        ...folder.split('/').where((s) => s.isNotEmpty),
      ]);

  Uri _fileUri(String filename) => _join(folderUri, [filename]);

  static Uri _join(Uri uri, List<String> segments) => uri.replace(
      pathSegments: [
        ...uri.pathSegments.where((s) => s.isNotEmpty),
        ...segments,
      ]);

  Map<String, String> get _authHeaders => {
        'authorization':
            'Basic ${base64Encode(utf8.encode('$user:$password'))}',
      };

  @override
  Future<void> testConnection() async {
    _requireCredentials();
    await _ensureFolder();
  }

  @override
  Future<void> upload(String filename, List<int> bytes) async {
    _requireCredentials();
    await _ensureFolder();
    final res = await _send('PUT', _fileUri(filename),
        body: bytes, extraHeaders: {'content-type': 'application/json'});
    // 201 = creada, 204 = sobrescrita.
    if (res.statusCode != 201 && res.statusCode != 204 && res.statusCode != 200) {
      throw _error('No se pudo subir la copia', res);
    }
  }

  @override
  Future<List<BackupEntry>> list() async {
    _requireCredentials();
    await _ensureFolder();
    final res = await _send('PROPFIND', folderUri, extraHeaders: {
      'depth': '1',
      'content-type': 'application/xml',
    }, body: utf8.encode(_propfindBody));
    if (res.statusCode != 207) {
      throw _error('No se pudieron listar las copias', res);
    }
    return parsePropfind(utf8.decode(res.bodyBytes), folderUri.path);
  }

  @override
  Future<List<int>> download(BackupEntry entry) async {
    _requireCredentials();
    final res = await _send('GET', base.replace(path: entry.id));
    if (res.statusCode != 200) {
      throw _error('No se pudo descargar la copia', res);
    }
    return res.bodyBytes;
  }

  @override
  Future<void> delete(BackupEntry entry) async {
    _requireCredentials();
    final res = await _send('DELETE', base.replace(path: entry.id));
    if (res.statusCode != 204 && res.statusCode != 200 && res.statusCode != 404) {
      throw _error('No se pudo borrar la copia ${entry.name}', res);
    }
  }

  @override
  void close() => _client.close();

  void _requireCredentials() {
    if (user.isEmpty || password.isEmpty) {
      throw CloudBackupException(
          'Faltan el usuario o la contraseña de aplicación de Nextcloud.');
    }
  }

  /// Crea la carpeta si no existe. **405 significa "ya existe"**, no un error:
  /// tratarlo como fallo rompería todas las copias a partir de la segunda.
  Future<void> _ensureFolder() async {
    final res = await _send('MKCOL', folderUri);
    if (res.statusCode == 201 || res.statusCode == 405) return;
    throw _error('No se pudo abrir la carpeta "$folder"', res);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    List<int>? body,
    Map<String, String> extraHeaders = const {},
  }) async {
    final req = http.Request(method, uri)
      ..headers.addAll({..._authHeaders, ...extraHeaders});
    if (body != null) req.bodyBytes = body;
    try {
      final streamed = await _client.send(req);
      return http.Response.fromStream(streamed);
    } on CloudBackupException {
      rethrow;
    } catch (e) {
      throw CloudBackupException('No se pudo conectar con Nextcloud: $e');
    }
  }

  CloudBackupException _error(String what, http.Response res) {
    switch (res.statusCode) {
      case 401:
      case 403:
        return CloudBackupException(
            '$what: usuario o contraseña de aplicación incorrectos.',
            statusCode: res.statusCode);
      case 404:
        return CloudBackupException(
            '$what: no se encontró la ruta. ¿Es correcta la dirección?',
            statusCode: res.statusCode);
      case 507:
        return CloudBackupException('$what: no queda espacio en Nextcloud.',
            statusCode: res.statusCode);
      default:
        return CloudBackupException(what, statusCode: res.statusCode);
    }
  }

  static const _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:">'
      '<d:prop><d:getlastmodified/><d:getcontentlength/><d:resourcetype/></d:prop>'
      '</d:propfind>';
}

/// Extrae las entradas de un `multistatus` de PROPFIND.
///
/// Parseo a mano con expresiones regulares en vez de traer un parser de XML: la
/// respuesta la genera Nextcloud, la forma es fija y solo se leen tres campos.
/// Se descarta el `<d:response>` de la propia carpeta comparando la ruta con
/// [folderPath], y cualquier `<d:collection>` (subcarpetas).
List<BackupEntry> parsePropfind(String xml, String folderPath) {
  final entries = <BackupEntry>[];
  final responses = RegExp(
    r'<[a-zA-Z]*:?response[^>]*>(.*?)</[a-zA-Z]*:?response>',
    dotAll: true,
  ).allMatches(xml);

  String norm(String p) {
    var s = Uri.decodeFull(p);
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  final folder = norm(folderPath);

  for (final r in responses) {
    final block = r.group(1)!;
    final href = _tag(block, 'href');
    if (href == null) continue;
    final path = norm(href);
    if (path == folder) continue; // la carpeta misma
    if (RegExp(r'<[a-zA-Z]*:?collection\s*/?>').hasMatch(block)) continue;

    final name = Uri.decodeFull(path.split('/').last);
    if (name.isEmpty) continue;

    final lengthRaw = _tag(block, 'getcontentlength');
    entries.add(BackupEntry(
      id: path,
      name: name,
      modifiedAt: _parseHttpDate(_tag(block, 'getlastmodified')),
      sizeBytes: lengthRaw == null ? null : int.tryParse(lengthRaw),
    ));
  }
  return entries;
}

String? _tag(String block, String name) {
  final m = RegExp(
    '<[a-zA-Z]*:?$name[^>]*>(.*?)</[a-zA-Z]*:?$name>',
    dotAll: true,
  ).firstMatch(block);
  return m?.group(1)?.trim();
}

const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12, //
};

/// Parsea una fecha RFC 1123 ("Fri, 17 Jul 2026 03:00:00 GMT"), que es lo que
/// devuelve `getlastmodified`. Devuelve `null` si no casa: la fecha es
/// informativa (la rotación ordena por nombre), así que no merece lanzar.
DateTime? _parseHttpDate(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})')
      .firstMatch(raw);
  if (m == null) return null;
  final month = _months[m.group(2)];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(m.group(3)!),
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  ).toLocal();
}
