package com.iranianprovpn.app  // این خط رو تغییر بده

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Base64
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.gson.Gson
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

data class VmessConfig(
    val v: String,
    val ps: String,
    val add: String,
    val port: String,
    val id: String,
    val aid: String,
    val net: String,
    val type: String,
    val host: String?,
    val path: String?,
    val tls: String?
)

data class ProxyConfig(
    val host: String,
    val port: Int,
    val uuid: String
)

class VpnConnectionService : VpnService() {
    companion object {
        private const val TAG = "VpnService"
        private const val NOTIFICATION_CHANNEL_ID = "VpnChannel"
        private const val NOTIFICATION_ID = 1
        private const val LOCAL_SOCKS_PORT = 10808
        var isVpnRunning = false
        private var proxyExecutor: ExecutorService? = null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val configUri = intent?.getStringExtra("CONFIG_URI")
        
        if (configUri.isNullOrEmpty()) {
            Log.e(TAG, "Config URI is missing.")
            return stopVpn()
        }
        
        if (configUri.startsWith("STOP_VPN")) {
            return stopVpn()
        }
        
        if (isVpnRunning) {
            return START_STICKY
        }

        startProxyServer(configUri)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): android.os.IBinder? = null

    override fun onRevoke() {
        stopVpn()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun startProxyServer(configUri: String) {
        if (isVpnRunning) return

        val proxyConfig = parseProxyConfig(configUri)
        if (proxyConfig == null) {
            Log.e(TAG, "Failed to parse proxy config")
            return
        }

        proxyExecutor = Executors.newFixedThreadPool(4)
        startSocksProxy(proxyConfig)
        
        isVpnRunning = true
        Log.i(TAG, "Proxy server started on port $LOCAL_SOCKS_PORT - ${proxyConfig.host}:${proxyConfig.port}")
        setupTunnel()
        setupNotification()
    }

    private fun stopVpn(): Int {
        proxyExecutor?.shutdownNow()
        proxyExecutor = null
        isVpnRunning = false
        Log.i(TAG, "Proxy server stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
        return START_NOT_STICKY
    }

    private fun startSocksProxy(config: ProxyConfig) {
        proxyExecutor?.execute {
            try {
                val serverSocket = ServerSocket(LOCAL_SOCKS_PORT)
                Log.i(TAG, "SOCKS server listening on $LOCAL_SOCKS_PORT")
                while (isVpnRunning) {
                    val clientSocket = serverSocket.accept()
                    proxyExecutor?.execute { handleSocksClient(clientSocket, config) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "SOCKS server error", e)
            }
        }
    }

    private fun handleSocksClient(clientSocket: Socket, config: ProxyConfig) {
        try {
            val targetSocket = Socket(config.host, config.port)
            Log.d(TAG, "Proxying to ${config.host}:${config.port}")
            forwardTraffic(clientSocket, targetSocket)
        } catch (e: Exception) {
            Log.e(TAG, "Proxy forward error", e)
            try {
                clientSocket.close()
            } catch (ignored: Exception) {}
        }
    }

    private fun forwardTraffic(local: Socket, remote: Socket) {
        val executor = proxyExecutor ?: return
        executor.execute { copyStream(local.getInputStream(), remote.getOutputStream(), local, remote) }
        executor.execute { copyStream(remote.getInputStream(), local.getOutputStream(), remote, local) }
    }

    private fun copyStream(input: InputStream, output: OutputStream, local: Socket, remote: Socket) {
        try {
            val buffer = ByteArray(4096)
            var bytes: Int
            while (input.read(buffer).also { bytes = it } != -1) {
                output.write(buffer, 0, bytes)
                output.flush()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Stream copy error", e)
        } finally {
            try {
                input.close()
                output.close()
            } catch (ignored: Exception) {}
        }
    }

    private fun parseProxyConfig(uri: String): ProxyConfig? {
        return try {
            if (uri.startsWith("vmess://")) {
                val base64Encoded = uri.substring(8)
                val decodedBytes = Base64.decode(base64Encoded, Base64.DEFAULT)
                val jsonString = String(decodedBytes, StandardCharsets.UTF_8)
                
                val gson = Gson()
                val vmess = gson.fromJson(jsonString, VmessConfig::class.java)
                
                ProxyConfig(
                    host = vmess.add,
                    port = vmess.port.toIntOrNull() ?: 443,
                    uuid = vmess.id
                )
            } else null
        } catch (e: Exception) {
            Log.e(TAG, "Config parse error: ${e.message}")
            null
        }
    }

    private fun setupTunnel() {
        val builder = Builder()
            .setMtu(1500)
            .addAddress("10.0.0.2", 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("1.1.1.1")
            .setSession("Iran Speed VPN")
        
        // Exclude this app from VPN
        builder.addDisallowedApplication(packageName)
        val vpnInterface = builder.establish()
        
        if (vpnInterface != null) {
            Log.i(TAG, "VPN tunnel established")
        } else {
            Log.e(TAG, "Failed to establish VPN tunnel")
        }
    }

    private fun setupNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Iran Speed VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN connection status"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Iran Speed VPN")
            .setContentText("Status: Connected via SOCKS Proxy")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }
}