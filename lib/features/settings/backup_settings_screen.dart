import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/isar_provider.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/settings_repository.dart';
import '../backup/backup_planner.dart';
import '../backup/backup_scheduler_service.dart';
import '../backup/backup_worker.dart';
import '../backup/google_drive_target.dart';
import '../backup/nextcloud_target.dart';

/// Ajustes de las copias de seguridad automáticas: activar, frecuencia
/// (diaria/semanal/mensual), destino, hora preferida, copia manual y estado de
/// la última copia. Todos los campos son **locales** de este dispositivo (no se
/// sincronizan ni se incluyen en el backup exportable).
class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final repo = ref.read(settingsRepositoryProvider);

    // Guarda un cambio y pone al día la tarea periódica de segundo plano.
    Future<void> updateAndReschedule(void Function(AppSettings) mutate) async {
      await repo.update(mutate);
      final s = await repo.getOrCreate();
      try {
        if (s.backupEnabled) {
          await registerBackupTask(
            requiresNetwork:
                s.backupDestinationEnum != BackupDestination.localFile,
          );
        } else {
          await cancelBackupTask();
        }
      } catch (_) {
        // WorkManager no disponible: el ajuste se guarda igual y la copia se
        // hará como red de seguridad al abrir/reanudar la app.
      }
    }

    final freq = settings.backupFrequencyEnum;
    final next = nextBackupTime(
      freq: freq,
      hour: settings.backupHour,
      minute: settings.backupMinute,
      lastRun: settings.backupLastRunAt,
      now: DateTime.now(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Copias de seguridad')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.backup_outlined),
            title: const Text('Copias automáticas'),
            subtitle: const Text(
                'Guarda una copia de tus datos cada cierto tiempo, en segundo '
                'plano.'),
            value: settings.backupEnabled,
            onChanged: (v) => updateAndReschedule((s) => s.backupEnabled = v),
          ),
          const Divider(),
          const _Header('Programación'),
          ListTile(
            enabled: settings.backupEnabled,
            leading: const Icon(Icons.event_repeat),
            title: const Text('Frecuencia'),
            subtitle: Text(_freqLabel(freq)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: settings.backupEnabled
                ? () => _pickFrequency(context, updateAndReschedule)
                : null,
          ),
          ListTile(
            enabled: settings.backupEnabled,
            leading: const Icon(Icons.schedule),
            title: const Text('Hora preferida'),
            subtitle: Text(
                '${_two(settings.backupHour)}:${_two(settings.backupMinute)} · '
                'próxima aprox.: ${DateFormat('d MMM, HH:mm', 'es_ES').format(next)}'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: settings.backupEnabled
                ? () => _pickTime(context, settings.backupHour,
                    settings.backupMinute, updateAndReschedule)
                : null,
          ),
          const Divider(),
          const _Header('Destino'),
          ListTile(
            enabled: settings.backupEnabled,
            leading: const Icon(Icons.save_outlined),
            title: const Text('Dónde guardar'),
            subtitle: Text(_destLabel(settings.backupDestinationEnum)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: settings.backupEnabled
                ? () => _pickDestination(context, updateAndReschedule)
                : null,
          ),
          if (settings.backupDestinationEnum == BackupDestination.nextcloud)
            _NextcloudFields(enabled: settings.backupEnabled),
          if (settings.backupDestinationEnum == BackupDestination.googleDrive)
            _GoogleDriveFields(enabled: settings.backupEnabled),
          const Divider(),
          const _Header('Estado'),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Última copia'),
            subtitle: Text(_lastStatus(settings.backupLastRunAt,
                settings.backupLastResult)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Hacer copia ahora'),
              onPressed: () => _runNow(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Haciendo copia…')));
    final result =
        await BackupSchedulerService(ref.read(isarProvider)).runNow();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(result.ok
          ? 'Copia realizada: ${result.filename}'
          : 'Error al hacer la copia: ${result.message}'),
    ));
  }

  Future<void> _pickFrequency(BuildContext context,
      Future<void> Function(void Function(AppSettings)) update) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in BackupFrequency.values)
              ListTile(
                title: Text(_freqLabel(f)),
                onTap: () {
                  update((s) => s.backupFrequency = f.name);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDestination(BuildContext context,
      Future<void> Function(void Function(AppSettings)) update) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: Text(_destLabel(BackupDestination.localFile)),
              onTap: () {
                update((s) => s.backupDestination =
                    BackupDestination.localFile.name);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(_destLabel(BackupDestination.nextcloud)),
              onTap: () {
                update((s) =>
                    s.backupDestination = BackupDestination.nextcloud.name);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_to_drive),
              title: Text(_destLabel(BackupDestination.googleDrive)),
              onTap: () {
                update((s) =>
                    s.backupDestination = BackupDestination.googleDrive.name);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    int hour,
    int minute,
    Future<void> Function(void Function(AppSettings)) update,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked != null) {
      await update((s) {
        s.backupHour = picked.hour;
        s.backupMinute = picked.minute;
      });
    }
  }

  static String _freqLabel(BackupFrequency f) => switch (f) {
        BackupFrequency.daily => 'Diaria',
        BackupFrequency.weekly => 'Semanal',
        BackupFrequency.monthly => 'Mensual',
      };

  static String _destLabel(BackupDestination d) => switch (d) {
        BackupDestination.localFile => 'Archivo local (en el móvil)',
        BackupDestination.googleDrive => 'Google Drive',
        BackupDestination.nextcloud => 'Servidor Nextcloud',
      };

  static String _lastStatus(DateTime? at, String result) {
    if (at == null && result.isEmpty) return 'Aún no se ha hecho ninguna copia';
    if (at == null) return result;
    final when = DateFormat('d MMM yyyy, HH:mm', 'es_ES').format(at);
    return result.isEmpty ? when : '$when\n$result';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Campos de conexión de Nextcloud (URL, usuario, contraseña de aplicación y
/// carpeta) + "Probar conexión". Guarda cada cambio en los ajustes locales
/// (nunca se exportan ni se sincronizan). Con estado propio para conservar el
/// texto de los controladores entre reconstrucciones del ListView.
class _NextcloudFields extends ConsumerStatefulWidget {
  const _NextcloudFields({required this.enabled});
  final bool enabled;

  @override
  ConsumerState<_NextcloudFields> createState() => _NextcloudFieldsState();
}

class _NextcloudFieldsState extends ConsumerState<_NextcloudFields> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _folder;
  bool _obscure = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(currentSettingsProvider);
    _url = TextEditingController(text: s.nextcloudBaseUrl);
    _user = TextEditingController(text: s.nextcloudUser);
    _pass = TextEditingController(text: s.nextcloudPassword);
    _folder = TextEditingController(text: s.nextcloudFolder);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _folder.dispose();
    super.dispose();
  }

  String get _folderOrDefault =>
      _folder.text.trim().isEmpty ? 'Finanzas' : _folder.text.trim();

  void _save() {
    ref.read(settingsRepositoryProvider).update((s) {
      s.nextcloudBaseUrl = _url.text.trim();
      s.nextcloudUser = _user.text.trim();
      s.nextcloudPassword = _pass.text;
      s.nextcloudFolder = _folderOrDefault;
    });
  }

  Future<void> _test() async {
    _save();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing = true);
    final target = NextcloudBackupTarget(
      baseUrl: _url.text.trim(),
      user: _user.text.trim(),
      password: _pass.text,
      folder: _folderOrDefault,
    );
    try {
      await target.testConnection();
      messenger.showSnackBar(
          const SnackBar(content: Text('Conexión correcta ✓')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _url,
            enabled: widget.enabled,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Dirección del servidor',
              hintText: 'https://nube.ejemplo.com',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _user,
            enabled: widget.enabled,
            autocorrect: false,
            onChanged: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Usuario',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pass,
            enabled: widget.enabled,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Contraseña de aplicación',
              helperText: 'Usa una contraseña de aplicación de Nextcloud',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _folder,
            enabled: widget.enabled,
            autocorrect: false,
            onChanged: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Carpeta',
              hintText: 'Finanzas',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: const Text('Probar conexión'),
            onPressed: widget.enabled && !_testing ? _test : null,
          ),
        ],
      ),
    );
  }
}

/// Conexión de la cuenta de Google para las copias en Drive: conectar/mostrar
/// email/desconectar + los pasos de configuración de Google Cloud (que hace el
/// usuario una única vez). El token lo gestiona `google_sign_in`; aquí solo se
/// guarda el email para mostrarlo (ajuste local, nunca exportado).
class _GoogleDriveFields extends ConsumerStatefulWidget {
  const _GoogleDriveFields({required this.enabled});
  final bool enabled;

  @override
  ConsumerState<_GoogleDriveFields> createState() => _GoogleDriveFieldsState();
}

class _GoogleDriveFieldsState extends ConsumerState<_GoogleDriveFields> {
  String? _email;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(currentSettingsProvider).googleDriveAccountEmail;
    _email = saved.isEmpty ? null : saved;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final client = await GoogleDriveAuth.silentAuthClient();
      final authorized = client != null;
      client?.close();
      if (!mounted) return;
      // Si ya no hay autorización silenciosa, olvidamos el email mostrado. Si la
      // hay, conservamos el email guardado (no lo re-consultamos en cada visita).
      if (!authorized) {
        setState(() => _email = null);
        _persist('');
      }
    } catch (_) {
      // google_sign_in no disponible (test / sin Play Services): sin cambios.
    }
  }

  void _persist(String email) {
    ref
        .read(settingsRepositoryProvider)
        .update((s) => s.googleDriveAccountEmail = email);
  }

  Future<void> _connect() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final email = await GoogleDriveAuth.connect();
      if (!mounted) return;
      setState(() => _email = email);
      _persist(email);
      messenger
          .showSnackBar(SnackBar(content: Text('Conectado como $email')));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('No se pudo conectar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await GoogleDriveAuth.disconnect();
    } catch (_) {}
    if (!mounted) return;
    _persist('');
    setState(() {
      _email = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = _email != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (connected)
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.account_circle),
                title: Text(_email!),
                subtitle: const Text('Cuenta conectada'),
                trailing: TextButton(
                  onPressed: _busy ? null : _disconnect,
                  child: const Text('Desconectar'),
                ),
              ),
            )
          else
            FilledButton.tonalIcon(
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_to_drive),
              label: const Text('Conectar cuenta de Google'),
              onPressed: widget.enabled && !_busy ? _connect : null,
            ),
          const SizedBox(height: 12),
          Text(
            'Configuración única en Google Cloud (la haces tú):\n'
            '1. Crea un proyecto en console.cloud.google.com.\n'
            '2. Activa la API de Google Drive.\n'
            '3. Configura la pantalla de consentimiento OAuth (tipo Externo) y '
            'añádete como usuario de prueba.\n'
            '4. Crea una credencial OAuth de tipo Android con el paquete '
            'com.example.finanzas y la huella SHA-1 del keystore de release '
            '(finanzas.keystore).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
