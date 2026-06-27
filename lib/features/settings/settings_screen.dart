import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router/app_router.dart';
import '../../data/backup_service.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../shared/widgets/icon_color_picker.dart';
import '../security/app_lock_service.dart';
import 'goals_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final repo = ref.read(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const _SectionHeader('Apariencia'),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Tema'),
            subtitle: Text(_themeLabel(settings.themeMode)),
            onTap: () => _pickTheme(context, ref),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.palette),
            title: const Text('Sincronizar color con el sistema'),
            subtitle: const Text('Material You'),
            value: settings.dynamicColor,
            onChanged: (v) => repo.update((s) => s.dynamicColor = v),
          ),
          if (!settings.dynamicColor)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 10,
                children: [
                  for (final color in kPaletteColors)
                    GestureDetector(
                      onTap: () =>
                          repo.update((s) => s.seedColorValue = color),
                      child: CircleAvatar(
                        backgroundColor: Color(color),
                        radius: 16,
                        child: settings.seedColorValue == color
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Tema oscuro AMOLED'),
            subtitle: const Text('Negro puro en pantallas OLED'),
            value: settings.amoled,
            onChanged: (v) => repo.update((s) => s.amoled = v),
          ),
          const Divider(),
          const _SectionHeader('Módulos'),
          SwitchListTile(
            secondary: const Icon(Icons.flag),
            title: const Text('Objetivos'),
            value: settings.goalsEnabled,
            onChanged: (v) => repo.update((s) {
              _toggleModule(s, AppModule.goals, v);
            }),
          ),
          const Divider(),
          const _SectionHeader('Organización'),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('Cuentas'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.accounts),
          ),
          ListTile(
            leading: const Icon(Icons.category),
            title: const Text('Categorías'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.categories),
          ),
          ListTile(
            leading: const Icon(Icons.autorenew),
            title: const Text('Movimientos recurrentes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.recurring),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_customize),
            title: const Text('Personalizar inicio'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.dashboardConfig),
          ),
          if (settings.goalsEnabled)
            ListTile(
              leading: const Icon(Icons.flag),
              title: const Text('Objetivos'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GoalsScreen()),
              ),
            ),
          const Divider(),
          const _SectionHeader('Seguridad'),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('Bloqueo de la app'),
            subtitle: const Text(
                'Pide tu huella o el PIN del teléfono al abrir la app'),
            value: settings.appLockEnabled,
            onChanged: (v) => _toggleAppLock(context, ref, v),
          ),
          const Divider(),
          const _SectionHeader('Datos'),
          ListTile(
            leading: const Icon(Icons.summarize),
            title: const Text('Generar informe'),
            subtitle: const Text('PDF o Excel de un tramo de fechas'),
            onTap: () => context.push(Routes.reports),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Exportar datos'),
            subtitle: const Text('Genera una copia en JSON'),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Importar datos'),
            subtitle: const Text('Reemplaza los datos actuales'),
            onTap: () => _import(context, ref),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever,
                color: Theme.of(context).colorScheme.error),
            title: Text('Borrar todos los datos',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => _wipe(context, ref),
          ),
          const SizedBox(height: 24),
          const Center(child: Text('Finanzas · v0.1.0')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _toggleModule(AppSettings s, AppModule module, bool enabled) {
    // Copia crecible: las listas que Isar deserializa pueden ser de longitud
    // fija, por lo que mutarlas in-place con add/remove lanzaría una excepción.
    final modules = [...s.enabledModules];
    modules.remove(module.name);
    if (enabled) modules.add(module.name);
    s.enabledModules = modules;
  }

  String _themeLabel(String mode) => switch (mode) {
        'light' => 'Claro',
        'dark' => 'Oscuro',
        _ => 'Según el sistema',
      };

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(settingsRepositoryProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in const {
            'system': 'Según el sistema',
            'light': 'Claro',
            'dark': 'Oscuro',
          }.entries)
            ListTile(
              title: Text(entry.value),
              onTap: () {
                repo.update((s) => s.themeMode = entry.key);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _toggleAppLock(
      BuildContext context, WidgetRef ref, bool enable) async {
    final repo = ref.read(settingsRepositoryProvider);
    final service = ref.read(appLockServiceProvider);

    // Activar/desactivar requiere autenticarse con la credencial del
    // dispositivo (huella o PIN del teléfono).
    if (enable && !await service.isDeviceSupported()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Configura una huella o un PIN en los ajustes del teléfono.'),
          ),
        );
      }
      return;
    }

    final ok = await service.authenticate();
    if (!ok) return; // cancelado o fallido: el switch vuelve a su sitio solo
    await repo.update((s) => s.appLockEnabled = enable);
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref.read(backupServiceProvider).exportToFile();
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Copia de seguridad Finanzas');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      'Importar datos',
      'Esto reemplazará todos los datos actuales. ¿Continuar?',
    );
    if (!confirmed) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      await ref.read(backupServiceProvider).importJson(content);
      await ref.read(recurringRepositoryProvider).materializeDue();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos importados correctamente.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e')),
        );
      }
    }
  }

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      'Borrar todos los datos',
      'Esta acción no se puede deshacer. ¿Seguro?',
    );
    if (!confirmed) return;
    await ref.read(backupServiceProvider).wipe();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos borrados.')),
      );
    }
  }

  Future<bool> _confirm(
      BuildContext context, String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
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
