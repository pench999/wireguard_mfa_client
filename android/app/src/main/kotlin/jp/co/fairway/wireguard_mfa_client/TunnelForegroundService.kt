package jp.co.fairway.wireguard_mfa_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder

class TunnelForegroundService : Service() {
    private var generation = 0L
    override fun onCreate() {
        super.onCreate()
        generation = TunnelRuntime.generation
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("vpn", "VPN", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        startForeground(1, Notification.Builder(this, "vpn")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("WireGuard MFA Client")
            .setContentText("VPN connected")
            .setContentIntent(open).setOngoing(true).build())
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_NOT_STICKY
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        val endedGeneration = generation
        TunnelRuntime.worker.execute {
            if (TunnelRuntime.generation == endedGeneration) TunnelRuntime.stop(applicationContext)
        }
        super.onDestroy()
    }
}
