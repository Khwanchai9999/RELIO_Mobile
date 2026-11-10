package com.relio.relio_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class EmergencyModeForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "RELIO emergency mode", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "สถานะโหมด SOS หรือ Rescue ที่ผู้ใช้เปิดไว้"
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                },
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                val requestedMode = intent.getStringExtra(EXTRA_MODE)
                if (requestedMode != null && requestedMode != activeMode) {
                    return START_NOT_STICKY
                }
                running = false
                activeMode = null
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        if (intent?.action != ACTION_START) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val mode = intent.getStringExtra(EXTRA_MODE)
            ?.takeIf { it == "sos" || it == "rescue" || it == "nearbyRelay" }
        if (mode == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        activeMode = mode
        running = true
        startForeground(NOTIFICATION_ID, notification(mode))
        return START_NOT_STICKY
    }

    private fun notification(mode: String): Notification {
        val route = when (mode) {
            "sos" -> "/sos/active"
            "rescue" -> "/rescue"
            else -> "/nearby"
        }
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("relio_notification_route", route)
        }
        val pending = PendingIntent.getActivity(
            this, 7601, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val title = when (mode) {
            "sos" -> "RELIO • SOS ACTIVE"
            "rescue" -> "RELIO • RESCUE ACTIVE"
            else -> "RELIO • NEARBY RELAY"
        }
        val body = when (mode) {
            "sos" -> "โหมด SOS ยังทำงานอยู่ แตะเพื่อจัดการ"
            "rescue" -> "โหมดกู้ภัยยังทำงานอยู่ แตะเพื่อจัดการ"
            else -> "กำลังเปิด Nearby เพื่อช่วยส่งต่อข้อความใกล้เคียง"
        }
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pending)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = false
        activeMode = null
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "com.relio.relio_mobile.action.START_EMERGENCY_MODE"
        const val ACTION_STOP = "com.relio.relio_mobile.action.STOP_EMERGENCY_MODE"
        const val EXTRA_MODE = "mode"
        private const val CHANNEL = "relio_emergency_mode"
        private const val NOTIFICATION_ID = 7601
        @Volatile var running: Boolean = false
            private set
        @Volatile var activeMode: String? = null
            private set
    }
}
