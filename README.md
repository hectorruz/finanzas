# Finanzas

Aplicación de **finanzas personales para Android**, hecha con **Flutter**, con todos los datos
**en el dispositivo** (sin backend, sin cuentas, sin telemetría) y un pequeño servidor HTTP
propio para sincronizar con otro móvil por Wi-Fi y para usar la app desde el navegador del PC.

- Material You con **color dinámico** y tema oscuro **AMOLED**.
- Base de datos local **Isar** (fork de comunidad `isar_community`), **Riverpod** para
  estado/DI y **go_router** para navegación.
- Dinero siempre en **enteros de céntimos** — nunca `double`.
- Interfaz en español (`es_ES`).

---

## ✨ Qué hace

| Área | Resumen |
| --- | --- |
| **Cuentas** | Banco, efectivo, inversión, **depósito a plazo** y **Letra del Tesoro**, con subcuentas de profundidad ilimitada, archivado y saldo inicial. Los depósitos estiman el interés **neto** (retención de IRPF del 19 %) y las letras la ganancia al vencimiento; ese rendimiento se suma al saldo del banco asociado. |
| **Movimientos** | Ingresos, gastos y transferencias, con filtros tipo Excel, búsqueda por texto, edición en lote y detalle en hoja inferior. |
| **Categorías** | Categorías de ingreso/gasto con subcategorías de profundidad ilimitada, icono y color. |
| **Recurrentes** | Plantillas (nómina, suscripciones…) con frecuencia × intervalo; se materializan solas al abrir la app y avisan con una **notificación local** configurable. |
| **Tickets (OCR)** | Escaneo **on-device** con ML Kit: comercio, total y fecha con marca de confianza, memoria de correcciones comercio → categoría, detección de duplicados y copia de la foto al álbum "Finanzas" de la galería. |
| **Pagos automáticos** | Lee las notificaciones de pago (Google Wallet y **cualquier app** con reglas regex propias) y **crea el gasto aunque la app esté cerrada**. |
| **Dashboard** | Rejilla de tarjetas configurable (saldo total, saldos por cuenta, comparativa mensual, últimos movimientos, alta rápida, escanear ticket, objetivos) y **modo privacidad** (el ojo de la barra superior oculta todos los importes). |
| **Objetivos** | Metas de ahorro con dos modos de planificación: aporto X €/mes → fecha estimada, o fijo la fecha → aporte mensual necesario. |
| **Informes** | Informe con portada de tarjetas personalizable, evolución temporal, rankings por categoría/cuenta/concepto, medias, récords y comparativa con el periodo anterior; se exporta a **PDF** y a **Excel** (con formato condicional, autofiltro y cabecera congelada). |
| **Sincronización LAN** | Dos móviles (principal ↔ vinculado) se sincronizan por Wi-Fi con emparejamiento por PIN o QR. **Ningún cambio se pisa en silencio**: los conflictos los resuelve una persona en una pantalla de revisión. |
| **Webapp de escritorio** | El propio móvil sirve una app web completa: abre `http://<ip-del-móvil>:<puerto>` desde cualquier navegador de la misma Wi-Fi. |
| **Copias de seguridad** | Export/import JSON manual y copias automáticas a **Nextcloud** (WebDAV) o **Google Drive**, con frecuencia, retención y aviso de fallo. |
| **Seguridad** | Bloqueo de la app con la credencial del dispositivo (huella/PIN) y ocultación del contenido en el conmutador de tareas. |
| **Alta rápida** | Tile de Ajustes rápidos que abre un popup translúcido para apuntar un gasto sin abrir la app ni pasar el bloqueo. |

---

## ⚙️ Puesta en marcha

### Requisitos
- Flutter **3.24+** (Dart 3.5+)
- JDK 17 y Android SDK; dispositivo o emulador con **Android 7.0 (API 24)** o superior

### Pasos

La carpeta `android/` **sí está versionada** (manifest, Gradle, Kotlin, recursos). Lo único
que hay que generar es el código de Isar (`*.g.dart`, ignorado por git):

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

> ⚠️ **No ejecutes `flutter create .`** para "regenerar" `android/`: sobrescribiría los
> ficheros versionados y cambiaría el `applicationId` (`com.example.finanzas`), con lo que
> se rompería el cliente OAuth de Google Drive y la APK dejaría de poder actualizar una
> instalación existente.

### Comandos habituales

```bash
flutter analyze                                  # lint
flutter test                                     # toda la batería (≈40 ficheros)
flutter test test/money_test.dart                # un solo fichero
dart run build_runner build --delete-conflicting-outputs   # tras tocar modelos Isar
```

Los tests que necesitan Isar descargan el binario nativo la primera vez
(`Isar.initializeIsarCore(download: true)` en `test/support/test_isar.dart`), así que la
primera ejecución requiere conexión.

