import 'package:isar_community/isar.dart';

part 'merchant_rule.g.dart';

/// Memoria de correcciones del OCR: asocia un comercio (normalizado) con la
/// categoría que el usuario eligió, para que el próximo ticket del mismo
/// comercio se categorice solo.
///
/// Es la semilla del futuro motor de reglas de auto-categorización: cuando
/// exista, estas entradas deben poder alimentarlo. De momento es **estado local
/// del dispositivo** (no se sincroniza); las transacciones que produce sí.
@Collection(accessor: 'merchantRules')
class MerchantRule {
  Id id = Isar.autoIncrement;

  /// Comercio normalizado (minúsculas, espacios colapsados). Clave de búsqueda.
  @Index(unique: true, replace: true)
  late String merchant;

  /// Categoría que el usuario eligió la última vez para este comercio.
  int categoryId = 0;

  /// Cuántas veces se ha confirmado esta asociación (para pesar la confianza).
  int hits = 1;

  DateTime updatedAt = DateTime.now();

  MerchantRule();

  /// Normaliza un nombre de comercio para usarlo como clave.
  static String normalize(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
