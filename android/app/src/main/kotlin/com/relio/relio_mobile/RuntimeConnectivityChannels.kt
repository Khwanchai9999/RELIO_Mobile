package com.relio.relio_mobile

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class RuntimeConnectivityChannels(private val context: Activity) : EventChannel.StreamHandler {
    companion object {
        private const val REQUEST_NEARBY = 7141
        private const val METHOD_CHANNEL = "relio/runtime_connectivity"
        private const val EVENT_CHANNEL = "relio/runtime_connectivity/events"
    }

    private val connectivityManager = context.getSystemService(ConnectivityManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var networkRegistered = false
    private var radioRegistered = false
    private var permissionResult: MethodChannel.Result? = null
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
                when (call.method) {
                    "readStatus" -> result.success(readStatus())
                    "requestPermissions" -> {
                        if (permissionResult != null) {
                            result.error("permissionRequestInProgress", "Permission request in progress", null)
                        } else {
                            val requested = (call.arguments as? List<*>)
                                ?.filterIsInstance<String>()?.distinct().orEmpty()
                            // ตรวจชื่อสิทธิ์ที่ระบบรองรับ; นโยบายเลือก tier อยู่ใน Dart ที่เดียว
                            if (requested.any { it !in readablePermissions() }) {
                                result.error("unsupportedPermission", "Unsupported Nearby permission", null)
                            } else {
                                val missing = requested.filterNot(::hasPermission)
                                if (missing.isEmpty()) result.success(null)
                                else {
                                    permissionResult = result
                                    ActivityCompat.requestPermissions(context, missing.toTypedArray(), REQUEST_NEARBY)
                                }
                            }
                        }
                    }
                    "openNearbySettings" -> {
                        val action = when (call.arguments as? String) {
                            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                            "wifi" -> Settings.ACTION_WIFI_SETTINGS
                            "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
                            else -> Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                        }
                        val intent = Intent(action)
                        if (action == Settings.ACTION_APPLICATION_DETAILS_SETTINGS) {
                            val app = if (call.arguments == "playServices") "com.google.android.gms" else context.packageName
                            intent.data = Uri.parse("package:$app")
                        }
                        try { context.startActivity(intent); result.success(null) }
                        catch (_: RuntimeException) { result.error("settingsUnavailable", "Settings unavailable", null) }
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != REQUEST_NEARBY) return
        permissionResult?.success(null)
        permissionResult = null
        publish()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (!networkRegistered) {
            try {
                connectivityManager?.registerDefaultNetworkCallback(networkCallback)
                networkRegistered = connectivityManager != null
            } catch (_: RuntimeException) { /* ยังอ่าน snapshot ได้เมื่อ callback ถูกจำกัด */ }
        }
        if (!radioRegistered) {
            try {
                val filter = IntentFilter().apply {
                    addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
                    addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
                    addAction(LocationManager.MODE_CHANGED_ACTION)
                    addAction(LocationManager.PROVIDERS_CHANGED_ACTION)
                }
                // Bluetooth broadcast อาจมาจาก privileged process ที่ไม่ใช่ system UID
                ContextCompat.registerReceiver(context, radioReceiver, filter, ContextCompat.RECEIVER_EXPORTED)
                radioRegistered = true
            } catch (_: RuntimeException) { /* foreground refresh เป็นเส้นทางสำรอง */ }
        }
        publish()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        if (networkRegistered) {
            try { connectivityManager?.unregisterNetworkCallback(networkCallback) }
            catch (_: RuntimeException) { /* ป้องกันการถอด callback ซ้ำ */ }
        }
        if (radioRegistered) {
            try { context.unregisterReceiver(radioReceiver) }
            catch (_: RuntimeException) { /* ป้องกันการถอด receiver ซ้ำ */ }
        }
        networkRegistered = false
        radioRegistered = false
    }

    private fun readablePermissions(): List<String> = buildList {
        add(Manifest.permission.ACCESS_COARSE_LOCATION)
        add(Manifest.permission.ACCESS_FINE_LOCATION)
        add(Manifest.permission.ACCESS_WIFI_STATE)
        add(Manifest.permission.CHANGE_WIFI_STATE)
        if (Build.VERSION.SDK_INT >= 31) {
            add(Manifest.permission.BLUETOOTH_SCAN)
            add(Manifest.permission.BLUETOOTH_CONNECT)
            add(Manifest.permission.BLUETOOTH_ADVERTISE)
        }
        if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.NEARBY_WIFI_DEVICES)
    }

    private fun readStatus(): Map<String, Any?> {
        val network = connectivityManager?.activeNetwork
        val capabilities = network?.let { connectivityManager?.getNetworkCapabilities(it) }
        val wifiManager = context.applicationContext.getSystemService(WifiManager::class.java)
        val locationManager = context.getSystemService(LocationManager::class.java)
        val bluetoothManager = context.getSystemService(BluetoothManager::class.java)
        val bluetoothAvailable = context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)
        val bluetoothEnabled = try {
            if (Build.VERSION.SDK_INT >= 31 && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) null
            else bluetoothManager?.adapter?.isEnabled
        } catch (_: RuntimeException) { null }
        val playStatus = try {
            when (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)) {
                ConnectionResult.SUCCESS -> "available"
                ConnectionResult.SERVICE_MISSING -> "missing"
                ConnectionResult.SERVICE_DISABLED -> "disabled"
                ConnectionResult.SERVICE_VERSION_UPDATE_REQUIRED -> "outdated"
                ConnectionResult.SERVICE_UPDATING -> "updating"
                else -> "unavailable"
            }
        } catch (_: RuntimeException) { "unknown" }

        return mapOf(
            "androidSdk" to Build.VERSION.SDK_INT,
            "deviceModel" to Build.MODEL,
            "targetSdk" to context.applicationInfo.targetSdkVersion,
            "hasInternetRoute" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ?: false),
            "internetValidated" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) ?: false),
            "wifiAvailable" to context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI),
            "wifiEnabled" to try { wifiManager?.isWifiEnabled } catch (_: RuntimeException) { null },
            "bluetoothAvailable" to bluetoothAvailable,
            "bluetoothEnabled" to bluetoothEnabled,
            "permissions" to readablePermissions().associateWith(::hasPermission),
            "locationEnabled" to try {
                locationManager?.let { LocationManagerCompat.isLocationEnabled(it) }
            } catch (_: RuntimeException) { null },
            "playServicesStatus" to playStatus,
        )
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun publish() {
        handler.post { eventSink?.success(readStatus()) }
    }
}
