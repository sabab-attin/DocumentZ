package com.example.documentz

import android.os.Build
import android.net.wifi.WifiManager
import android.content.Context
import android.content.ComponentName
import android.content.pm.PackageManager
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var automaticLibraryBridge: AutomaticLibraryBridge? = null
    private var documentOpenBridge: DocumentOpenBridge? = null
    private var appUpdateBridge: AppUpdateBridge? = null
    private var syncQrBridge: SyncQrBridge? = null
    private var nearbySyncBridge: NearbySyncBridge? = null
    private var immersiveReader = false
    private var syncMulticastLock: WifiManager.MulticastLock? = null
    private var networkResult: MethodChannel.Result? = null
    private val networkRequest = 8437
    private val iconAliases = mapOf(
        "classic" to "com.example.documentz.LauncherClassic",
        "kawaii" to "com.example.documentz.LauncherKawaii",
        "medieval" to "com.example.documentz.LauncherMedieval"
    )
    private val scanner = Executors.newSingleThreadExecutor()
    private val worker = Executors.newSingleThreadExecutor()
    private var folderResult: MethodChannel.Result? = null
    private val folderRequest = 8432
    private val storageAccess by lazy { DeviceStorageAccess(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        automaticLibraryBridge?.close()
        automaticLibraryBridge = AutomaticLibraryBridge(this, flutterEngine)
        documentOpenBridge?.close()
        documentOpenBridge = DocumentOpenBridge(this, flutterEngine)
        appUpdateBridge?.close()
        appUpdateBridge = AppUpdateBridge(this, flutterEngine)
        syncQrBridge?.close()
        syncQrBridge = SyncQrBridge(this, flutterEngine)
        nearbySyncBridge?.close()
        nearbySyncBridge = NearbySyncBridge(this, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "documentz/appearance").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "localSyncDiscovery" -> {
                        if (call.argument<Boolean>("enabled") == true) {
                            if (syncMulticastLock?.isHeld != true) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                                syncMulticastLock = wifi?.createMulticastLock("DocumentZ local sync")?.apply {
                                    setReferenceCounted(false)
                                    acquire()
                                }
                            }
                        } else {
                            if (syncMulticastLock?.isHeld == true) syncMulticastLock?.release()
                            syncMulticastLock = null
                        }
                        result.success(null)
                    }
                    "localNetworkAccess" -> {
                        val permission = "android.permission.ACCESS_LOCAL_NETWORK"
                        if (Build.VERSION.SDK_INT < 37 || applicationInfo.targetSdkVersion < 37 ||
                            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else if (networkResult != null) {
                            result.error("busy", "A local network permission request is already open.", null)
                        } else {
                            networkResult = result
                            requestPermissions(arrayOf(permission), networkRequest)
                        }
                    }
                    "fullscreen" -> {
                        immersiveReader = call.argument<Boolean>("enabled") == true
                        applyReaderSystemBars()
                        result.success(null)
                    }
                    "getIcon" -> {
                        val selected = iconAliases.entries.firstOrNull {
                            val state = packageManager.getComponentEnabledSetting(ComponentName(this, it.value))
                            state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                                (it.key == "classic" && state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT)
                        }?.key ?: "classic"
                        result.success(selected)
                    }
                    "setIcon" -> {
                        val key = call.argument<String>("icon") ?: throw IllegalArgumentException("Missing icon")
                        require(iconAliases.containsKey(key)) { "Unknown icon" }
                        val chosen = iconAliases.getValue(key)
                        if (Build.VERSION.SDK_INT >= 33) {
                            packageManager.setComponentEnabledSettings(iconAliases.values.map {
                                PackageManager.ComponentEnabledSetting(
                                    ComponentName(this, it),
                                    if (it == chosen) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                    PackageManager.DONT_KILL_APP
                                )
                            })
                        } else {
                            // Enable the new launcher entry before disabling the previous one.
                            packageManager.setComponentEnabledSetting(ComponentName(this, chosen),
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                            iconAliases.values.filter { it != chosen }.forEach {
                                packageManager.setComponentEnabledSetting(ComponentName(this, it),
                                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("appearance", "Could not update appearance", null) }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "documentz/device_documents").setMethodCallHandler { call, result ->
            if (storageAccess.handle(call, result)) return@setMethodCallHandler
            when (call.method) {
                "addFolder" -> {
                    if (folderResult != null) { result.error("busy", "Folder picker already open", null) }
                    else {
                        folderResult = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).putExtra(Intent.EXTRA_LOCAL_ONLY, true).addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION), folderRequest)
                        } catch (e: Exception) { folderResult = null; result.error("picker", e.message, null) }
                    }
                }
                "removeFolder" -> {
                    try {
                        val uri = Uri.parse(call.argument<String>("folder")!!)
                        val granted = contentResolver.persistedUriPermissions.firstOrNull { it.uri == uri }
                        val flags = (if (granted?.isReadPermission == true) Intent.FLAG_GRANT_READ_URI_PERMISSION else 0) or
                            (if (granted?.isWritePermission == true) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
                        if (flags != 0) contentResolver.releasePersistableUriPermission(uri, flags)
                        result.success(null)
                    } catch (e: Exception) { result.error("permission", e.message, null) }
                }
                "scanScope" -> result.success(storageAccess.scope())
                "quickScan" -> {
                    val extensions = (call.argument<List<String>>("extensions") ?: emptyList()).toSet()
                    worker.execute {
                        val folders = contentResolver.persistedUriPermissions.filter { it.isReadPermission && DocumentsContract.isTreeUri(it.uri) }.map { it.uri.toString() }
                        val files = storageAccess.indexed(extensions).map { storageAccess.connectedIdentity(it, folders) }
                        runOnUiThread { result.success(mapOf("files" to files, "folders" to folders, "errors" to emptyList<String>())) }
                    }
                }
                "scan" -> {
                    val extensions = (call.argument<List<String>>("extensions") ?: emptyList()).toSet()
                    scanner.execute {
                        try {
                            val files = linkedMapOf<String, Map<String, Any>>()
                            val errors = mutableListOf<String>()
                            val folders = contentResolver.persistedUriPermissions.filter { it.isReadPermission && DocumentsContract.isTreeUri(it.uri) }.map { it.uri.toString() }
                            if (storageAccess.allowed()) {
                                val local = storageAccess.scan(extensions).map { storageAccess.connectedIdentity(it, folders) }
                                runOnUiThread { result.success(mapOf("files" to local, "folders" to folders, "errors" to emptyList<String>())) }
                                return@execute
                            }
                            for (folder in folders) {
                                val tree = Uri.parse(folder)
                                val queue = java.util.ArrayDeque<String>()
                                val visited = mutableSetOf<String>()
                                queue.add(DocumentsContract.getTreeDocumentId(tree))
                                while (!queue.isEmpty() && !Thread.currentThread().isInterrupted) {
                                    val parent = queue.removeFirst()
                                    if (!visited.add(parent)) continue
                                    try {
                                        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
                                        val projection = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                                            DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                                        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                                            while (cursor.moveToNext()) {
                                                val id = cursor.getString(0)
                                                val name = cursor.getString(1) ?: continue
                                                val mime = cursor.getString(2)
                                                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) queue.add(id)
                                                else if (extensions.contains(name.substringAfterLast('.', "").lowercase())) {
                                                    val fileUri = DocumentsContract.buildDocumentUriUsingTree(tree, id).toString()
                                                    files[tree.authority + ":" + id] = mapOf("uri" to fileUri, "name" to name, "folder" to folder,
                                                        "size" to (if (cursor.isNull(3)) 0L else cursor.getLong(3)),
                                                        "modified" to (if (cursor.isNull(4)) 0L else cursor.getLong(4)))
                                                }
                                            }
                                        } ?: errors.add(folder)
                                    } catch (e: Exception) { errors.add(folder) }
                                }
                            }
                            val shared = storageAccess.scan(extensions)
                            // Keep existing SAF identities so linked notes and imported copies stay connected.
                            val connectedPaths = files.values.mapNotNull { item ->
                                storageAccess.sharedPath(Uri.parse(item["uri"] as String))
                            }.toSet()
                            val merged = files.values.toList() + shared.filter {
                                !connectedPaths.contains(Uri.parse(it["uri"] as String).path)
                            }
                            runOnUiThread { result.success(mapOf("files" to merged, "folders" to folders, "errors" to errors.distinct())) }
                        } catch (e: Exception) { runOnUiThread { result.error("scan", e.message, null) } }
                    }
                }
                "rename" -> {
                    worker.execute {
                    try {
                        val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("Missing URI"))
                        require(uri.scheme == "content" || uri.scheme == "file") { "Expected a document URI" }
                        val name = call.argument<String>("name") ?: throw IllegalArgumentException("Missing name")
                        require(name.isNotBlank() && !name.contains('/') && !name.contains('\\')) { "Invalid name" }
                        val changed = if (uri.scheme == "file") storageAccess.rename(uri, name) else
                            (DocumentsContract.renameDocument(contentResolver, uri, name)
                                ?: throw IllegalStateException("Provider refused rename")).toString()
                        runOnUiThread { result.success(changed) }
                    } catch (e: Exception) { runOnUiThread { result.error("permission", "Could not rename. Reconnect the folder and allow write access.", null) } }
                    }
                }
                "delete" -> {
                    worker.execute {
                    try {
                        val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("Missing URI"))
                        require(uri.scheme == "content" || uri.scheme == "file") { "Expected a document URI" }
                        if (uri.scheme == "file") storageAccess.delete(uri)
                        else if (!DocumentsContract.deleteDocument(contentResolver, uri)) throw IllegalStateException("Provider refused deletion")
                        runOnUiThread { result.success(null) }
                    } catch (e: Exception) { runOnUiThread { result.error("permission", "Could not delete. Reconnect the folder and allow write access.", null) } }
                    }
                }
                "read" -> {
                    val uri = call.argument<String>("uri")
                    worker.execute {
                        try {
                            val parsed = Uri.parse(uri ?: throw IllegalArgumentException("Missing URI"))
                            if (parsed.scheme != "content" && parsed.scheme != "file") throw IllegalArgumentException("Expected a document URI")
                            val output = ByteArrayOutputStream()
                            (if (parsed.scheme == "file") storageAccess.read(parsed) else contentResolver.openInputStream(parsed))?.use { input ->
                                val buffer = ByteArray(65536)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    output.write(buffer, 0, count)
                                }
                            } ?: throw IllegalArgumentException("Cannot open document")
                            val bytes = output.toByteArray()
                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) { runOnUiThread { result.error("read", e.message, null) } }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun applyReaderSystemBars() {
        if (Build.VERSION.SDK_INT >= 30) {
            window.insetsController?.let { controller ->
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (immersiveReader) controller.hide(WindowInsets.Type.systemBars())
                else controller.show(WindowInsets.Type.systemBars())
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (immersiveReader) {
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            } else View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && immersiveReader) window.decorView.post { applyReaderSystemBars() }
    }

    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        documentOpenBridge?.handleIntent(intent)
        appUpdateBridge?.handleIntent(intent)
        syncQrBridge?.handleIntent(intent)
        super.onNewIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        automaticLibraryBridge?.resume()
    }

    override fun onDestroy() {
        automaticLibraryBridge?.close()
        automaticLibraryBridge = null
        documentOpenBridge?.close()
        documentOpenBridge = null
        appUpdateBridge?.close()
        appUpdateBridge = null
        nearbySyncBridge?.close()
        nearbySyncBridge = null
        syncQrBridge?.close()
        syncQrBridge = null
        if (syncMulticastLock?.isHeld == true) syncMulticastLock?.release()
        syncMulticastLock = null
        networkResult?.success(false)
        networkResult = null
        storageAccess.close()
        folderResult?.success(false)
        folderResult = null
        scanner.shutdownNow()
        worker.shutdown()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (appUpdateBridge?.permissionResult(requestCode, grantResults) == true) return
        if (nearbySyncBridge?.permissionResult(requestCode, grantResults) == true) return
        if (requestCode == networkRequest) {
            networkResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            networkResult = null
            return
        }
        storageAccess.permissionResult(requestCode)
    }

    @Deprecated("Uses FlutterActivity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (syncQrBridge?.activityResult(requestCode, resultCode, data) == true) return
        if (storageAccess.activityResult(requestCode)) return
        if (requestCode != folderRequest) return
        val result = folderResult ?: return
        folderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(false); return }
        try {
            contentResolver.takePersistableUriPermission(uri, (data?.flags ?: Intent.FLAG_GRANT_READ_URI_PERMISSION) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
            result.success(true)
        } catch (e: Exception) { result.error("permission", e.message, null) }
    }
}
