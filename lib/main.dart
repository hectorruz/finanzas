import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/db/isar_provider.dart';
import 'core/db/isar_service.dart';
import 'data/repositories/recurring_repository.dart';
import 'data/seed_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Datos de localización para DateFormat en español.
  await initializeDateFormatting('es_ES', null);

  // Inicialización asíncrona de Isar ANTES de runApp (directiva de calidad #4):
  // así inyectamos la instancia real en el grafo de Riverpod mediante overrides
  // y evitamos cualquier `late Isar` global.
  final isar = await IsarService.open();

  // Datos por defecto la primera vez y materialización de recurrentes pendientes.
  await SeedService(isar).seedIfEmpty();
  await RecurringRepository(isar).materializeDue();

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const FinanzasApp(),
    ),
  );
}
