/// Destino Google Drive, por REST plano sobre `package:http`.
///
/// Se evita `googleapis` (paquete generado, enorme) porque son cuatro llamadas:
/// buscar/crear carpeta, listar, subir (multipart), descargar, borrar. El token
/// llega de fuera ([headersProvider]) para que esta clase se pueda testear con
/// un `http.Client` de mentira sin arrastrar `google_sign_in`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_backup_provider.dart';

/// Devuelve las cabeceras de autorización, o `null` si no se puede autorizar sin
/// interacción (en cuyo caso el proveedor lanza pidiendo reconectar).
typedef DriveHeadersProvider = Future<Map<String, String>?> Function();

class GoogleDriveBackupProvider implements CloudBackupProvider {
  GoogleDriveBackupProvider({
    required this.folder,
    required this.headersProvider,
    String folderId = '',
    http.Client? client,
    Uri? apiBase,
    Uri? uploadBase,
  })  : _folderId = folderId.isEmpty ? null : folderId,
        _client = client ?? http.Client(),
        _apiBase = apiBase ?? Uri.parse('https://www.googleapis.com/drive/v3'),
        _uploadBase = uploadBase ??
            Uri.parse('https://www.googleapis.com/upload/drive/v3');

  final String folder;
  final DriveHeadersProvider headersProvider;
  final http.Client _client;
  final Uri _apiBase;
  final Uri _uploadBase;

  String? _folderId;

  /// Id de la carpeta ya resuelto, para que el orquestador lo cachee en los
  /// ajustes y la próxima copia no la vuelva a buscar. `null` hasta la primera
  /// operación.
  String? get resolvedFolderId => _folderId;

  @override
  String get label => 'Google Drive';

  @override
  Future<void> testConnection() async {
    await _resolveFolder();
  }

  @override
  Future<void> upload(String filename, List<int> bytes) async {
    final headers = await _headers();
    final folderId = await _resolveFolder();
    // Subida multipart: metadatos JSON + contenido, en un solo POST.
    const boundary = 'finanzas_backup_boundary';
    final metadata = jsonEncode({
      'name': filename,
      'parents': [folderId],
    });
    final body = <int>[];
    void write(String s) => body.addAll(utf8.encode(s));
    write('--$boundary\r\n');
    write('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    write('$metadata\r\n');
    write('--$boundary\r\n');
    write('Content-Type: application/json\r\n\r\n');
    body.addAll(bytes);
    write('\r\n--$boundary--\r\n');

    final res = await _client.post(
      _uploadBase.replace(
        pathSegments: [..._uploadBase.pathSegments, 'files'],
        queryParameters: {'uploadType': 'multipart', 'fields': 'id,name'},
      ),
      headers: {
        ...headers,
        'content-type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );
    if (res.statusCode != 200) {
      throw _error('No se pudo subir la copia', res);
    }
  }

  @override
  Future<List<BackupEntry>> list() async {
    final headers = await _headers();
    final folderId = await _resolveFolder();
    final res = await _client.get(
      _apiBase.replace(
        pathSegments: [..._apiBase.pathSegments, 'files'],
        queryParameters: {
          'q': "'$folderId' in parents and trashed = false",
          'fields': 'files(id,name,modifiedTime,size)',
          'spaces': 'drive',
          'pageSize': '1000',
        },
      ),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw _error('No se pudieron listar las copias', res);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final files = (data['files'] as List<dynamic>? ?? const []);
    return files.map((f) {
      final m = f as Map<String, dynamic>;
      return BackupEntry(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        modifiedAt: DateTime.tryParse(m['modifiedTime'] as String? ?? ''),
        sizeBytes: int.tryParse(m['size'] as String? ?? ''),
      );
    }).toList();
  }

  @override
  Future<List<int>> download(BackupEntry entry) async {
    final headers = await _headers();
    final res = await _client.get(
      _apiBase.replace(
        pathSegments: [..._apiBase.pathSegments, 'files', entry.id],
        queryParameters: {'alt': 'media'},
      ),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw _error('No se pudo descargar la copia', res);
    }
    return res.bodyBytes;
  }

  @override
  Future<void> delete(BackupEntry entry) async {
    final headers = await _headers();
    final res = await _client.delete(
      _apiBase.replace(pathSegments: [..._apiBase.pathSegments, 'files', entry.id]),
      headers: headers,
    );
    if (res.statusCode != 204 && res.statusCode != 200 && res.statusCode != 404) {
      throw _error('No se pudo borrar la copia ${entry.name}', res);
    }
  }

  @override
  void close() => _client.close();

  Future<Map<String, String>> _headers() async {
    final h = await headersProvider();
    if (h == null) {
      throw CloudBackupException(
          'No hay acceso a Google Drive. Vuelve a conectar la cuenta.');
    }
    return h;
  }

  /// Busca la carpeta de la app por nombre en la raíz; si no existe, la crea.
  /// Con el scope `drive.file` solo se ven las carpetas que ha creado la app,
  /// así que la búsqueda por nombre no choca con carpetas ajenas homónimas.
  Future<String> _resolveFolder() async {
    if (_folderId != null) return _folderId!;
    final headers = await _headers();

    final res = await _client.get(
      _apiBase.replace(
        pathSegments: [..._apiBase.pathSegments, 'files'],
        queryParameters: {
          'q': "mimeType = 'application/vnd.google-apps.folder' and "
              "name = '${folder.replaceAll("'", r"\'")}' and trashed = false",
          'fields': 'files(id,name)',
          'spaces': 'drive',
        },
      ),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw _error('No se pudo abrir la carpeta "$folder"', res);
    }
    final files = (jsonDecode(res.body) as Map<String, dynamic>)['files']
        as List<dynamic>?;
    if (files != null && files.isNotEmpty) {
      return _folderId = (files.first as Map<String, dynamic>)['id'] as String;
    }

    final created = await _client.post(
      _apiBase.replace(
        pathSegments: [..._apiBase.pathSegments, 'files'],
        queryParameters: {'fields': 'id'},
      ),
      headers: {...headers, 'content-type': 'application/json'},
      body: jsonEncode({
        'name': folder,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );
    if (created.statusCode != 200) {
      throw _error('No se pudo crear la carpeta "$folder"', created);
    }
    return _folderId =
        (jsonDecode(created.body) as Map<String, dynamic>)['id'] as String;
  }

  CloudBackupException _error(String what, http.Response res) {
    switch (res.statusCode) {
      case 401:
      case 403:
        return CloudBackupException(
            '$what: Google Drive rechazó el acceso. Vuelve a conectar la cuenta.',
            statusCode: res.statusCode);
      case 404:
        return CloudBackupException('$what: no se encontró el fichero.',
            statusCode: res.statusCode);
      default:
        return CloudBackupException(what, statusCode: res.statusCode);
    }
  }
}
