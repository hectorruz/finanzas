# AGENTS.md — cómo retomar este proyecto

Guía de arranque para un agente de IA (Codex, Claude Code, …) o para una persona que
coja el proyecto sin contexto previo. Aquí está **lo que hay que saber para no romper
nada**; el porqué de cada decisión está en [CLAUDE.md](CLAUDE.md), que es la referencia
larga, y la visión de producto en [README.md](README.md).

Orden de lectura recomendado: este fichero entero → la sección de CLAUDE.md de la feature
que vayas a tocar → el código.

---

## 1. Qué es esto en dos líneas

App Flutter de finanzas personales para **Android**, con todos los datos locales en
**Isar**, **Riverpod** para estado/DI y **go_router** para navegación. Sin backend: lo que
parece "servidor" es un `HttpServer` que corre **en el propio móvil** para sincronizar con
otro móvil por Wi-Fi y para servir una webapp de escritorio. La interfaz y todos los
comentarios/documentación están **en español**.

Estado: en uso real por el autor. No hay versionado semántico serio (`0.1.0+1`); la unidad
de entrega es el **commit + APK** (`finanzas-<hash>.apk`).

---

## 2. Puesta en marcha (5 minutos)

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # genera los *.g.dart de Isar
flutter analyze && flutter test
```

- `android/` **está versionada**. **Nunca ejecutes `flutter create .`** sobre el repo:
  pisa manifest/Gradle/Kotlin y cambia el `applicationId` (`com.example.finanzas`), lo que
  rompe el cliente OAuth de Drive y la continuidad de firma de la APK.
- `*.g.dart`, `pubspec.lock`, `web/`, `build/`, el keystore y `android/key.properties`
  **no** están versionados (ver `.gitignore`).
- Los tests con Isar descargan el binario nativo la primera vez → hace falta red.

Compilar la APK de release (la webapp va **dentro** de la APK, empaquétala antes):

```bash
flutter build web -t lib/main_web.dart
dart run tool/pack_webapp.dart          # → assets/webapp.zip (se modifica, NO lo commitees)
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk ~/Documentos/finanzas/finanzas-$(git rev-parse --short HEAD).apk
```

---

## 3. Reglas de trabajo (las que más se incumplen)

1. **Móvil y webapp se actualizan juntos.** Si la feature existe en los dos sitios
   (informes, tarjetas del dashboard, ajustes que viajan por `/api/settings`, cuentas,
   objetivos…), el cambio va en `lib/features/<feature>/` **y** en `lib/features/web/`,
   en el mismo commit. Si de verdad solo aplica a una plataforma, dilo en el mensaje del
   commit para que no parezca un olvido.
2. **Nada falla en silencio.** Prohibido el `catch (_)` mudo: o se propaga a la interfaz,
   o se guarda en un campo de resultado visible (`backupLastResult`), o se notifica. Este
   repo ha pagado caros varios fallos silenciosos (ver §6).
3. **Dinero en enteros de céntimos**, siempre. Tipos de interés en puntos básicos.
   Redondea **una sola vez**, al final del cálculo. Nunca `double` para dinero.
4. **La lógica no trivial se extrae a una función pura + test.** Es el patrón de todo el
   repo: `deposit_math.dart`, `backup_planner.dart`, `notification_planner.dart`,
   `goal_planning.dart`, `notification_parser.dart`, `sync_qr.dart`, `regex_help.dart`.
   Widget que calcula fechas o importes por su cuenta = revisión rechazada.
5. **Documenta en el mismo commit.** Feature nueva o cambio de comportamiento → actualiza
   su sección en `CLAUDE.md` (y `README.md` si cambia lo que la app hace de cara al
   usuario). Los comentarios explican **por qué**, no qué.
6. **Idioma:** código, comentarios, textos de UI y mensajes de commit en español.
   Formato de commit: `tipo(ámbito): descripción` — p. ej. `feat(cuentas): …`,
   `fix(informes): …`, `test: …`.
7. **Antes de dar algo por terminado:** `flutter analyze` + `flutter test` en verde. Si
   tocaste modelos Isar, `build_runner` antes.
8. **Al cerrar una feature**, el flujo habitual del autor es: commit → push a `main` →
   compilar la APK de release y copiarla a `~/Documentos/finanzas/`.

---

## 4. Mapa rápido del código

| Necesitas tocar… | Empieza por |
| --- | --- |
| Arranque, entrypoints, orden de init | `lib/main.dart`, `lib/app.dart` |
| Esquema/DB, migraciones | `lib/core/db/` (`isar_service.dart`, `migration_service.dart`) |
| Modelos y enums | `lib/data/models/` (9 colecciones + `enums.dart`) |
| Acceso a datos | `lib/data/repositories/` (uno por modelo, con provider Riverpod) |
| Pantallas | `lib/features/<feature>/` |
| Webapp de escritorio | `lib/features/web/` + `lib/main_web.dart` |
| API HTTP del móvil | `lib/features/sync/net/data_api.dart` (+ `api_serializer.dart`) |
| Sincronización LAN | `lib/features/sync/` (`sync_engine.dart` = motor puro; `net/` = transporte) |
| Informes PDF/Excel | `lib/data/report_*.dart` |
| Copias en la nube | `lib/features/backup/` |
| Lector de notificaciones de pago | `lib/features/payments/` + `android/app/src/main/kotlin/…` |
| Rutas | `lib/core/router/app_router.dart` (constantes en `Routes`) |

**Tres entrypoints Dart**, todos en `lib/main.dart` salvo la web:
`main()` (app completa), `quickAddMain()` (popup del tile de Ajustes rápidos, no pasa por
el bloqueo) y `paymentIngestMain()` (engine **sin UI** que lanza Kotlin al llegar una
notificación de pago). Los dos últimos llevan `@pragma('vm:entry-point')`: si los
renombras o los "limpias" por parecer código muerto, **rompes features enteras**.
`lib/main_web.dart` es el cuarto, para el target web.

---

## 5. Invariantes que no se negocian

- **Dinero:** `int` de céntimos en persistencia y cálculo; `Money` para parsear/formatear;
  `quantityScaled` (×10⁶) para fracciones de participaciones.
- **Enums en Isar:** siempre `@Enumerated(EnumType.name)` y lectura con `enumByName()`
  (con fallback); `.byName()` lanza y no debe usarse sobre datos persistidos.
- **Soft delete:** las 6 colecciones sincronizables (`Account`, `Category`,
  `TransactionModel`, `RecurringRule`, `Receipt`, `Goal`) implementan `Syncable`
  (`uuid`/`updatedAt`/`deletedAt`). Borrar = marcar `deletedAt`; **toda** consulta filtra
  `deletedAt == null`. Guardar = pasar por el repositorio, que sella con `stampForSave`.
- **Sincronización:** ningún cambio se descarta en silencio; los timestamps solo *detectan*
  qué cambió, y un conflicto real lo resuelve una persona en la pantalla de revisión.
- **Ajustes locales vs. sincronizados:** identidad de sync, servidor, lector de pagos y
  credenciales de copias son **locales** — no viajan por sync ni por el JSON de backup.
  `BackupService.importJson` **muta** la fila de `settings` existente en vez de crear una
  nueva, justo para no borrarlos (hay test de regresión).
- **Importes en pantalla:** usa `MoneyText`, que respeta el modo privacidad
  (`hideAmounts`); `Text(Money(x).format())` se salta el ojo del dashboard.
- **La webapp no puede importar Isar** ni nada que lo importe transitivamente: los
  `*.g.dart` llevan literales `int64` que `dart2js` no representa y `flutter build web`
  revienta. Por eso `report_config.dart` está separado de `report_service.dart`.

---

## 6. Trampas conocidas (todas han mordido ya)

- **Isar rellena con `Int.MIN`**: añadir un `int` no-nullable a una colección con datos
  deja `-9223372036854775808` en las filas viejas, no el default de Dart. Sube
  `kCurrentDataVersion` y sanea en `migration_service.dart`.
- **`am force-stop` al depurar el lector de pagos**: deja el `NotificationListenerService`
  sin enlazar y parece un bug de la feature. Usa `am kill`.
- **Nunca `android:process` en el listener de pagos**: Isar admite varios isolates pero
  **no** varios procesos → corrupción de la BD.
- **`cancelAll()` de notificaciones está prohibido**: cada feature cancela solo *sus* ids
  (recurrentes = id de la regla, copias `800000000`, pagos `810000000+`, sync `900000000+`).
- **`assets/webapp.zip` aparece modificado tras empaquetar**: es esperado, no lo commitees
  (el repo guarda el placeholder).
- **El bundling de assets de Flutter no es recursivo**: por eso la webapp viaja como zip y
  no como carpeta. No "simplifiques" eso.
- **Un regex inválido en las reglas de pago degrada a la heurística en silencio**: por eso
  el editor valida con `regexError` antes de guardar.
- **La portada del informe puede quedar en blanco** si las tarjetas elegidas no aplican al
  flujo o no hay datos; degrada con gracia.
- **Nada de WorkManager**: su residuo huérfano ya provocó un crash en release (`3b1bdfa`).
  El trabajo periódico se dispara de forma oportunista desde `main()`/`resumed`/Wi-Fi.

---

## 7. Trabajo pendiente / ideas

Sin prioridad asignada; confirma con el autor antes de meterte en los grandes.

1. **Arreglar el workflow de CI** (`.github/workflows/build-apk.yml`): sigue haciendo
   `flutter create . --org com.hectorruz` y parcheando el manifest con `sed`, herencia de
   cuando `android/` no se versionaba. Hoy pisa la plataforma versionada y cambia el
   `applicationId`. Debería quedar: checkout → `pub get` → `build_runner` → `flutter build
   apk`. Opcional: empaquetar la webapp e inyectar el keystore desde secrets.
2. **TLS autofirmado** para el servidor LAN y la webapp: hoy el tráfico va en HTTP plano
   dentro de la red local, protegido solo por el token de emparejamiento.
3. **Descubrimiento mDNS** entre dispositivos: ahora el auto-sync del vinculado aproxima
   "estamos en la misma red" probando la última IP conocida del principal.
4. **Copias/sincronización con la app cerrada**: limitación asumida (sin WorkManager). Si
   alguna vez se aborda, hacerlo sin reintroducir el crash de release.
5. **`AccountType.investment` es hoy solo un contenedor**: no hay cotizaciones en vivo.
   (Versiones antiguas del README prometían Yahoo Finance; ese código ya no existe.)
6. **Verificar el OAuth de Google Drive** en Google Cloud Console: app publicada (en
   *Testing* el refresh token caduca a los 7 días) y SHA-1 de **release y debug**
   registrados; si no, Drive falla solo en un tipo de build. Nextcloud no necesita nada.
7. **iOS no está soportado** (servidores en segundo plano muy restringidos, y el lector de
   notificaciones no tiene equivalente).

---

## 8. Checklist antes de entregar un cambio

- [ ] `dart run build_runner build --delete-conflicting-outputs` si tocaste modelos Isar
- [ ] `flutter analyze` sin avisos nuevos
- [ ] `flutter test` en verde (y test nuevo si añadiste lógica no trivial)
- [ ] Migración escrita si añadiste un campo no-nullable a una colección con datos
- [ ] Paridad móvil ↔ webapp revisada (o justificada en el commit)
- [ ] `CLAUDE.md` / `README.md` actualizados si cambió el comportamiento
- [ ] Mensaje de commit en español con `tipo(ámbito): descripción`
