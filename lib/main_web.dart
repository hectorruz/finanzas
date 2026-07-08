import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'features/web/web_app.dart';

/// Punto de entrada de la **webapp de escritorio** (target web). Es una app
/// aparte de la del móvil: no abre Isar ni monta `FinanzasApp`; habla con el
/// móvil por HTTP a través de `WebApiClient`.
///
/// Compilar con: `flutter build web -t lib/main_web.dart`
/// (o `flutter run -d chrome -t lib/main_web.dart` para desarrollo).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES', null);
  runApp(const ProviderScope(child: WebApp()));
}
