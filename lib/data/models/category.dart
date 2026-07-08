import 'package:isar_community/isar.dart';

import '../../core/sync/syncable.dart';
import 'enums.dart';

part 'category.g.dart';

/// Categoría personalizable para clasificar ingresos o gastos.
@Collection(accessor: 'categories')
class Category implements Syncable {
  Id id = Isar.autoIncrement;

  /// Metadatos de sincronización (ver [Syncable]).
  @override
  @Index()
  String uuid = '';
  @override
  DateTime updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  DateTime? deletedAt;

  late String name;

  @Enumerated(EnumType.name)
  CategoryKind kind = CategoryKind.expense;

  String iconName = 'category';

  int colorValue = 0xFF9E9E9E;

  /// Marca las categorías creadas por defecto (siguen siendo editables/borrables).
  bool isDefault = false;

  /// Id de la categoría padre si es una subcategoría; `null` si es de primer
  /// nivel. Una subcategoría hereda el [kind] de su padre.
  int? parentId;

  int sortOrder = 0;

  Category();

  /// ¿Es una subcategoría (cuelga de otra)?
  @ignore
  bool get isSubcategory => parentId != null;
}

/// Separador usado para mostrar la ruta padre · hijo de una categoría.
const String kCategoryPathSeparator = ' · ';

/// Devuelve el nombre completo de la categoría [id] resolviendo la cadena de
/// padres con [byId], p. ej. `Alimentación · Casa` para una subcategoría.
/// Si la categoría no existe, devuelve [fallback].
String categoryFullName(
  int? id,
  Map<int, Category> byId, {
  String fallback = '',
}) {
  if (id == null) return fallback;
  final category = byId[id];
  if (category == null) return fallback;
  final parts = <String>[category.name];
  var parentId = category.parentId;
  // Guard contra ciclos accidentales en los datos.
  final seen = <int>{category.id};
  while (parentId != null && seen.add(parentId)) {
    final parent = byId[parentId];
    if (parent == null) break;
    parts.add(parent.name);
    parentId = parent.parentId;
  }
  return parts.reversed.join(kCategoryPathSeparator);
}
