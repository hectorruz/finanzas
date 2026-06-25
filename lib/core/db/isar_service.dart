import 'package:isar_community/isar.dart';
import 'package:isar_community_flutter_libs/isar_flutter_libs.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/account.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/category.dart';
import '../../data/models/goal.dart';
import '../../data/models/holding.dart';
import '../../data/models/receipt.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/models/transaction.dart';

/// Esquemas registrados en la base de datos.
const List<CollectionSchema<dynamic>> kIsarSchemas = [
  AccountSchema,
  TransactionModelSchema,
  CategorySchema,
  RecurringRuleSchema,
  ReceiptSchema,
  HoldingSchema,
  GoalSchema,
  AppSettingsSchema,
];

/// Abre (o crea) la instancia de Isar en el directorio de documentos de la app.
///
/// Se invoca una sola vez en `main()` **antes** de `runApp` y la instancia
/// resultante se inyecta en el grafo de Riverpod mediante `isarProvider`.
class IsarService {
  static Future<Isar> open() async {
    final existing = Isar.getInstance();
    if (existing != null) return existing;

    final dir = await getApplicationDocumentsDirectory();
    return Isar.open(
      kIsarSchemas,
      directory: dir.path,
      inspector: false,
    );
  }
}
