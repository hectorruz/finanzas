package com.example.finanzas

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth requiere FlutterFragmentActivity para mostrar el diálogo biométrico.
class MainActivity : FlutterFragmentActivity() {

    /** Acción pendiente entregada por un Quick Settings Tile (arranque en frío). */
    private var pendingAction: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Capturar la acción del intent que arrancó la actividad.
        pendingAction = intent?.getStringExtra(EXTRA_QUICK_ACTION)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialAction" -> {
                        result.success(pendingAction)
                        pendingAction = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Puente con el lector de notificaciones de pago (Google Wallet y apps
        // personalizadas). El servicio nativo bufferiza; aquí solo se drena y se
        // consulta el permiso de acceso a notificaciones.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PAYMENT_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> result.success(isNotificationAccessGranted())
                    "openListenerSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    "drainBuffer" -> result.success(
                        PaymentNotificationListenerService.readBuffer(this@MainActivity, clear = true)
                    )
                    "peekBuffer" -> result.success(
                        PaymentNotificationListenerService.readBuffer(this@MainActivity, clear = false)
                    )
                    "setSourcePackages" -> {
                        @Suppress("UNCHECKED_CAST")
                        val packages = (call.arguments as? List<String>) ?: emptyList()
                        PaymentNotificationListenerService.setSources(this@MainActivity, packages)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** ¿Tiene la app acceso a las notificaciones (listener habilitado por el usuario)? */
    private fun isNotificationAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        return flat.split(":").any {
            ComponentName.unflattenFromString(it)?.packageName == packageName
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra(EXTRA_QUICK_ACTION) ?: return
        // La app ya corre: entregar la acción directamente a Flutter.
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("onQuickAction", action)
        } else {
            pendingAction = action
        }
    }

    companion object {
        const val CHANNEL = "com.example.finanzas/quick_tile"
        const val PAYMENT_CHANNEL = "com.example.finanzas/payments"
        const val EXTRA_QUICK_ACTION = "quick_action"
    }
}
