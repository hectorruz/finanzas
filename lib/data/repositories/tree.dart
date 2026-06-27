// Utilidades para aplanar jerarquías padre/hijo de anidamiento ilimitado
// (subcategorías dentro de subcategorías, subcuentas dentro de subcuentas…).

/// Un nodo aplanado junto con su profundidad (0 = primer nivel).
class TreeEntry<T> {
  const TreeEntry(this.value, this.depth);
  final T value;
  final int depth;
}

/// Aplana una lista de entidades con relación padre/hijo en un recorrido en
/// profundidad, respetando el orden de entrada en cada nivel. Las entidades
/// cuyo padre no esté en la lista se tratan como de primer nivel. Es seguro
/// frente a ciclos accidentales (cada nodo se visita una sola vez).
List<TreeEntry<T>> flattenTree<T>(
  List<T> all, {
  required int Function(T) idOf,
  required int? Function(T) parentIdOf,
}) {
  final ids = all.map(idOf).toSet();
  final byParent = <int?, List<T>>{};
  for (final item in all) {
    final p = parentIdOf(item);
    final key = (p != null && ids.contains(p)) ? p : null;
    byParent.putIfAbsent(key, () => []).add(item);
  }
  final result = <TreeEntry<T>>[];
  final visited = <int>{};
  void visit(T node, int depth) {
    if (!visited.add(idOf(node))) return;
    result.add(TreeEntry(node, depth));
    for (final child in byParent[idOf(node)] ?? const []) {
      visit(child, depth + 1);
    }
  }

  for (final root in byParent[null] ?? const []) {
    visit(root, 0);
  }
  return result;
}
