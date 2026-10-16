package com.example.documentz

import android.app.Activity
import android.content.Intent
import com.google.zxing.client.android.Intents
import com.google.zxing.integration.android.IntentIntegrator
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** QR camera runs inside this APK, with no scanner module or network download. */
@Suppress("DEPRECATION")
class SyncQrBridge(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "documentz/sync")
    private var pendingLink: String? = null
    private var scanResult: MethodChannel.Result? = null
    private val scanRequest = 8438

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scanSyncQr" -> scan(result)
                "takePairingLink" -> {
                    val link = pendingLink
                    pendingLink = null
                    result.success(link)
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(activity.intent)
    }

    fun scan(result: MethodChannel.Result) {
        if (scanResult != null) {
            result.error("scanner_busy", "Finish or cancel the current QR scan first.", null)
            return
        }
        scanResult = result
        try {
            IntentIntegrator(activity)
                .setRequestCode(scanRequest)
                .setCaptureActivity(SyncQrCaptureActivity::class.java)
                .setDesiredBarcodeFormats(listOf("QR_CODE"))
                .setPrompt("Scan the other device's DocumentZ pairing QR")
                .setOrientationLocked(false)
                .setBeepEnabled(false)
                .setBarcodeImageEnabled(false)
                .initiateScan()
        } catch (_: SecurityException) {
            scanResult = null
            result.error("camera_permission", "Allow camera access for DocumentZ, or use Read QR from image.", null)
        } catch (error: Exception) {
            scanResult = null
            result.error("scanner", "Could not open the camera scanner (${error.javaClass.simpleName}). Use Read QR from image or manual pairing.", null)
        }
    }

    fun activityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != scanRequest) return false
        val result = scanResult ?: return true
        scanResult = null
        if (data?.getBooleanExtra(Intents.Scan.MISSING_CAMERA_PERMISSION, false) == true) {
            result.error("camera_permission", "Camera permission was denied. Allow camera access in Android Settings, or use Read QR from image.", null)
            return true
        }
        if (resultCode == Activity.RESULT_OK && data == null) {
            result.error("scanner", "The camera returned no QR data. Please scan again.", null)
            return true
        }
        val raw = IntentIntegrator.parseActivityResult(resultCode, data)?.contents
        if (raw != null && raw.length > 4096) {
            result.error("scanner", "This QR code is too large to be a DocumentZ pairing invitation.", null)
        } else {
            result.success(raw)
        }
        return true
    }

    fun handleIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val raw = uri.toString()
        if (raw.length > 4096) return
        if (!((uri.scheme == "documentz" && uri.host == "pair") || uri.scheme == "documentz-sync")) return
        // The Dart parser additionally validates version, endpoint and key data.
        // Never print or persist this URI: its fragment is a temporary secret.
        pendingLink = raw
        intent.data = null
        channel.invokeMethod("pairingLinkAvailable", null)
    }

    fun close() {
        pendingLink = null
        scanResult?.success(null)
        scanResult = null
        channel.setMethodCallHandler(null)
    }
}
