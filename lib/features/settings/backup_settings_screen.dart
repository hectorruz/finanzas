import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/settings_repository.dart';
import '../backup/backup_planner.dart';
import '../backup/backup_retention.dart';
import '../backup/backup_scheduler_service.dart';
import '../backup/cloud_backup_provider.dart';
import '../backup/google_drive_auth.dart';

/// Ajustes de las copias de seguridad en la nube: proveedor, credenciales,
/// frecuencia, retención, copia manual, estado y restauración.
class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(currentSettingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final provider = s.backupProviderEnum;

    return Scaffold(
      appBar: AppBar(title: const Text('Copias en la nube')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Copias automáticas'),
            subtitle: const Text(
                'Sube una copia de tus datos según la frecuencia que elijas'),
            value: s.backupEnabled,
            onChanged: (v) async {
              await repo.update((x) {
                x.backupEnabled = v;
                // Al activar, ancla la serie hoy a la hora preferida y fuerza
                // una primera copia (lastRun a null) para validar la config ya.
                if (v && x.backupAnchorAt == null) {
                  final now = DateTime.now();
                  x.backupAnchorAt = DateTime(now.year, now.month, now.day,
                      x.backupHour, x.backupMinute);
                  x.backupLastRunAt = null;
                }
              });
              // Al activar, intenta la primera copia en el momento.
              if (v && context.mounted) {
                await _runNow(context, ref);
              }
            },
          ),
          const Divider(),

          // --- Proveedor ---
          const _Header('Proveedor'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Nextcloud'),
            trailing: provider == BackupProvider.nextcloud
                ? Icon(Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary)
                : const Icon(Icons.circle_outlined),
            onTap: () => repo
                .update((x) => x.backupProvider = BackupProvider.nextcloud.name),
          ),
          ListTile(
            leading: const Icon(Icons.add_to_drive_outlined),
            title: const Text('Google Drive'),
            trailing: provider == BackupProvider.googleDrive
                ? Icon(Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary)
                : const Icon(Icons.circle_outlined),
            onTap: () => repo.update(
                (x) => x.backupProvider = BackupProvider.googleDrive.name),
          ),
          const Divider(),

          // --- Credenciales, según proveedor ---
          if (provider == BackupProvider.nextcloud)
            _NextcloudSection(settings: s)
          else
            _DriveSection(settings: s),
          const Divider(),

          // --- Frecuencia ---
          const _Header('Frecuencia'),
          ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('Cada cuánto'),
            subtitle:
                Text(frequencyLabel(s.backupFrequencyEnum, s.backupEvery)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickFrequency(context, ref, s),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Hora preferida'),
            subtitle: Text(
                '${_two(s.backupHour)}:${_two(s.backupMinute)} · orientativa '
                '(se hace al abrir la app tras esa hora)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTime(context, ref, s),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('Solo con Wi-Fi'),
            subtitle: const Text('No usar datos móviles para subir la copia'),
            value: s.backupWifiOnly,
            onChanged: (v) => repo.update((x) => x.backupWifiOnly = v),
          ),
          const Divider(),

          // --- Retención ---
          const _Header('Retención'),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text('Conservar las últimas ${_clampKeep(s.backupKeepLast)} '
                'copias'),
            subtitle: Text(retentionHorizonLabel(s.backupFrequencyEnum,
                s.backupEvery, _clampKeep(s.backupKeepLast))),
          ),
          _RetentionSelector(current: _clampKeep(s.backupKeepLast)),
          const Divider(),

          // --- Acciones y estado ---
          const _Header('Estado'),
          _StatusTile(settings: s),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _runNow(context, ref),
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Copiar ahora'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _restore(context, ref),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restaurar'),
                  ),
                ),
              ],
            ),
          ),
          if (provider == BackupProvider.googleDrive)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Solo se ven las copias creadas por esta app. Si subiste un '
                'archivo a mano a Drive, no aparecerá aquí (pero puedes usar '
                '"Importar datos" desde Ajustes).',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --- Acciones ---

  Future<void> _runNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Subiendo copia…')));
    final result =
        await ref.read(backupSchedulerServiceProvider).runNow(notify: false);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(result.ok
          ? 'Copia subida correctamente.'
          : 'No se pudo copiar: ${result.message}'),
    ));
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final service = ref.read(backupSchedulerServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    List<BackupEntry> entries;
    try {
      entries = await service.listRemote();
    } catch (e) {
      final msg = e is CloudBackupException ? e.message : e.toString();
      messenger.showSnackBar(
          SnackBar(content: Text('No se pudo leer la nube: $msg')));
      return;
    }
    if (!context.mounted) return;
    if (entries.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No hay copias en la nube todavía.')));
      return;
    }

    final chosen = await showModalBottomSheet<BackupEntry>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Elige una copia para restaurar'),
              subtitle: Text('Se reemplazarán TODOS los datos actuales'),
            ),
            const Divider(),
            for (final e in entries)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(_backupDateLabel(e)),
                subtitle: Text(_sizeLabel(e.sizeBytes)),
                onTap: () => Navigator.pop(context, e),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Restaurar esta copia?'),
        content: Text(
            'Se borrarán todos los datos actuales y se sustituirán por los de '
            '${_backupDateLabel(chosen)}. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    messenger.showSnackBar(
        const SnackBar(content: Text('Restaurando…')));
    try {
      await service.restoreFrom(chosen);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
          content: Text('Datos restaurados. Reinicia la app si algo no se '
              'actualiza.')));
    } catch (e) {
      final msg = e is CloudBackupException ? e.message : e.toString();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
          SnackBar(content: Text('No se pudo restaurar: $msg')));
    }
  }

  Future<void> _pickFrequency(
      BuildContext context, WidgetRef ref, AppSettings s) async {
    final repo = ref.read(settingsRepositoryProvider);
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < kBackupPresets.length; i++)
              ListTile(
                title: Text(frequencyLabel(
                    kBackupPresets[i].freq, kBackupPresets[i].every)),
                trailing: presetFor(s.backupFrequencyEnum, s.backupEvery) == i
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, i),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Personalizada…'),
              onTap: () => Navigator.pop(context, -1),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice >= 0) {
      final preset = kBackupPresets[choice];
      await repo.update((x) {
        x.backupFrequency = preset.freq.name;
        x.backupEvery = preset.every;
      });
    } else if (context.mounted) {
      await _pickCustomFrequency(context, ref, s);
    }
  }

  Future<void> _pickCustomFrequency(
      BuildContext context, WidgetRef ref, AppSettings s) async {
    final repo = ref.read(settingsRepositoryProvider);
    var freq = s.backupFrequencyEnum;
    var every = s.backupEvery;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Frecuencia personalizada'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('Cada'),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 64,
                    child: TextFormField(
                      initialValue: '$every',
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (v) => every = int.tryParse(v) ?? 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButton<BackupFrequency>(
                value: freq,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                      value: BackupFrequency.daily, child: Text('días')),
                  DropdownMenuItem(
                      value: BackupFrequency.weekly, child: Text('semanas')),
                  DropdownMenuItem(
                      value: BackupFrequency.monthly, child: Text('meses')),
                ],
                onChanged: (v) => setState(() => freq = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (result == true) {
      await repo.update((x) {
        x.backupFrequency = freq.name;
        x.backupEvery = every < 1 ? 1 : every;
      });
    }
  }

  Future<void> _pickTime(
      BuildContext context, WidgetRef ref, AppSettings s) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.backupHour, minute: s.backupMinute),
    );
    if (picked == null) return;
    await ref.read(settingsRepositoryProvider).update((x) {
      x.backupHour = picked.hour;
      x.backupMinute = picked.minute;
      // Reancla conservando el día, para que cambiar la hora no cambie los días.
      if (x.backupAnchorAt != null) {
        x.backupAnchorAt =
            reanchor(x.backupAnchorAt!, picked.hour, picked.minute);
      }
    });
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

