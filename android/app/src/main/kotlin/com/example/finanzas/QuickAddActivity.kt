package com.example.finanzas

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs

/**
 * Activity translúcida que muestra el popup de alta rápida (estilo panel de
 * WiFi). Arranca Flutter con el entrypoint `quickAddMain`, que pinta solo un
 * diálogo para añadir ingreso/gasto. Al ser una pantalla aparte y transparente,
 * no abre la app ni pasa por el bloqueo (PIN/huella).
 */
class QuickAddActivity : FlutterActivity() {

    override fun getDartEntrypointFunctionName(): String = "quickAddMain"

    // Fondo transparente para ver el scrim (que pinta Flutter) y lo de detrás.
    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode =
        FlutterActivityLaunchConfigs.BackgroundMode.transparent
}
