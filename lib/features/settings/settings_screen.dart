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
            subtitle: const Text('Pide PIN al abrir o volver a la app'),
            value: settings.appLockConfigured,
            onChanged: (v) => _toggleAppLock(context, ref, v),
          ),
          if (settings.appLockConfigured) ...[
            ListTile(
              leading: const Icon(Icons.pin),
              title: const Text('Cambiar PIN'),
              onTap: () => _changePin(context, ref),
            ),
            Consumer(
              builder: (context, ref, _) {
                final available = ref.watch(biometricsAvailableProvider);
                if (available.valueOrNull != true) {
                  return const SizedBox.shrink();
                }
                return SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Desbloqueo con huella'),
                  subtitle: const Text('Usa la biometría además del PIN'),
                  value: settings.biometricUnlock,
                  onChanged: (v) =>
                      repo.update((s) => s.biometricUnlock = v),
                );
              },
            ),
          ],
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
    if (enable) {
      final pin = await _pinSetupDialog(context);
      if (pin == null) return; // cancelado: el switch vuelve a su sitio solo
      final salt = service.generateSalt();
      await repo.update((s) {
        s.appLockEnabled = true;
        s.pinSalt = salt;
        s.pinHash = service.hashPin(pin, salt);
      });
    } else {
      // Para desactivar el bloqueo hay que demostrar que se conoce el PIN.
      final settings = ref.read(currentSettingsProvider);
      final ok = await _verifyPinDialog(context, service, settings);
      if (!ok) return;
      await repo.update((s) {
        s.appLockEnabled = false;
        s.biometricUnlock = false;
        s.pinHash = '';
        s.pinSalt = '';
      });
    }
  }

  /// Pide el PIN actual y lo verifica. Devuelve `true` si es correcto.
  Future<bool> _verifyPinDialog(
    BuildContext context,
    AppLockService service,
    AppSettings settings,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Confirma tu PIN'),
            content: TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: 'PIN actual',
                counterText: '',
                errorText: error,
              ),
              onSubmitted: (_) => _submitVerify(
                  context, controller, service, settings, setState, (e) => error = e),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => _submitVerify(
                    context, controller, service, settings, setState, (e) => error = e),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      },
    );
    return result ?? false;
  }

  void _submitVerify(
    BuildContext context,
    TextEditingController controller,
    AppLockService service,
    AppSettings settings,
    void Function(void Function()) setState,
    void Function(String?) setError,
  ) {
    if (service.verifyPin(settings, controller.text)) {
      Navigator.pop(context, true);
    } else {
      setState(() => setError('PIN incorrecto'));
    }
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(settingsRepositoryProvider);
    final service = ref.read(appLockServiceProvider);
    final pin = await _pinSetupDialog(context);
    if (pin == null) return;
    final salt = service.generateSalt();
    await repo.update((s) {
      s.pinSalt = salt;
      s.pinHash = service.hashPin(pin, salt);
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN actualizado.')),
      );
    }
  }

  /// Pide un PIN de 4 dígitos y su confirmación. Devuelve el PIN o `null`.
  Future<String?> _pinSetupDialog(BuildContext context) {
    final firstController = TextEditingController();
    final secondController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Configura tu PIN'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: firstController,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'PIN (4 dígitos)',
                    counterText: '',
                  ),
                  validator: (v) => (v != null && v.length == 4)
                      ? null
                      : 'Introduce 4 dígitos',
                ),
                TextFormField(
                  controller: secondController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Repite el PIN',
                    counterText: '',
                  ),
                  validator: (v) => v == firstController.text
                      ? null
                      : 'Los PIN no coinciden',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, firstController.text);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
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
