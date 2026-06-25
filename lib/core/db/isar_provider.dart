import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

/// Provider de la instancia de Isar.
///
/// Es un *placeholder* que lanza una excepción si se usa sin haber sido
/// sobreescrito. En `main()` se abre Isar de forma asíncrona y se inyecta la
/// instancia real mediante `ProviderScope(overrides: [...])`. Así evitamos un
/// `late Isar` global y mantenemos el grafo de dependencias testeable.
final isarProvider = Provider<Isar>(
  (ref) => throw UnimplementedError(
    'isarProvider debe sobreescribirse en ProviderScope con la instancia real.',
  ),
);
