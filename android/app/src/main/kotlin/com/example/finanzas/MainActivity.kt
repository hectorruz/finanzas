package com.example.finanzas

import android.content.Intent
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
        const val EXTRA_QUICK_ACTION = "quick_action"
    }
}
