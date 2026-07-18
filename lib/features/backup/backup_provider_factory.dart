/// Construye el [CloudBackupProvider] adecuado a partir de los ajustes.
library;

import 'package:http/http.dart' as http;

import '../../data/models/app_settings.dart';
import '../../data/models/enums.dart';
import 'cloud_backup_provider.dart';
import 'google_drive_auth.dart';
import 'google_drive_provider.dart';
import 'nextcloud_provider.dart';

/// Crea el proveedor del destino [provider] (o el activo en [settings] si no se
/// indica) con su configuración. El [client] se inyecta en los tests.
CloudBackupProvider providerFor(
  AppSettings settings, {
  BackupProvider? provider,
  http.Client? client,
}) {
  final target = provider ?? settings.backupProviderEnum;
  final config = settings.configFor(target);
  switch (target) {
    case BackupProvider.nextcloud:
      return NextcloudBackupProvider(
        baseUrl: config.baseUrl,
        user: config.user,
        password: config.password,
        folder: config.folder,
        client: client,
      );
    case BackupProvider.googleDrive:
      return GoogleDriveBackupProvider(
        folder: config.folder,
        folderId: config.folderId,
        headersProvider: () =>
            GoogleDriveAuth.instance.authHeaders(interactive: false),
        client: client,
      );
  }
}
