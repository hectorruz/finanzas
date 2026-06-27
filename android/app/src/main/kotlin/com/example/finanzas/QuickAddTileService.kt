package com.example.finanzas

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Tile de Ajustes rápidos (panel desplegable, junto a WiFi/modo avión).
 *
 * Al pulsarlo abre [MainActivity] con un extra que indica a Flutter que debe
 * navegar al editor de movimientos para registrar un ingreso/gasto.
 */
class QuickAddTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        // Tile sin estado "encendido": actúa como un botón de acción.
        qsTile?.let {
            it.state = Tile.STATE_INACTIVE
            it.updateTile()
        }
    }

    override fun onClick() {
        super.onClick()

        // Abre el popup translúcido de alta rápida (no la app completa).
        val intent = Intent(this, QuickAddActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        // Lanza el popup y colapsa el panel de Ajustes rápidos.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pending = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