String _backupDateLabel(BackupEntry e) {
  // El nombre lleva el timestamp UTC; lo parseamos para mostrarlo en local.
  final match = RegExp(r'(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})Z')
      .firstMatch(e.name);
  if (match != null) {
    final dt = DateTime.parse(
            '${match.group(1)}T${match.group(2)}:${match.group(3)}:${match.group(4)}Z')
        .toLocal();
    return DateFormat('d MMM y, HH:mm', 'es').format(dt);
  }
  return e.name;
}

String _sizeLabel(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Fuerza el número de copias a conservar a un rango sano [1, 999]. Defensa en
/// profundidad frente al centinela de Isar (Int.MIN) en registros migrados desde
/// una versión previa: aunque la migración lo saneó ya, la UI nunca debe mostrar
/// ni guardar un valor absurdo.
int _clampKeep(int v) => v < 1 ? 1 : (v > 999 ? 999 : v);

// --- Selector de retención (botones + campo escribible) ---

class _RetentionSelector extends ConsumerStatefulWidget {
  const _RetentionSelector({required this.current});
  final int current;

  @override
  ConsumerState<_RetentionSelector> createState() => _RetentionSelectorState();
}

class _RetentionSelectorState extends ConsumerState<_RetentionSelector> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.current}');
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_RetentionSelector old) {
    super.didUpdateWidget(old);
    // Si el valor cambió por los botones (o la migración), y el campo no se está
    // editando, refleja el nuevo valor sin pisar lo que el usuario teclea.
    if (widget.current != old.current && !_focus.hasFocus) {
      _controller.text = '${widget.current}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save(int value) async {
    final v = _clampKeep(value);
    await ref
        .read(settingsRepositoryProvider)
        .update((x) => x.backupKeepLast = v);
    if (mounted && _controller.text != '$v') _controller.text = '$v';
  }

  void _commitField() {
    final parsed = int.tryParse(_controller.text.trim());
    _save(parsed ?? widget.current);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('Copias a conservar'),
          const Spacer(),
          IconButton.outlined(
            onPressed: widget.current > 1
                ? () => _save(widget.current - 1)
                : null,
            icon: const Icon(Icons.remove),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: Theme.of(context).textTheme.titleLarge,
              decoration: const InputDecoration(isDense: true),
              onEditingComplete: () {
                _commitField();
                _focus.unfocus();
              },
              onSubmitted: (_) => _commitField(),
              onTapOutside: (_) {
                _commitField();
                _focus.unfocus();
              },
            ),
          ),
          const SizedBox(width: 12),
          IconButton.outlined(
            onPressed: widget.current < 999
                ? () => _save(widget.current + 1)
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

// --- Sección Nextcloud ---

class _NextcloudSection extends ConsumerWidget {
  const _NextcloudSection({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(settingsRepositoryProvider);
    final config = settings.configFor(BackupProvider.nextcloud);

    // Como la config va serializada, editamos sobre copias y persistimos entera.
    Future<void> setConfig(BackupProviderConfig next) =>
        repo.update((x) => x.backupProviderConfigs = x.withBackupConfig(next));

    final isHttp = config.baseUrl.trim().startsWith('http://');

    return Column(
      children: [
        const _Header('Cuenta de Nextcloud'),
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('Dirección'),
          subtitle: Text(config.baseUrl.isEmpty
              ? 'Sin configurar'
              : config.baseUrl),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final v = await _editText(context,
                title: 'Dirección de Nextcloud',
                initial: config.baseUrl,
                hint: 'https://cloud.ejemplo.com');
            if (v != null) await setConfig(config.copyWith(baseUrl: v.trim()));
          },
        ),
        if (isHttp)
          const ListTile(
            leading: Icon(Icons.warning_amber, color: Colors.orange),
            title: Text('Conexión sin cifrar (http)',
                style: TextStyle(fontSize: 13)),
            subtitle: Text(
                'La contraseña viajaría en claro. Usa https salvo en tu LAN.',
                style: TextStyle(fontSize: 12)),
          ),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Usuario'),
          subtitle:
              Text(config.user.isEmpty ? 'Sin configurar' : config.user),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final v = await _editText(context,
                title: 'Usuario', initial: config.user);
            if (v != null) await setConfig(config.copyWith(user: v.trim()));
          },
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: const Text('Contraseña de aplicación'),
          subtitle: Text(config.password.isEmpty
              ? 'Sin configurar'
              : '•••••••• (guardada)'),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final v = await _editText(context,
                title: 'Contraseña de aplicación',
                initial: config.password,
                obscure: true,
                hint: 'Ajustes → Seguridad en Nextcloud');
            if (v != null) await setConfig(config.copyWith(password: v.trim()));
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Carpeta'),
          subtitle: Text(config.folder),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final v = await _editText(context,
                title: 'Carpeta', initial: config.folder);
            if (v != null && v.trim().isNotEmpty) {
              await setConfig(config.copyWith(folder: v.trim()));
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () => _testConnection(context, ref),
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Probar conexión'),
          ),
        ),
      ],
    );
  }

  Future<void> _testConnection(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Probando…')));
    final result = await ref
        .read(backupSchedulerServiceProvider)
        .testConnection(settings, provider: BackupProvider.nextcloud);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }
}

