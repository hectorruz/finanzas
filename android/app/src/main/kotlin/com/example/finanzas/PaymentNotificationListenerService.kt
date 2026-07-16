package com.example.finanzas

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * Escucha las notificaciones del sistema y guarda las de las apps de pago
 * configuradas (por defecto Google Wallet) en un buffer **persistente**
 * (SharedPreferences, como lista JSON). Vive independiente del engine de
 * Flutter, así que captura los pagos **aunque la app esté cerrada**, y acto
 * seguido lanza el engine de ingesta ([PaymentIngestEngine]) para que el gasto
 * se cree en el momento, sin esperar a que alguien abra la app.
 *
 * Solo almacena título + texto + timestamp + paquete: no interpreta nada aquí
 * (el parseo y la creación del gasto ocurren en Dart, `notification_parser.dart`).
 *
 * ⚠️ Este servicio debe seguir corriendo en el proceso principal: **nunca** le
 * añadas `android:process` en el manifest. La ingesta abre la misma instancia de
 * Isar que la interfaz, e Isar admite varios isolates pero **no** varios
 * procesos: se corrompería la base de datos.
 */
class PaymentNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        val pkg = notification.packageName ?: return

        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val sources = prefs.getStringSet(KEY_SOURCES, DEFAULT_SOURCES) ?: DEFAULT_SOURCES
        if (!sources.contains(pkg)) return

        // Espejo de `AppSettings.paymentReaderEnabled` (vive en Isar: Kotlin no
        // lo ve con la app cerrada). Ausente = nunca espejado, o sea una versión
        // anterior recién actualizada que aún no se ha abierto: capturamos como
        // siempre pero sin arrancar el engine, y se drenará al abrir. Lo fija
        // Dart en cada arranque y en el toggle de ajustes (`setReaderEnabled`).
        val enabled =
            if (prefs.contains(KEY_ENABLED)) prefs.getBoolean(KEY_ENABLED, false) else null
        if (enabled == false) return

        val extras = notification.notification?.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString().orEmpty()
        val text = extras.getCharSequence("android.text")?.toString().orEmpty()
        val bigText = extras.getCharSequence("android.bigText")?.toString().orEmpty()
        val body = if (bigText.isNotEmpty()) bigText else text
        if (title.isEmpty() && body.isEmpty()) return

        val item = JSONObject().apply {
            put("package", pkg)
            put("title", title)
            put("text", body)
            put("postedAt", notification.postTime)
        }

        synchronized(LOCK) {
            val arr = try {
                JSONArray(prefs.getString(KEY_BUFFER, "[]"))
            } catch (e: Exception) {
                JSONArray()
            }
            arr.put(item)
            val capped = if (arr.length() > MAX) {
                JSONArray().also { trimmed ->
                    for (i in (arr.length() - MAX) until arr.length()) trimmed.put(arr.get(i))
                }
            } else {
                arr
            }
            prefs.edit().putString(KEY_BUFFER, capped.toString()).apply()
        }

        // Lector confirmado activo: procesa el pago ya, aunque la app esté
        // cerrada. El engine se apaga solo al terminar.
        if (enabled == true) PaymentIngestEngine.trigger(applicationContext)
    }

    companion object {
        const val PREFS = "payment_reader"
        const val KEY_BUFFER = "buffer"
        const val KEY_SOURCES = "sources"
        const val KEY_ENABLED = "enabled"
        const val MAX = 200
        val DEFAULT_SOURCES: Set<String> = setOf("com.google.android.apps.walletnfcrel")
        private val LOCK = Any()

        /** Devuelve el buffer JSON y, si [clear], lo vacía. Usado por el puente. */
        fun readBuffer(context: Context, clear: Boolean): String {
            val prefs = context.getSharedPreferences(PREFS, MODE_PRIVATE)
            synchronized(LOCK) {
                val data = prefs.getString(KEY_BUFFER, "[]") ?: "[]"
                if (clear) prefs.edit().putString(KEY_BUFFER, "[]").apply()
                return data
            }
        }

        /** Fija las apps de origen cuyas notificaciones se capturan. */
        fun setSources(context: Context, packages: List<String>) {
            val prefs = context.getSharedPreferences(PREFS, MODE_PRIVATE)
            val set = if (packages.isEmpty()) DEFAULT_SOURCES else packages.toSet()
            prefs.edit().putStringSet(KEY_SOURCES, set).apply()
        }

        /**
         * Espeja el ajuste de Isar que decide si se captura y se procesa.
         * Al desactivar tira el buffer: si no, seguiría llenándose hasta [MAX] y
         * al reactivar entrarían de golpe pagos viejos ya caducados.
         */
        fun setEnabled(context: Context, enabled: Boolean) {
            val prefs = context.getSharedPreferences(PREFS, MODE_PRIVATE)
            synchronized(LOCK) {
                val editor = prefs.edit().putBoolean(KEY_ENABLED, enabled)
                if (!enabled) editor.putString(KEY_BUFFER, "[]")
                editor.apply()
            }
        }

        /** ¿Queda algo sin drenar? Resuelve la carrera drenado/apagado del engine. */
        fun hasBuffered(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, MODE_PRIVATE)
            synchronized(LOCK) {
                return try {
                    JSONArray(prefs.getString(KEY_BUFFER, "[]")).length() > 0
                } catch (e: Exception) {
                    false
                }
            }
        }
    }
}
