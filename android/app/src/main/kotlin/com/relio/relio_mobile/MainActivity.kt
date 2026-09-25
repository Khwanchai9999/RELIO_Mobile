package com.relio.relio_mobile

import com.google.firebase.appdistribution.FirebaseAppDistribution
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val updateChannel = "relio/app_update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler(::handleUpdateCall)
    }

    private fun handleUpdateCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "checkForUpdate") {
            result.notImplemented()
            return
        }

        try {
            FirebaseAppDistribution.getInstance()
                .updateIfNewReleaseAvailable()
                .addOnSuccessListener {
                    // The official basic flow owns the tester dialog and the
                    // user-confirmed download/install. Success means checked.
                    result.success(mapOf("status" to "checked"))
                }
                .addOnFailureListener {
                    // Do not return exception text: it may contain account or
                    // configuration details. The Flutter layer receives only
                    // a safe state code.
                    result.success(mapOf("status" to "unavailable", "code" to "sdkUnavailable"))
                }
        } catch (_: Throwable) {
            result.success(mapOf("status" to "unavailable", "code" to "sdkUnavailable"))
        }
    }
}