// --- Sección Google Drive ---

class _DriveSection extends ConsumerStatefulWidget {
  const _DriveSection({required this.settings});
  final AppSettings settings;

  @override
  ConsumerState<_DriveSection> createState() => _DriveSectionState();
}

class _DriveSectionState extends ConsumerState<_DriveSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(settingsRepositoryProvider);
    final config = widget.settings.configFor(BackupProvider.googleDrive);
    final connected = config.account.isNotEmpty;

    return Column(
      children: [
        const _Header('Cuenta de Google Drive'),
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(connected ? config.account : 'Sin conectar'),
          subtitle: Text(connected
              ? 'Conectada'
              : 'Necesario para subir copias a tu Drive'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final email =
                                await GoogleDriveAuth.instance.connect();
                            await repo.update((x) => x.backupProviderConfigs =
                                x.withBackupConfig(
                                    config.copyWith(account: email)));
                            messenger.showSnackBar(SnackBar(
                                content: Text('Conectado como $email')));
                          } catch (e) {
                            final msg = e is CloudBackupException
                                ? e.message
                                : e.toString();
                            messenger.showSnackBar(
                                SnackBar(content: Text(msg)));
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  icon: const Icon(Icons.login),
                  label: Text(connected ? 'Cambiar cuenta' : 'Conectar cuenta'),
                ),
              ),
              if (connected) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await GoogleDriveAuth.instance.disconnect();
                          await repo.update((x) => x.backupProviderConfigs =
                              x.withBackupConfig(config.copyWith(
                                  account: '', folderId: '')));
                        },
                  child: const Text('Desconectar'),
                ),
              ],
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Carpeta'),
          subtitle: Text(config.folder),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final v = await _editText(context,
                title: 'Carpeta', initial: config.folder);
            if (v != null && v.trim().isNotEmpty) {
              await repo.update((x) => x.backupProviderConfigs =
                  x.withBackupConfig(config.copyWith(folder: v.trim())));
            }
          },
        ),
      ],
    );
  }
}