---

## 📦 Compilar la APK

La webapp de escritorio viaja **dentro** de la APK como `assets/webapp.zip`; en el repo hay
un *placeholder*, así que hay que empaquetar el build web **antes** de compilar o el móvil
servirá una página de "aún no compilada":

```bash
flutter build web -t lib/main_web.dart      # build de la webapp
dart run tool/pack_webapp.dart              # → assets/webapp.zip
flutter build apk --release
```

La release se firma con un keystore persistente (`android/app/finanzas.keystore` +
`android/key.properties`, ambos **fuera del repo**). Si faltan, Gradle cae a la clave de
depuración y la APK resultante **no podrá actualizar** una instalación firmada con el
keystore bueno. Guarda copia de ambos ficheros en sitio seguro.

### CI

`.github/workflows/build-apk.yml` compila la APK al empujar un tag `v*` o a mano desde la
pestaña *Actions*:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Las APK de CI van firmadas con la clave de depuración del runner y **no** incluyen la
webapp real (el workflow no ejecuta el paso de empaquetado): sirven para probar, no para
distribuir. El workflow además sigue regenerando `android/` con `flutter create`, algo
incompatible con la carpeta versionada — ver *Deuda técnica* en [AGENTS.md](AGENTS.md).

---

## 🧱 Arquitectura

Estructura **feature-first**; la capa de datos son repositorios sobre Isar expuestos como
providers de Riverpod.

```
lib/
  main.dart      # 3 entrypoints: main, quickAddMain (popup), paymentIngestMain (headless)
  main_web.dart  # entrypoint de la webapp de escritorio
  app.dart       # MaterialApp.router + color dinámico + ciclo de vida (sync/backup/pagos)
  core/
    db/          # IsarService (apertura + esquemas), migraciones, isarProvider
    money/       # Money: parseo y formateo sobre int de céntimos
    sync/        # contrato Syncable (uuid/updatedAt/deletedAt) + sellado
    planning/    # matemática pura de objetivos
    notifications/ router/ theme/ icons/ platform/
  data/
    models/      # 9 colecciones Isar + enums.dart
    repositories/# un repo por modelo + providers
    report_*.dart, backup_service.dart, seed_service.dart
  features/
    dashboard/ movements/ accounts/ categories/ receipts/ reports/ payments/
    notifications/ backup/ sync/ security/ settings/ quick_add/ web/
  shared/widgets/
```

### Invariantes del proyecto

1. **Dinero en enteros.** Todo importe es `int` de céntimos (`amountCents`, `totalCents`,
   `nominalCents`…). `Money` (`lib/core/money/money.dart`) centraliza parseo y formato.
   Los tipos de interés van en **puntos básicos** (`3,75 % → 375`).
2. **Enums por nombre.** Se persisten con `@Enumerated(EnumType.name)`; para leerlos usa
   `enumByName()` (con fallback) y nunca `.byName()`, que lanza.
3. **Borrado suave.** Las entidades sincronizables no se borran: se marcan con `deletedAt`
   y toda lectura filtra `deletedAt == null`.
4. **Nada se pierde en silencio.** Ni en la sincronización (los conflictos los decide una
   persona) ni en los errores: se propagan a la interfaz en vez de tragarse con `catch (_)`.
5. **Móvil y webapp van juntos.** Si una funcionalidad existe en los dos sitios, se
   actualiza en los dos en el mismo commit.

---

## 🔒 Datos y privacidad

- Todos los datos viven en el dispositivo (Isar). **No hay backend ni cuentas de usuario.**
- El OCR de tickets se ejecuta **on-device** (ML Kit): las fotos no salen del móvil.
- La copia de seguridad automática de Android está **desactivada** (`allowBackup="false"`)
  para que el sistema no suba la base de datos —con los tokens de sincronización— sin
  consentimiento. Sacar datos del móvil es siempre una acción explícita: export JSON,
  copia a Nextcloud/Drive o sincronización LAN.
- El tráfico de sincronización y de la webapp es **HTTP plano dentro de la red local**,
  protegido por token de emparejamiento (pendiente TLS autofirmado).
- Peticiones a internet: solo las que tú actives (Nextcloud / Google Drive).

---

## 📚 Más documentación

- **[CLAUDE.md](CLAUDE.md)** — guía técnica larga: decisiones de diseño, detalles de cada
  fase (sync, webapp, notificaciones, OCR, pagos, copias, informes) y las trampas de cada
  una. Es la referencia de fondo para tocar el código.
- **[AGENTS.md](AGENTS.md)** — arranque rápido para un agente de IA (Codex, Claude Code…)
  o una persona que retome el proyecto: estado actual, flujo de trabajo, invariantes,
  errores típicos y trabajo pendiente.
