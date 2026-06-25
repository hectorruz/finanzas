import 'package:isar_community/isar.dart';

part 'goal.g.dart';

/// Objetivo de ahorro configurable (módulo opcional del dashboard).
@Collection(accessor: 'goals')
class Goal {
  Id id = Isar.autoIncrement;

  late String name;

  /// Cantidad objetivo en céntimos.
  int targetCents = 0;

  /// Cantidad acumulada en céntimos.
  int currentCents = 0;

  String iconName = 'flag';

  int colorValue = 0xFF4CAF50;

  DateTime? deadline;

  int sortOrder = 0;

  Goal();

  /// Progreso entre 0.0 y 1.0.
  @ignore
  double get progress {
    if (targetCents <= 0) return 0;
    return (currentCents / targetCents).clamp(0.0, 1.0);
  }
}
