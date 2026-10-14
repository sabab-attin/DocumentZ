package com.example.documentz

import android.os.Build
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
    private var immersiveReader = false
    private val iconAliases = mapOf(
        "classic" to "com.example.documentz.LauncherClassic",
        "kawaii" to "com.example.documentz.LauncherKawaii",
        "medieval" to "com.example.documentz.LauncherMedieval"
    )
    private val worker = Executors.newSingleThreadExecutor()
    private var folderResult: MethodChannel.Result? = null
    private val folderRequest = 8432

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "documentz/appearance").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
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
                "scan" -> {
                    val extensions = (call.argument<List<String>>("extensions") ?: emptyList()).toSet()
                    worker.execute {
                        try {
                            val files = linkedMapOf<String, Map<String, Any>>()
                            val errors = mutableListOf<String>()
                            val folders = contentResolver.persistedUriPermissions.filter { it.isReadPermission && DocumentsContract.isTreeUri(it.uri) }.map { it.uri.toString() }
                            for (folder in folders) {
                                val tree = Uri.parse(folder)
                                val queue = java.util.ArrayDeque<String>()
                                val visited = mutableSetOf<String>()
                                queue.add(DocumentsContract.getTreeDocumentId(tree))
                                while (!queue.isEmpty()) {
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
                            runOnUiThread { result.success(mapOf("files" to files.values.toList(), "folders" to folders, "errors" to errors.distinct())) }
                        } catch (e: Exception) { runOnUiThread { result.error("scan", e.message, null) } }
                    }
                }
                "rename" -> {
                    worker.execute {
                    try {
                        val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("Missing URI"))
                        require(uri.scheme == "content") { "Expected a document URI" }
                        val name = call.argument<String>("name") ?: throw IllegalArgumentException("Missing name")
                        require(name.isNotBlank() && !name.contains('/') && !name.contains('\\')) { "Invalid name" }
                        val changed = DocumentsContract.renameDocument(contentResolver, uri, name)
                            ?: throw IllegalStateException("Provider refused rename")
                        runOnUiThread { result.success(changed.toString()) }
                    } catch (e: Exception) { runOnUiThread { result.error("permission", "Could not rename. Reconnect the folder and allow write access.", null) } }
                    }
                }
                "delete" -> {
                    worker.execute {
                    try {
                        val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("Missing URI"))
                        require(uri.scheme == "content") { "Expected a document URI" }
                        if (!DocumentsContract.deleteDocument(contentResolver, uri)) throw IllegalStateException("Provider refused deletion")
                        runOnUiThread { result.success(null) }
                    } catch (e: Exception) { runOnUiThread { result.error("permission", "Could not delete. Reconnect the folder and allow write access.", null) } }
                    }
                }
                "read" -> {
                    val uri = call.argument<String>("uri")
                    val limit = call.argument<Int>("limit") ?: 104857600
                    worker.execute {
                        try {
                            val parsed = Uri.parse(uri ?: throw IllegalArgumentException("Missing URI"))
                            if (parsed.scheme != "content") throw IllegalArgumentException("Expected a document URI")
                            val output = ByteArrayOutputStream()
                            contentResolver.openInputStream(parsed)?.use { input ->
                                val buffer = ByteArray(65536)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    if (output.size().toLong() + count > limit) throw IllegalArgumentException("Document exceeds 100 MB")
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

    override fun onDestroy() {
        folderResult?.success(false)
        folderResult = null
        worker.shutdown()
        super.onDestroy()
    }

    @Deprecated("Uses FlutterActivity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
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
