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

  int sortOrder = 0;

  Category();
}
