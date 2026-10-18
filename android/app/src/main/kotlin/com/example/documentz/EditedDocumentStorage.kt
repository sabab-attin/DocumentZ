package com.example.documentz

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import java.io.File

/** Writes public Downloads copies, never overwriting an existing document. */
object EditedDocumentStorage {
    @Synchronized
    fun save(context: Context, entries: List<Map<String, String>>): List<String> {
        require(entries.isNotEmpty()) { "No edited files to save." }
        val cacheRoot = context.cacheDir.canonicalFile
        val sources = entries.map { entry ->
            val source = File(requireNotNull(entry["path"])).canonicalFile
            require(source.path.startsWith(cacheRoot.path + File.separator) && source.isFile) { "Invalid temporary output." }
            val name = requireNotNull(entry["name"])
            require(name.isNotBlank() && name != "." && name != ".." &&
                name.none { it == '/' || it == '\\' || it.code < 32 }) { "Invalid output name." }
            source to name
        }
        val resolver = context.contentResolver
        val uris = mutableListOf<Uri>()
        val files = mutableListOf<File>()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                for ((source, name) in sources) {
                    val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
                        ?: "application/octet-stream"
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                        put(MediaStore.MediaColumns.MIME_TYPE, mime)
                        put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/DocumentZ")
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        ?: error("Could not create the Downloads copy. Check free storage.")
                    uris.add(uri)
                    val output = resolver.openOutputStream(uri, "w") ?: error("Could not open the Downloads copy.")
                    output.use { out -> source.inputStream().use { it.copyTo(out) } }
                }
                for (uri in uris) {
                    check(resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1)
                }
                return uris.map { it.toString() }
            }
            @Suppress("DEPRECATION")
            val downloads = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DocumentZ")
            check(downloads.isDirectory || downloads.mkdirs()) { "Allow storage access and check free space in Downloads." }
            for ((source, name) in sources) {
                var target = File(downloads, name)
                var suffix = 1
                while (!target.createNewFile()) {
                    val dot = name.lastIndexOf('.')
                    val stem = if (dot > 0) name.substring(0, dot) else name
                    val extension = if (dot > 0) name.substring(dot) else ""
                    target = File(downloads, "$stem (${suffix++})$extension")
                }
                files.add(target)
                target.outputStream().use { out -> source.inputStream().use { it.copyTo(out) } }
            }
            MediaScannerConnection.scanFile(context, files.map { it.path }.toTypedArray(), null, null)
            return files.map { it.path }
        } catch (error: Exception) {
            for (uri in uris) { runCatching { resolver.delete(uri, null, null) } }
            for (file in files) { runCatching { file.delete() } }
            throw error
        }
    }
}
