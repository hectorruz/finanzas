import 'package:isar_community/isar.dart';

part 'holding.g.dart';

/// Factor de escalado para la cantidad de acciones (soporta hasta 6 decimales).
const int kQuantityScale = 1000000;

/// Una posición de inversión (acción o ETF) dentro de la cartera.
///
/// - El dinero se guarda en **céntimos** (`buyPriceCents`, `sellPriceCents`),
///   siempre normalizado a EUR.
/// - La **cantidad** de títulos se guarda como entero escalado
///   ([quantityScaled] = unidades × [kQuantityScale]) para permitir fracciones
///   (p. ej. `0.0005`) sin pérdida de precisión por coma flotante.
@Collection(accessor: 'holdings')
class Holding {
  Id id = Isar.autoIncrement;

  /// Ticker para Yahoo Finance (p. ej. `AAPL`, `VWCE.DE`).
  @Index(caseSensitive: false)
  late String ticker;

  String name = '';

  /// Cantidad de títulos × [kQuantityScale].
  int quantityScaled = 0;

  /// Precio de compra unitario en céntimos de EUR.
  int buyPriceCents = 0;

  /// Divisa en la que se realizó la compra (informativo; el valor ya es EUR).
  String buyCurrency = 'EUR';

  /// Precio de venta unitario en céntimos de EUR (si ya se vendió).
  int? sellPriceCents;

  String? sellCurrency;

  DateTime purchaseDate = DateTime.now();

  DateTime? sellDate;

  Holding();

  // --- Helpers de cantidad escalada (directiva de calidad #5) ---

  /// Cantidad de títulos como `double` para mostrar/operar.
  @ignore
  double get quantity => quantityScaled / kQuantityScale;

  set quantity(double value) =>
      quantityScaled = (value * kQuantityScale).round();

  /// Construye el entero escalado a partir de una cantidad decimal.
  static int scaleQuantity(double value) =>
      (value * kQuantityScale).round();

  /// Convierte el entero escalado de vuelta a `double`.
  static double unscaleQuantity(int scaled) => scaled / kQuantityScale;

  /// Coste total de adquisición en céntimos (precio × cantidad).
  @ignore
  int get costBasisCents => (buyPriceCents * quantity).round();

  /// Indica si la posición sigue abierta (no vendida).
  @ignore
  bool get isOpen => sellPriceCents == null;
}
