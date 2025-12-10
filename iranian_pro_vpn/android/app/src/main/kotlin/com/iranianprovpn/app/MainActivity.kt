package com.iranianprovpn.app  // این خط رو تغییر بده

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.iranianprovpn.app/vpn"  // این خط رو تغییر بده
    private val VPN_REQUEST_CODE = 100

    // متغیر موقت برای نگهداری لینک و Result در هنگام درخواست مجوز
    private var pendingVpnConfigUri: String? = null
    private var pendingFlutterResult: MethodChannel.Result? = null
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpnService" -> {
                    val rawConfigLink = call.argument<String>("configLink")
                    
                    if (rawConfigLink.isNullOrEmpty()) {
                        result.error("CONFIG_ERROR", "Config link is missing from Flutter argument.", null)
                        return@setMethodCallHandler
                    }
                    
                    checkAndRequestVpnPermission(rawConfigLink, result)
                }
                "stopVpnService" -> {
                    stopVpnService()
                    result.success("VPN stop requested.")
                }
                "isVpnRunning" -> {
                    result.success(VpnConnectionService.isVpnRunning)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkAndRequestVpnPermission(configUri: String, result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        
        if (intent != null) {
            pendingVpnConfigUri = configUri
            pendingFlutterResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            startVpnService(configUri, result)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                val link = pendingVpnConfigUri
                val flutterResult = pendingFlutterResult
                
                if (link != null) {
                    if (flutterResult != null) {
                        startVpnService(link, flutterResult)
                    } else {
                        startVpnService(link, null)
                    }
                }
            } else {
                pendingFlutterResult?.error("VPN_PERMISSION_DENIED", "User denied VPN permission.", null)
            }
            pendingVpnConfigUri = null
            pendingFlutterResult = null
        }
    }
    
    private fun startVpnService(configUri: String, result: MethodChannel.Result?) {
        val intent = Intent(this, VpnConnectionService::class.java).apply {
            putExtra("CONFIG_URI", configUri)
        }
        startService(intent)
        
        result?.success("VPN service started with config: $configUri")
    }

    private fun stopVpnService() {
        val intent = Intent(this, VpnConnectionService::class.java).apply {
            putExtra("CONFIG_URI", "STOP_VPN")
        }
        startService(intent)
    }
}