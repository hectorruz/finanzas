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
 * Flutter, así que captura los pagos **aunque la app esté cerrada**; la app
 * drena y procesa el buffer al abrir/reanudar (ver `PaymentIngestService`).
 *
 * Solo almacena título + texto + timestamp + paquete: no interpreta nada aquí
 * (el parseo y la creación del gasto ocurren en Dart, `notification_parser.dart`).
 */
class PaymentNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        val pkg = notification.packageName ?: return

        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val sources = prefs.getStringSet(KEY_SOURCES, DEFAULT_SOURCES) ?: DEFAULT_SOURCES
        if (!sources.contains(pkg)) return

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
    }

    companion object {
        const val PREFS = "payment_reader"
        const val KEY_BUFFER = "buffer"
        const val KEY_SOURCES = "sources"
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
    }
}
