package jp.co.fairway.wireguard_mfa_client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.net.VpnService

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var pendingName: String? = null
    private var pendingDeadline: Long? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "jp.co.fairway.wgmfa/tunnel")
            .setMethodCallHandler { call, result ->
                if (call.method == "start") {
                    if (pending != null) { result.error("service_start_failed", "VPN permission request pending", null); return@setMethodCallHandler }
                    val name = (call.arguments as? String) ?: call.argument<String>("name")
                    val deadline = if (call.arguments is Map<*, *>) call.argument<Number>("expiresAt")?.toLong() else null
                    if (name == null) { result.error("invalid_tunnel", null, null); return@setMethodCallHandler }
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        pending = result
                        pendingName = name
                        pendingDeadline = deadline
                        startActivityForResult(intent, 1001)
                    } else execute(result, "service_start_failed") { TunnelRuntime.start(applicationContext, name, deadline) }
                } else execute(result, if (call.method == "stop") "service_stop_failed" else "tunnel_failed") {
                    when (call.method) {
                        "state" -> TunnelRuntime.state(applicationContext, call.arguments as String)
                        "deadline" -> TunnelRuntime.deadline(call.arguments as String)
                        "stop" -> { TunnelRuntime.stop(applicationContext); null }
                        "provision" -> {
                            TunnelRuntime.provision(applicationContext, call.argument<String>("name")!!, call.argument<String>("config")!!)
                            null
                        }
                        else -> throw IllegalArgumentException("Unknown method")
                    }
                }
            }
    }

    private fun execute(result: MethodChannel.Result, code: String, action: () -> Any?) {
        TunnelRuntime.worker.execute {
            try {
                val value = action()
                runOnUiThread { result.success(value) }
            } catch (_: Exception) {
                runOnUiThread { result.error(code, "Android VPN operation failed", null) }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 1001) return
        val result = pending ?: return
        val name = pendingName!!
        val deadline = pendingDeadline
        pending = null
        pendingName = null
        pendingDeadline = null
        if (resultCode == Activity.RESULT_OK) execute(result, "service_start_failed") { TunnelRuntime.start(applicationContext, name, deadline) }
        else result.error("vpn_permission_denied", "VPN permission denied", null)
    }
}
