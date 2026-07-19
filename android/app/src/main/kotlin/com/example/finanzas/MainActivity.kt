package com.example.finanzas

import android.content.Intent
import android.view.WindowManager
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
        // consulta el permiso de acceso a notificaciones. El mismo canal lo monta
        // el engine headless que procesa los pagos con la app cerrada (ver
        // `PaymentsChannel` y `PaymentIngestEngine`).
        PaymentsChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)

        // Pantalla segura (FLAG_SECURE): oculta la miniatura en recientes y
        // bloquea capturas. Debe operar sobre la ventana de ESTA actividad, por
        // eso vive aquí y no en PaymentsChannel (solo contexto) ni en el engine
        // headless. Las llamadas se ejecutan en el hilo principal (UI).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        val enabled = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
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
        const val SECURE_CHANNEL = "com.example.finanzas/secure_screen"
        const val EXTRA_QUICK_ACTION = "quick_action"
    }
}
