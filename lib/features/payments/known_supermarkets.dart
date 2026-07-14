/// Supermercados conocidos con **categoría por defecto "Alimentación"** y
/// nombre canónico de la tienda. Determinista y sin dependencias (Dart puro,
/// testeable aparte). Es solo un *fallback*: si el usuario define una regla
/// tienda → categoría propia, esa manda.
library;

/// Categoría de gasto por defecto de los supermercados conocidos. Debe coincidir
/// (ignorando mayúsculas) con una categoría sembrada por `SeedService`.
const kAlimentacionCategory = 'Alimentación';

class _Supermarket {
  const _Supermarket(this.canonicalName, this.keywords);
  final String canonicalName;
  final List<String> keywords;
}

const _supermarkets = <_Supermarket>[
  _Supermarket('Lidl', ['lidl']),
  _Supermarket('Mercadona', ['mercadona']),
  _Supermarket('Dia', ['dia']),
];

/// Si [merchant] es un supermercado conocido, devuelve su nombre canónico; si
/// no, `null`. El match es por **palabra completa** (o igualdad), nunca
/// substring, para no confundir "dia" dentro de "guardia"/"media"/"diamond".
String? canonicalSupermarket(String merchant) {
  final words = _words(merchant).toSet();
  for (final s in _supermarkets) {
    for (final kw in s.keywords) {
      if (words.contains(kw)) return s.canonicalName;
    }
  }
  return null;
}

List<String> _words(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^0-9a-záéíóúüñ]+'), ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .toList();
