package jp.co.fairway.wireguard_mfa_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TunnelExpiryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val expected = intent.getLongExtra("generation", -1)
        TunnelRuntime.worker.execute {
            try {
                TunnelRuntime.expireIfNeeded(context.applicationContext, expected)
            } finally {
                pending.finish()
            }
        }
    }
}
