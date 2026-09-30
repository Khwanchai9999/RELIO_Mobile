package com.relio.relio_mobile

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class RuntimeConnectivityChannels(private val context: Context) : EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "relio/runtime_connectivity"
        private const val EVENT_CHANNEL = "relio/runtime_connectivity/events"
    }

    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var eventSink: EventChannel.EventSink? = null
    private var registered = false

    private val handler = Handler(Looper.getMainLooper())
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = publish()
        override fun onLost(network: Network) = publish()
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publish()
    }

    private val radioReceiver = object : BroadcastReceiver() {
        override fun onReceive(receiverContext: Context?, intent: Intent?) = publish()
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "readStatus") result.success(readStatus())
                else result.notImplemented()
            }
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (!registered) {
            try {
                connectivityManager.registerDefaultNetworkCallback(networkCallback)
                val filter = IntentFilter().apply {
                    addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
                    addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
                    addAction(LocationManager.MODE_CHANGED_ACTION)
                    addAction(LocationManager.PROVIDERS_CHANGED_ACTION)
                }
                ContextCompat.registerReceiver(
                    context,
                    radioReceiver,
                    filter,
                    ContextCompat.RECEIVER_NOT_EXPORTED,
                )
                registered = true
            } catch (_: SecurityException) {
                // อ่านสถานะที่ระบบอนุญาตได้ แม้ Android จะจำกัดสิทธิ์บางรายการ
            } catch (_: RuntimeException) {
                // บางอุปกรณ์อาจไม่รองรับ callback บางชนิด จึงยังส่ง snapshot ได้
            }
        }
        publish()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        if (!registered) return
        try {
            connectivityManager.unregisterNetworkCallback(networkCallback)
        } catch (_: RuntimeException) {
            // ป้องกันการหยุด stream ซ้ำระหว่างปิด Activity
        }
        try {
            context.unregisterReceiver(radioReceiver)
        } catch (_: IllegalArgumentException) {
            // Receiver อาจถูกถอดไปแล้วเมื่อระบบปิด stream
        }
        registered = false
    }

    private fun readStatus(): Map<String, Any?> {
        val network = connectivityManager.activeNetwork
        val capabilities = network?.let(connectivityManager::getNetworkCapabilities)
        val wifiManager = context.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val sdk = Build.VERSION.SDK_INT

        val bluetoothEnabled = try {
            if (sdk >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                null
            } else {
                val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                manager.adapter?.isEnabled
            }
        } catch (_: SecurityException) {
            null
        }

        return mapOf(
            "hasInternetRoute" to capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
            "internetValidated" to capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
            "wifiEnabled" to try { wifiManager.isWifiEnabled } catch (_: SecurityException) { null },
            "bluetoothEnabled" to bluetoothEnabled,
            "nearbyPermissionsGranted" to hasRequiredNearbyPermissions(sdk),
            "locationEnabled" to if (sdk <= Build.VERSION_CODES.R) {
                try { locationManager.isLocationEnabled } catch (_: RuntimeException) { null }
            } else null,
            "androidSdk" to sdk,
        )
    }

    private fun hasRequiredNearbyPermissions(sdk: Int): Boolean = when {
        sdk >= Build.VERSION_CODES.TIRAMISU -> listOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.NEARBY_WIFI_DEVICES,
        ).all(::hasPermission)
        sdk >= Build.VERSION_CODES.S -> listOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_ADVERTISE,
        ).all(::hasPermission)
        else -> hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun publish() {
        val sink = eventSink ?: return
        handler.post { sink.success(readStatus()) }
    }
}
