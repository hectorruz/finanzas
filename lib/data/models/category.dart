import 'package:isar_community/isar.dart';

import 'enums.dart';

part 'category.g.dart';

/// Categoría personalizable para clasificar ingresos o gastos.
@Collection(accessor: 'categories')
class Category {
  Id id = Isar.autoIncrement;

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