// --- Estado de la última copia ---

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final last = settings.backupLastRunAt;
    final scheme = Theme.of(context).colorScheme;

    if (last == null) {
      return ListTile(
        leading: const Icon(Icons.cloud_off_outlined),
        title: const Text('Aún no hay ninguna copia'),
        subtitle: Text(settings.backupLastResult.isEmpty
            ? 'Activa las copias o pulsa "Copiar ahora"'
            : settings.backupLastResult),
      );
    }

    final age = DateTime.now().difference(last);
    // Umbral de "vieja": el doble de un periodo. Es la única señal visible de la
    // pega del disparo oportunista (si no abres la app, no hay copia).
    final period = retentionHorizon(
        settings.backupFrequencyEnum, settings.backupEvery, 1);
    final stale = age > period * 2;
    final failing = settings.backupConsecutiveFailures > 0;
    final color = (stale || failing) ? scheme.error : null;

    return ListTile(
      leading: Icon(
        failing
            ? Icons.error_outline
            : (stale ? Icons.warning_amber : Icons.cloud_done_outlined),
        color: color,
      ),
      title: Text('Última copia: ${_ago(age)}',
          style: TextStyle(color: color)),
      subtitle: Text(
        settings.backupLastResult.isEmpty
            ? DateFormat('d MMM y, HH:mm', 'es').format(last)
            : settings.backupLastResult,
        style: TextStyle(color: color),
      ),
    );
  }

  String _ago(Duration d) {
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
  }
}

// --- Helpers compartidos ---

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary)),
      );
}

Future<String?> _editText(
  BuildContext context, {
  required String title,
  required String initial,
  bool obscure = false,
  String? hint,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: obscure,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar')),
      ],
    ),
  );
}
