package com.example.documentz

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class DocumentOpenBridge(private val activity: FlutterActivity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "documentz/documents")
    private val worker = Executors.newSingleThreadExecutor()
    private val queue = ArrayDeque<Pair<Uri, String?>>()
    private val staged = mutableMapOf<String, File>()
    private var closed = false
    private val formats = setOf("pdf", "epub", "txt", "md", "markdown", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "odt", "ods", "odp", "rtf", "html", "htm", "mhtml", "mht", "mobi", "png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "svg", "eps", "ps")

    init {
        val root = File(activity.cacheDir, "incoming-documents").apply { mkdirs() }
        // Only stale temporary imports, never library documents.
        root.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86400000 }?.forEach { it.delete() }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeDocument" -> {
                    val next = queue.removeFirstOrNull()
                    if (next == null) result.success(null) else worker.execute {
                        var copied: File? = null
                        try {
                            val uri = next.first
                            var name: String? = null
                            if (uri.scheme == "content") {
                                runCatching {
                                    activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                                        if (cursor.moveToFirst()) name = cursor.getString(0)
                                    }
                                }
                            }
                            name = name?.substringAfterLast('/')?.substringAfterLast('\\')?.take(240)
                                ?: uri.lastPathSegment?.substringAfterLast('/')?.take(240) ?: "document"
                            var extension = name.substringAfterLast('.', "").lowercase()
                            if (extension !in formats) {
                                val mime = (next.second ?: activity.contentResolver.getType(uri))?.substringBefore(';')?.lowercase()
                                extension = when (mime) {
                                    "application/epub+zip", "application/x-epub+zip" -> "epub"
                                    "application/x-mobipocket-ebook", "application/vnd.amazon.ebook" -> "mobi"
                                    "text/markdown", "text/x-markdown" -> "md"
                                    else -> MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: ""
                                }
                                require(extension in formats) { "This document format is not supported." }
                                name = "$name.$extension"
                            }
                            val id = UUID.randomUUID().toString()
                            copied = File(root, "$id.$extension")
                            activity.contentResolver.openInputStream(uri)?.use { input ->
                                copied.outputStream().use { output -> input.copyTo(output, 65536) }
                            } ?: throw IllegalArgumentException("The file provider did not return a readable document.")
                            val ready = copied
                            activity.runOnUiThread {
                                if (closed) ready.delete() else {
                                    staged[id] = ready
                                    result.success(mapOf("id" to id, "name" to name, "path" to ready.absolutePath))
                                }
                            }
                        } catch (_: Exception) {
                            copied?.delete()
                            activity.runOnUiThread {
                                if (!closed) result.error("document_open", "Could not open this file. Check that it is supported, available locally and that storage has enough space.", null)
                            }
                        }
                    }
                }
                "finishDocument" -> { staged.remove(call.argument<String>("id"))?.delete(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        handleIntent(activity.intent)
    }

    @Suppress("DEPRECATION")
    fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (android.os.Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java) else intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        } ?: return
        if (uri.scheme !in setOf("content", "file")) return
        if (uri.scheme == "file") {
            val file = File(uri.path ?: return).canonicalFile
            if (file.path.startsWith(File(activity.applicationInfo.dataDir).canonicalPath + File.separator)) return
        }
        if (queue.size >= 16) {
            Toast.makeText(activity, "Finish opening the current documents, then try again.", Toast.LENGTH_LONG).show()
            return
        }
        queue.addLast(uri to intent.type)
        intent.action = null
        intent.data = null
        intent.removeExtra(Intent.EXTRA_STREAM)
        channel.invokeMethod("documentAvailable", null)
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        staged.values.forEach { it.delete() }
        staged.clear()
        worker.shutdown()
    }
}
