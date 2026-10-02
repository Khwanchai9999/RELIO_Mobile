package com.relio.relio_mobile

import android.content.Intent
import android.content.pm.PackageManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.util.Base64
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.firebase.appdistribution.FirebaseAppDistribution
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val updateChannel = "relio/app_update"
    private val notificationChannel = "relio/notifications"
    private val identityChannel = "relio/device_identity"
    private val diagnosticsChannel = "relio/diagnostics"
    private val identityKeyStore = RelioIdentityKeyStore()
    private val identityExecutor = Executors.newSingleThreadExecutor()
    private var runtimeConnectivityChannels: RuntimeConnectivityChannels? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var notificationsMethodChannel: MethodChannel? = null

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        runtimeConnectivityChannels?.onRequestPermissionsResult(requestCode)
        if (requestCode == REQUEST_NOTIFICATIONS) {
            val result = notificationPermissionResult
            notificationPermissionResult = null
            result?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler(::handleUpdateCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, identityChannel)
            .setMethodCallHandler(::handleIdentityCall)
        if (packageName != PROD_APPLICATION_ID) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, diagnosticsChannel)
                .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDiagnosticsDeviceInfo" -> result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER.take(80),
                            "model" to Build.MODEL.take(100),
                            "androidVersion" to Build.VERSION.RELEASE.take(40),
                            "apiLevel" to Build.VERSION.SDK_INT,
                            "package" to packageName,
                        ),
                    )
                    "shareDiagnosticsZip" -> {
                        try {
                            val path = call.argument<String>("path")
                                ?: throw IllegalArgumentException("missing archive path")
                            val file = File(path).canonicalFile
                            val cache = File(cacheDir, "diagnostics").canonicalFile
                            require(file.isFile && file.parentFile == cache) { "invalid archive path" }
                            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                            val share = Intent(Intent.ACTION_SEND).apply {
                                type = "application/zip"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(share, "ส่งออกข้อมูลวินิจฉัย RELIO"))
                            result.success(null)
                        } catch (_: Throwable) {
                            result.error("diagnostics_share_failed", "Could not share diagnostics archive", null)
                        }
                    }
                    else -> result.notImplemented()
                }
                }
        }
        createNotificationChannels()
        notificationsMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannel,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)
                    "notificationsAllowed" -> result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                    "getFcmToken" -> getQaFcmToken(result)
                    "showLocalNotification" -> showLocalNotification(call, result)
                    "consumeNotificationRoute" -> {
                        val route = intent?.getStringExtra(EXTRA_NOTIFICATION_ROUTE)
                            ?: intent?.getStringExtra("route")
                        intent?.removeExtra(EXTRA_NOTIFICATION_ROUTE)
                        intent?.removeExtra("route")
                        result.success(route)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        runtimeConnectivityChannels = RuntimeConnectivityChannels(this).also {
            it.register(flutterEngine)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        (intent.getStringExtra(EXTRA_NOTIFICATION_ROUTE)
            ?: intent.getStringExtra("route"))?.let { route ->
            notificationsMethodChannel?.invokeMethod("notificationTapped", route)
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_MESSAGES, "RELIO messages", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "แจ้งเตือนข้อความ Nearby โดยซ่อนเนื้อหาข้อความ"
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_SAFETY, "RELIO safety alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "แจ้งเตือน SOS ที่ได้รับจากอุปกรณ์ใกล้เคียง"
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_SYSTEM, "RELIO system", NotificationManager.IMPORTANCE_LOW).apply {
                description = "แจ้งเตือนสถานะ Sync และการอัปเดตที่สำคัญ"
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            },
        )
    }

    private fun handleIdentityCall(call: MethodCall, result: MethodChannel.Result) {
        identityExecutor.execute {
            try {
                val value = when (call.method) {
                    "getPublicIdentity" -> identityKeyStore.getOrCreatePublicIdentity().let {
                        mapOf("publicKey" to it.publicKey, "fingerprint" to it.fingerprint)
                    }
                    "fingerprint" -> identityKeyStore.fingerprint(
                        call.argument<String>("publicKey")
                            ?: throw IllegalArgumentException("missing public key"),
                    )
                    "sign" -> {
                        val encoded = call.argument<String>("message")
                            ?: throw IllegalArgumentException("missing message")
                        identityKeyStore.sign(decodeIdentityBytes(encoded))
                    }
                    "verify" -> {
                        val publicKey = call.argument<String>("publicKey")
                            ?: throw IllegalArgumentException("missing public key")
                        val message = call.argument<String>("message")
                            ?: throw IllegalArgumentException("missing message")
                        val signature = call.argument<String>("signature")
                            ?: throw IllegalArgumentException("missing signature")
                        identityKeyStore.verify(
                            publicKey,
                            decodeIdentityBytes(message),
                            signature,
                        )
                    }
                    else -> return@execute runOnUiThread { result.notImplemented() }
                }
                runOnUiThread { result.success(value) }
            } catch (_: Throwable) {
                runOnUiThread {
                    result.error("identity_unavailable", "Device identity operation unavailable", null)
                }
            }
        }
    }

    private fun decodeIdentityBytes(value: String): ByteArray {
        require(value.length <= 6000)
        return Base64.decode(value, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) {
            result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
            return
        }
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error("permission_in_progress", "Notification permission request is already active", null)
            return
        }
        notificationPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATIONS,
        )
    }

    private fun getQaFcmToken(result: MethodChannel.Result) {
        if (packageName != QA_APPLICATION_ID) {
            result.success(null)
            return
        }
        try {
            FirebaseMessaging.getInstance().token
                .addOnSuccessListener { token -> result.success(token) }
                .addOnFailureListener {
                    result.error("fcm_token_unavailable", "Push registration is unavailable", null)
                }
        } catch (_: Throwable) {
            result.error("fcm_unavailable", "Push registration is unavailable", null)
        }
    }

    private fun showLocalNotification(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
            ?: return result.error("invalid_arguments", "Notification data is unavailable", null)
        val id = arguments["id"] as? String ?: return result.error("invalid_id", "Notification id is unavailable", null)
        val title = arguments["title"] as? String ?: "RELIO"
        val body = arguments["body"] as? String ?: "มีการแจ้งเตือนใหม่"
        val route = arguments["route"] as? String ?: return result.error("invalid_route", "Notification route is unavailable", null)
        val urgent = arguments["urgent"] as? Boolean ?: false
        if (route != "/sos" && !route.matches(Regex("^/chat/[A-Za-z0-9._:-]{1,128}$"))) {
            return result.error("invalid_route", "Notification route is not allowed", null)
        }
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            result.success(false)
            return
        }
        val openApp = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_NOTIFICATION_ROUTE, route)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            route.hashCode(),
            openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val channel = if (urgent) CHANNEL_SAFETY else CHANNEL_MESSAGES
        val notification = NotificationCompat.Builder(this, channel)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(if (urgent) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(if (urgent) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(this).notify(id.hashCode() and 0x7fffffff, notification)
        result.success(true)
    }

    private fun handleUpdateCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "checkForFirebaseUpdate" -> checkForFirebaseUpdate(result)
                "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                "inspectApk" -> {
                    val path = call.argument<String>("path")
                        ?: throw IllegalArgumentException("missing path")
                    result.success(inspectApk(path))
                }
                "getInstalledSigningFingerprint" -> {
                    result.success(getSigningFingerprint(packageInfoForPackage(packageName)))
                }
                "launchInstaller" -> {
                    val path = call.argument<String>("path")
                        ?: throw IllegalArgumentException("missing path")
                    launchInstaller(path)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Throwable) {
            // Native errors are mapped to a safe result; package paths and
            // signing details must not leak into normal application logs.
            result.error("updateNativeError", "Update operation unavailable", null)
        }
    }

    private fun checkForFirebaseUpdate(result: MethodChannel.Result) {
        try {
            FirebaseAppDistribution.getInstance()
                .updateIfNewReleaseAvailable()
                .addOnSuccessListener {
                    // Firebase owns its tester dialog and user-confirmed install.
                    result.success(mapOf("status" to "checked"))
                }
                .addOnFailureListener {
                    result.success(mapOf("status" to "unavailable", "code" to "sdkUnavailable"))
                }
        } catch (_: Throwable) {
            result.success(mapOf("status" to "unavailable", "code" to "sdkUnavailable"))
        }
    }

    private fun canRequestPackageInstalls(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
        }
    }

    private fun inspectApk(path: String): Map<String, Any> {
        val packageInfo = packageManager.getPackageArchiveInfo(path, packageInfoFlags())
            ?: throw IllegalArgumentException("invalid apk")
        return mapOf(
            "packageName" to packageInfo.packageName,
            "versionCode" to versionCode(packageInfo),
            "signingCertSha256" to getSigningFingerprint(packageInfo),
        )
    }

    private fun launchInstaller(path: String) {
        val file = File(path)
        if (!file.isFile) throw IllegalArgumentException("apk not found")
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun packageInfoForPackage(name: String) =
        packageManager.getPackageInfo(name, packageInfoFlags())

    private fun packageInfoFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
    }

    private fun versionCode(packageInfo: android.content.pm.PackageInfo): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode
        }
    }

    private fun getSigningFingerprint(packageInfo: android.content.pm.PackageInfo): String {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.signatures ?: emptyArray()
        }
        if (signatures.isEmpty()) throw IllegalArgumentException("signer missing")
        val digest = MessageDigest.getInstance("SHA-256").digest(signatures.first().toByteArray())
        return digest.joinToString("") { byte -> "%02x".format(byte) }
    }

    companion object {
        private const val REQUEST_NOTIFICATIONS = 9024
        private const val CHANNEL_MESSAGES = "relio_messages"
        private const val CHANNEL_SAFETY = "relio_safety"
        private const val CHANNEL_SYSTEM = "relio_system"
        private const val EXTRA_NOTIFICATION_ROUTE = "relio_notification_route"
        private const val QA_APPLICATION_ID = "com.relio.relio_mobile.test"
        private const val PROD_APPLICATION_ID = "com.relio.relio_mobile"
    }
}
