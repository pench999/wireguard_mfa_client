package jp.co.fairway.wireguard_mfa_client

import android.content.Context
import android.content.Intent
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.io.ByteArrayInputStream
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object TunnelRuntime {
    val worker = Executors.newSingleThreadExecutor()
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
        val current = tunnel ?: return "stopped"
        return if (current.name == name && backend(context).getState(current) == Tunnel.State.UP) "running" else "stopped"
    }
    fun start(context: Context, name: String): Any? {
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
        try {
            context.startForegroundService(Intent(context, TunnelForegroundService::class.java))
        } catch (error: Exception) {
            backend(context).setState(candidate, Tunnel.State.DOWN, null)
            throw error
        }
        return null
    }
    fun stop(context: Context) {
        generation++
        tunnel?.let { backend(context).setState(it, Tunnel.State.DOWN, null) }
        context.stopService(Intent(context, TunnelForegroundService::class.java))
    }
}
