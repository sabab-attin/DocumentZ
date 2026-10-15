
package com.example.documentz

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.Locale

/** Access is checked before every operation, including after revocation. */
class DeviceStorageAccess(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    @Volatile private var closed = false
    private val request = 8433
    fun allowed(): Boolean = if (Build.VERSION.SDK_INT >= 30) {
        Environment.isExternalStorageManager()
    } else {
        activity.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED &&
        activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    }
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "storageAccess" -> result.success(allowed())
            "requestStorageAccess" -> {
                if (allowed()) {
                    result.success(true)
                } else if (pending != null) {
                    result.error("busy", "A storage request is already open.", null)
                } else {
                    pending = result
                    try {
                        if (Build.VERSION.SDK_INT >= 30) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                Uri.parse("package:" + activity.packageName))
                            try {
                                activity.startActivityForResult(intent, request)
                            } catch (_: android.content.ActivityNotFoundException) {
                                activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION), request)
                            }
                        } else {
                            activity.requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE,
                                Manifest.permission.WRITE_EXTERNAL_STORAGE), request)
                        }
                    } catch (_: Exception) {
                        pending = null
                        result.error("permission", "Could not open storage permission settings.", null)
                    }
                }
            }
            else -> return false
        }
        return true
    }
    fun activityResult(code: Int): Boolean {
        if (code != request) return false
        finish()
        return true
    }
    fun permissionResult(code: Int): Boolean {
        if (code != request) return false
        finish()
        return true
    }
    private fun finish() {
        val result = pending
        pending = null
        result?.success(allowed())
    }
    fun close() {
        closed = true
        pending?.success(false)
        pending = null
    }
    private fun roots(): List<File> {
        val paths = mutableListOf(Environment.getExternalStorageDirectory())
        activity.getExternalFilesDirs(null).filterNotNull().forEach { file ->
            val root = file.absolutePath.substringBefore("/Android/")
            paths.add(File(root))
        }
        if (Build.VERSION.SDK_INT >= 30) {
            val storage = activity.getSystemService(StorageManager::class.java)
            storage.storageVolumes.forEach { volume -> volume.directory?.let { paths.add(it) } }
        }
        return paths.mapNotNull {
            try { it.canonicalFile } catch (_: Exception) { null }
        }.distinctBy { it.path }
    }
    private fun blocked(file: File, root: File): Boolean {
        val relative = file.path.removePrefix(root.path).trimStart('/')
        return relative == "Android/data" || relative.startsWith("Android/data/") ||
            relative == "Android/obb" || relative.startsWith("Android/obb/")
    }
    private fun checked(uri: Uri): File {
        require(allowed()) { "Storage access is required." }
        require(uri.scheme == "file") { "Expected a local file." }
        val file = File(uri.path ?: throw IllegalArgumentException("Missing path")).canonicalFile
        require(roots().any { root ->
            file.path.startsWith(root.path + File.separator) && !blocked(file, root)
        }) { "File is outside shared storage." }
        return file
    }
    fun read(uri: Uri): InputStream = checked(uri).inputStream()
    fun rename(uri: Uri, name: String): String {
        require(name.isNotBlank() && name != "." && name != ".." &&
            !name.contains('/') && !name.contains('\\')) { "Invalid file name." }
        val file = checked(uri)
        require(file.isFile) { "Not a file." }
        require(file.extension.equals(File(name).extension, ignoreCase = true)) { "Keep the file extension." }
        val destination = File(file.parentFile, name)
        checked(Uri.fromFile(destination))
        require(!destination.exists()) { "A file with this name already exists." }
        check(file.renameTo(destination)) { "Could not rename this file." }
        return Uri.fromFile(destination).toString()
    }
    fun delete(uri: Uri) {
        val file = checked(uri)
        require(file.isFile) { "Not a file." }
        check(file.delete()) { "Could not delete this file." }
    }
    fun sharedPath(uri: Uri): String? {
        if (uri.authority != "com.android.externalstorage.documents") return null
        return try {
            val id = if (android.provider.DocumentsContract.isTreeUri(uri))
                android.provider.DocumentsContract.getTreeDocumentId(uri)
                else android.provider.DocumentsContract.getDocumentId(uri)
            val volume = id.substringBefore(':')
            val relative = id.substringAfter(':', "")
            val root = if (volume == "primary") Environment.getExternalStorageDirectory()
                else roots().firstOrNull { it.name.equals(volume, ignoreCase = true) }
            root?.let { File(it, relative).canonicalPath }
        } catch (_: Exception) { null }
    }
    fun connectedIdentity(item: Map<String, Any>, folders: List<String>): Map<String, Any> {
        val path = Uri.parse(item["uri"] as String).path ?: return item
        for (folder in folders) {
            val tree = Uri.parse(folder)
            val root = sharedPath(tree) ?: continue
            if (path.startsWith(root.trimEnd('/') + "/")) {
                val relative = path.removePrefix(root.trimEnd('/') + "/")
                val id = android.provider.DocumentsContract.getTreeDocumentId(tree).trimEnd('/') + "/" + relative
                val uri = android.provider.DocumentsContract.buildDocumentUriUsingTree(tree, id)
                return item + mapOf("uri" to uri.toString(), "folder" to folder)
            }
        }
        return item
    }

    fun scan(extensions: Set<String>): List<Map<String, Any>> {
        if (!allowed()) return emptyList()
        val files = linkedMapOf<String, Map<String, Any>>()
        val visited = mutableSetOf<String>()
        for (root in roots()) {
            val queue = java.util.ArrayDeque<File>()
            queue.add(root)
            while (queue.isNotEmpty()) {
                if (closed || Thread.currentThread().isInterrupted || !allowed()) return files.values.toList()
                val directory = queue.removeFirst()
                try {
                    val real = directory.canonicalFile
                    if (real != root && !real.path.startsWith(root.path + File.separator)) continue
                    if (blocked(real, root) || !visited.add(real.path)) continue
                    real.listFiles()?.forEach { entry ->
                        try {
                        val canonical = entry.canonicalFile
                        if (!canonical.path.startsWith(root.path + File.separator) || blocked(canonical, root)) return@forEach
                        if (canonical.isDirectory) {
                            queue.add(canonical)
                        } else if (canonical.isFile && canonical.canRead() &&
                            extensions.contains(canonical.extension.lowercase(Locale.ROOT))) {
                            val location = Uri.fromFile(canonical).toString()
                            files[canonical.path] = mapOf("uri" to location, "name" to canonical.name,
                                "folder" to root.path, "size" to canonical.length(), "modified" to canonical.lastModified())
                        }
                        } catch (_: Exception) { /* Continue with other entries. */ }
                    }
                } catch (_: Exception) {
                    // Inaccessible directories do not stop discovery elsewhere.
                }
            }
        }
        return files.values.toList()
    }
}
