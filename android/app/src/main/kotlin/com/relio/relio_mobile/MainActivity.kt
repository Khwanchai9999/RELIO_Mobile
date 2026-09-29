package com.relio.relio_mobile

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.google.firebase.appdistribution.FirebaseAppDistribution
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val updateChannel = "relio/app_update"
    private var runtimeConnectivityChannels: RuntimeConnectivityChannels? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler(::handleUpdateCall)
        runtimeConnectivityChannels = RuntimeConnectivityChannels(this).also {
            it.register(flutterEngine)
        }
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
}
