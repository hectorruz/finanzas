package com.example.finanzas

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Canal del lector de notificaciones de pago. Lo montan **los dos** engines: el
 * de la UI ([MainActivity]) y el headless ([PaymentIngestEngine]). Registrarlo
 * en ambos no es opcional: el puente Dart degrada `MissingPluginException` a
 * lista vacía, así que un engine sin este canal no procesaría ningún pago y no
 * lo diría.
 *
 * Todo funciona con el contexto de aplicación (las preferencias y
 * `Settings.Secure` no necesitan Activity), así que no retiene la Activity ni
 * depende de que exista una ventana.
 */
object PaymentsChannel {
    const val NAME = "com.example.finanzas/payments"

    fun register(messenger: BinaryMessenger, context: Context): MethodChannel {
        val app = context.applicationContext
        return MethodChannel(messenger, NAME).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> result.success(isNotificationAccessGranted(app))

                    // Abre una pantalla de ajustes: solo se llama desde la UI.
                    // Android 10+ bloquea los activity-start desde background,
                    // así que desde el engine headless no funcionaría.
                    "openListenerSettings" -> {
                        app.startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }

                    "drainBuffer" -> result.success(
                        PaymentNotificationListenerService.readBuffer(app, clear = true)
                    )
                    "peekBuffer" -> result.success(
                        PaymentNotificationListenerService.readBuffer(app, clear = false)
                    )
                    "setSourcePackages" -> {
                        @Suppress("UNCHECKED_CAST")
                        val packages = (call.arguments as? List<String>) ?: emptyList()
                        PaymentNotificationListenerService.setSources(app, packages)
                        result.success(null)
                    }
                    "setReaderEnabled" -> {
                        PaymentNotificationListenerService.setEnabled(
                            app,
                            call.arguments as? Boolean ?: false
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** ¿Tiene la app acceso a las notificaciones (listener habilitado por el usuario)? */
    fun isNotificationAccessGranted(context: Context): Boolean {
        val flat = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return flat.split(":").any {
            ComponentName.unflattenFromString(it)?.packageName == context.packageName
        }
    }
}
