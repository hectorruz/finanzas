# Finanzas

Aplicación de finanzas personales **nativa para Android**, construida con **Flutter**.

- Diseño Material You con **color dinámico** sincronizado con el sistema y **tema oscuro AMOLED**.
- Barra inferior de navegación.
- Base de datos local con **Isar** (fork de comunidad `isar_community`).
- Manejo del dinero con **enteros (céntimos)** — sin errores de coma flotante.
- Cuentas, movimientos (con filtros y edición en lote), categorías personalizables, dashboard
  configurable, recurrentes, escaneo de tickets con OCR e inversiones con cotización en vivo.

---

## ⚙️ Puesta en marcha

> Este repositorio contiene el **código fuente** (`lib/`), `pubspec.yaml` y la documentación.
> La carpeta de plataforma `android/` y el código generado por `build_runner` (`*.g.dart`)
> **no** están versionados; se generan localmente con los pasos siguientes.

### Requisitos
- Flutter 3.24+ (Dart 3.5+)
- Android SDK + un emulador o dispositivo físico (Android 5.0 / API 21 o superior)

### Pasos

```bash
# 1. Generar la carpeta android/ (respeta lib/ y pubspec.yaml existentes)
flutter create . --org com.hectorruz --platforms=android

# 2. Instalar dependencias
flutter pub get

# 3. Generar el código de Isar (modelos *.g.dart)
dart run build_runner build --delete-conflicting-outputs

# 4. Analizar y ejecutar
flutter analyze
flutter run
```

### Ajustes manuales de Android tras `flutter create`

**`android/app/build.gradle`** (dentro de `android { defaultConfig { ... } }`):

```gradle
defaultConfig {
    applicationId "com.hectorruz.finanzas"
    minSdkVersion 21          // requerido por ML Kit y color dinámico
    targetSdkVersion flutter.targetSdkVersion
    // ...
}
```

**`android/app/src/main/AndroidManifest.xml`**:

```xml
<manifest ...>
    <!-- OCR de tickets: cámara opcional -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />

    <application
        android:label="Finanzas"
        ... >
        <!-- Descarga del modelo OCR de ML Kit al instalar -->
        <meta-data
            android:name="com.google.mlkit.vision.DEPENDENCIES"
            android:value="ocr" />
        ...
    </application>
</manifest>
```

---

## 🧱 Arquitectura

Estructura **feature-first** con capa de datos basada en repositorios sobre Isar y **Riverpod**
para estado e inyección de dependencias.

```
lib/
  main.dart              # bootstrap: init Isar -> ProviderScope(overrides) -> runApp
  app.dart               # MaterialApp.router + DynamicColorBuilder + temas
  core/
    money/               # Money: value object sobre int (céntimos) + formateo
    theme/               # ColorScheme claro/oscuro + override AMOLED
    router/              # go_router con StatefulShellRoute (bottom nav persistente)
    db/                  # IsarService (apertura + schemas) + isarProvider
    fx/                  # FxService: conversión de divisas a EUR (Yahoo Finance)
  data/
    models/              # 8 colecciones Isar (@collection)
    repositories/        # repos + providers Riverpod
  features/
    dashboard/ movements/ receipts/ investments/ accounts/ settings/
  shared/widgets/        # widgets reutilizables
```

### Manejo del dinero
Todo importe monetario se almacena y opera como `int` de **céntimos** (`amountCents`,
`totalCents`, `buyPriceCents`...). El value object `Money` (`lib/core/money/money.dart`)
centraliza parseo (`"12,34" -> 1234`) y formateo con `intl`. En inversiones, la **cantidad** de
acciones se guarda como entero escalado `quantityScaled` (×10⁶) para soportar fracciones
(p. ej. `0.0005`) sin pérdida de precisión.

### Inversiones
Cotización en vivo desde la API pública de Yahoo Finance:
`https://query1.finance.yahoo.com/v8/finance/chart/<TICKER>`
y conversión de divisas con pares `EUR` (p. ej. `USDEUR=X`). Todo el código es real (sin mocks);
requiere conexión a internet en el dispositivo.

---

## 🚀 CI: compilar la APK y publicar Releases

El workflow `.github/workflows/build-apk.yml` compila la APK de release en CI
(genera `android/` con `flutter create`, ejecuta `build_runner` y `flutter
build apk`). Como la APK se firma con la clave de depuración por defecto del
template de Flutter, sirve para pruebas; para distribución firma con tu propio
keystore.

- **Lanzamiento manual**: pestaña *Actions* → *Build APK* → *Run workflow*. La
  APK queda como artefacto descargable.
- **Publicar una Release**: crea y empuja un tag `v*`, p. ej.:
  ```bash
  git tag v0.1.0 && git push origin v0.1.0
  ```
  El workflow adjuntará la APK a una Release de GitHub con notas automáticas.

## 🔒 Datos y privacidad
- Todos los datos son **locales** (Isar). No hay backend.
- El OCR de tickets se ejecuta **on-device** (ML Kit), sin enviar imágenes a la nube.
- Las únicas peticiones de red son a Yahoo Finance para cotizaciones e índices de cambio.
- Import/Export en JSON desde **Ajustes**; opción de **borrar todos los datos**.
