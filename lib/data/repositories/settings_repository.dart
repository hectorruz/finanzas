import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../models/app_settings.dart';
import '../models/enums.dart';

class SettingsRepository {
  SettingsRepository(this._isar);
  final Isar _isar;

  static const int _id = 0;

  /// Lee los ajustes; si no existen, crea y persiste los valores por defecto.
  Future<AppSettings> getOrCreate() async {
    final existing = await _isar.settings.get(_id);
    if (existing != null) return existing;
    final defaults = AppSettings()..id = _id;
    await _isar.writeTxn(() => _isar.settings.put(defaults));
    return defaults;
  }

  Stream<AppSettings> watch() async* {
    yield await getOrCreate();
    yield* _isar.settings
        .watchObject(_id, fireImmediately: false)
        .where((s) => s != null)
        .cast<AppSettings>();
  }

  Future<void> save(AppSettings settings) async {
    settings.id = _id;
    await _isar.writeTxn(() => _isar.settings.put(settings));
  }

  /// Aplica una mutación sobre los ajustes actuales y persiste.
  Future<void> update(void Function(AppSettings) mutate) async {
    final current = await getOrCreate();
    mutate(current);
    await save(current);
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(isarProvider)),
);

/// Ajustes reactivos. Mientras carga el primer valor se exponen los defaults.
final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

/// Acceso síncrono cómodo a los ajustes (con defaults mientras carga).
final currentSettingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(settingsProvider).maybeWhen(
        data: (s) => s,
        orElse: AppSettings.new,
      );
});

/// ThemeMode derivado de los ajustes.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(currentSettingsProvider).themeMode;
  return enumByName(
    ThemeMode.values,
    mode,
    ThemeMode.system,
  );
});
