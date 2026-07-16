package com.example.finanzas

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Arranca un FlutterEngine **sin interfaz** que ejecuta el entrypoint Dart
 * `paymentIngestMain` (abrir Isar, drenar el buffer y crear los gastos) y lo
 * destruye al terminar. Es lo que hace que un pago se apunte solo, con la app
 * cerrada, sin notificación permanente ni consumo en reposo.
 *
 * No arrancamos ningún servicio: el sistema ya tiene enlazado el
 * `PaymentNotificationListenerService`, así que las restricciones de arranque en
 * segundo plano de Android 12+ no aplican. Todo el estado se toca solo desde el
 * hilo principal (donde Android entrega `onNotificationPosted`), así que no hace
 * falta sincronizar.
 */
object PaymentIngestEngine {

    private const val TAG = "PaymentIngest"
    private const val LIFECYCLE_CHANNEL = "com.example.finanzas/payment_ingest"
    private const val ENTRYPOINT = "paymentIngestMain"

    /** Wallet actualiza la misma notificación varias veces seguidas: agrupa la ráfaga. */
    private const val DEBOUNCE_MS = 1_200L

    /** Red de seguridad por si Dart nunca avisa (p. ej. el isolate revienta). */
    private const val TIMEOUT_MS = 60_000L

    private val handler = Handler(Looper.getMainLooper())
    private var appContext: Context? = null
    private var engine: FlutterEngine? = null
    private var running = false

    /** Llegó una notificación mientras drenábamos: hay que volver a mirar. */
    private var rerun = false

    private val startRunnable = Runnable { start() }
    private val timeoutRunnable = Runnable {
        Log.w(TAG, "timeout: el isolate no avisó de que terminaba; destruyendo el engine")
        finish()
    }

    /** Una notificación de pago acaba de entrar en el buffer. */
    fun trigger(context: Context) {
        val app = context.applicationContext
        handler.post {
            appContext = app
            if (running) {
                // El engine ya está drenando: lo que acaba de entrar lo verá él
                // o, si llegó tarde, el reintento de `finish()`.
                rerun = true
                return@post
            }
            handler.removeCallbacks(startRunnable)
            handler.postDelayed(startRunnable, DEBOUNCE_MS)
        }
    }

    private fun start() {
        if (running) return
        val ctx = appContext ?: return
        running = true
        rerun = false

        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(ctx) // idempotente: no hace nada si ya arrancó
        // Asíncrono: no bloqueamos el hilo principal del proceso esperando al loader.
        loader.ensureInitializationCompleteAsync(ctx, null, handler) {
            if (!running) return@ensureInitializationCompleteAsync
            try {
                launch(ctx, loader.findAppBundlePath())
            } catch (e: Exception) {
                Log.e(TAG, "no se pudo arrancar el engine headless", e)
                finish()
            }
        }
    }

    private fun launch(ctx: Context, bundlePath: String) {
        // El constructor de FlutterEngine ya registra los plugins por su cuenta
        // (automaticallyRegisterPlugins), que es lo que necesitan path_provider
        // y flutter_local_notifications. Isar no necesita registro: su plugin
        // Android no hace nada y la librería nativa la carga Dart.
        val e = FlutterEngine(ctx)
        engine = e

        // Los canales se montan ANTES del entrypoint: Dart no empieza a correr
        // hasta `executeDartEntrypoint`, así que no se pierde ninguna llamada.
        // Sin PaymentsChannel, `drainBuffer()` daría MissingPluginException y el
        // puente Dart lo degradaría a "buffer vacío": no se procesaría nada.
        PaymentsChannel.register(e.dartExecutor.binaryMessenger, ctx)

        MethodChannel(e.dartExecutor.binaryMessenger, LIFECYCLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "finished") {
                    result.success(null)
                    Log.d(TAG, "ingesta terminada: ${call.arguments} gasto(s)")
                    finish()
                } else {
                    result.notImplemented()
                }
            }

        handler.postDelayed(timeoutRunnable, TIMEOUT_MS)
        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(bundlePath, ENTRYPOINT))
        Log.d(TAG, "engine headless arrancado ($ENTRYPOINT)")
    }

    private fun finish() {
        handler.removeCallbacks(timeoutRunnable)
        engine?.destroy()
        engine = null
        running = false
        Log.d(TAG, "engine headless destruido")

        // Carrera: una notificación publicada después del drenado y antes del
        // apagado se quedaría en el buffer hasta el siguiente pago. Reintentamos
        // solo si además llegó algo durante el run, así que no puede haber bucle
        // aunque el buffer no se vaciara nunca.
        val more = rerun && (appContext?.let { hasPending(it) } ?: false)
        rerun = false
        if (more) {
            Log.d(TAG, "quedan pagos sin drenar: reintentando")
            handler.postDelayed(startRunnable, DEBOUNCE_MS)
        }
    }

    private fun hasPending(ctx: Context): Boolean =
        PaymentNotificationListenerService.hasBuffered(ctx)
}
