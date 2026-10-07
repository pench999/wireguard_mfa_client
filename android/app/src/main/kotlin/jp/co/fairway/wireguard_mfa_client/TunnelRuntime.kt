package jp.co.fairway.wireguard_mfa_client

import android.content.Context
import android.content.Intent
import android.app.AlarmManager
import android.app.PendingIntent
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.io.ByteArrayInputStream
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object TunnelRuntime {
    val worker = Executors.newSingleThreadScheduledExecutor()
    private var deadlineElapsed: Long? = null
    private var expiryTask: ScheduledFuture<*>? = null
    private var expiryAlarm: PendingIntent? = null
    private var expiredName: String? = null
    private var authorizationExpiresAt: Long? = null
    @Volatile var generation = 0L
        private set
    private var backend: GoBackend? = null
    private var tunnel: Tunnel? = null
    private fun backend(context: Context): GoBackend = backend ?: GoBackend(context.applicationContext).also { backend = it }
    private fun file(context: Context, name: String): File {
        require(name.matches(Regex("^[A-Za-z0-9_.=+-]{1,64}$")))
        return File(context.noBackupFilesDir, "$name.wg.enc")
    }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("wgmfa-config", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("wgmfa-config", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun provision(context: Context, name: String, config: String) {
        Config.parse(ByteArrayInputStream(config.toByteArray(Charsets.UTF_8)))
        stop(context)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val destination = file(context, name)
        val temporary = File(destination.path + ".tmp")
        temporary.writeBytes(byteArrayOf(cipher.iv.size.toByte()) + cipher.iv + cipher.doFinal(config.toByteArray(Charsets.UTF_8)))
        check(temporary.renameTo(destination))
    }
    fun state(context: Context, name: String): String {
        if (!file(context, name).exists()) return "notInstalled"
        expireIfNeeded(context, generation)
        if (expiredName == name) return "expired"
        val current = tunnel ?: return "stopped"
        return if (current.name == name && backend(context).getState(current) == Tunnel.State.UP) "running" else "stopped"
    }
    fun start(context: Context, name: String, expiresAt: Long? = null): Any? {
        require(expiresAt == null || expiresAt > System.currentTimeMillis()) { "MFA authorization expired" }
        stop(context)
        expiredName = null
        val bytes = file(context, name).readBytes()
        val length = bytes[0].toInt() and 255
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(1, length + 1)))
        }
        val config = Config.parse(ByteArrayInputStream(cipher.doFinal(bytes.copyOfRange(length + 1, bytes.size))))
        val candidate = tunnel?.takeIf { it.name == name } ?: object : Tunnel {
            override fun getName() = name
            override fun onStateChange(newState: Tunnel.State) {
                if (newState == Tunnel.State.DOWN) {
                    context.stopService(Intent(context, TunnelForegroundService::class.java))
                }
            }
        }
        generation++
        backend(context).setState(candidate, Tunnel.State.UP, config)
        tunnel = candidate
        authorizationExpiresAt = expiresAt
        try {
            context.startForegroundService(Intent(context, TunnelForegroundService::class.java))
            if (expiresAt != null) {
                val expected = generation
                deadlineElapsed = SystemClock.elapsedRealtime() + (expiresAt - System.currentTimeMillis()).coerceAtLeast(0)
                expiryTask = worker.scheduleAtFixedRate({ expireIfNeeded(context, expected) }, 0, 1, TimeUnit.SECONDS)
                val alarm = PendingIntent.getBroadcast(context, 0,
                    Intent(context, TunnelExpiryReceiver::class.java).putExtra("generation", expected),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                expiryAlarm = alarm
                context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP, deadlineElapsed!!, alarm)
            }
        } catch (error: Exception) {
            cancelExpiry(context)
            backend(context).setState(candidate, Tunnel.State.DOWN, null)
            context.stopService(Intent(context, TunnelForegroundService::class.java))
            throw error
        }
        return null
    }
    fun stop(context: Context) {
        authorizationExpiresAt = null
        cancelExpiry(context)
        generation++
        tunnel?.let { backend(context).setState(it, Tunnel.State.DOWN, null) }
        context.stopService(Intent(context, TunnelForegroundService::class.java))
    }

    fun deadline(name: String): Long? = if (tunnel?.name == name) authorizationExpiresAt else null

    fun expireIfNeeded(context: Context, expectedGeneration: Long) {
        val deadline = deadlineElapsed ?: return
        if (generation != expectedGeneration || SystemClock.elapsedRealtime() < deadline) return
        val name = tunnel?.name ?: return
        stop(context)
        expiredName = name
    }

    private fun cancelExpiry(context: Context) {
        expiryTask?.cancel(false)
        expiryTask = null
        expiryAlarm?.let { context.getSystemService(AlarmManager::class.java).cancel(it) }
        expiryAlarm = null
        deadlineElapsed = null
    }
}
