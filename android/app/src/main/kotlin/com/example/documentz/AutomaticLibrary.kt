package com.example.documentz

import android.Manifest
import android.app.job.*
import android.content.*
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.*
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.AtomicFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/** A separate metadata journal: never races Flutter's saved index file. */
object AutomaticLibrary {
    const val PERIODIC = 57411
    const val CONTENT = 57412
    val worker = Executors.newSingleThreadExecutor()
    @Volatile var onSeeded: (() -> Unit)? = null
    @Volatile var onDelta: ((Long) -> Unit)? = null
    private val extensions = setOf("pdf", "epub", "mobi", "txt", "md", "markdown", "docx", "xlsx", "pptx", "odt", "ods", "odp", "rtf", "html", "htm", "mhtml", "mht")
    fun supported(name: String) = name.lastIndexOf('.') > 0 && name.substringAfterLast('.', "").lowercase(java.util.Locale.ROOT) in extensions
    private fun allowed(c: Context) = if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager()
        else c.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED &&
            c.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    fun folders(c: Context) = c.contentResolver.persistedUriPermissions.filter { it.isReadPermission && DocumentsContract.isTreeUri(it.uri) }.map { it.uri.toString() }
    fun roots(c: Context): List<File> {
        val roots = mutableListOf(Environment.getExternalStorageDirectory())
        c.getExternalFilesDirs(null).filterNotNull().forEach { roots.add(File(it.path.substringBefore("/Android/"))) }
        if (Build.VERSION.SDK_INT >= 30) c.getSystemService(StorageManager::class.java).storageVolumes.forEach { it.directory?.let(roots::add) }
        return roots.mapNotNull { runCatching { it.canonicalFile }.getOrNull() }.distinctBy { it.path }
    }
    fun scope(c: Context): String = allowed(c).toString() + ":" + roots(c).map { it.path }.sorted().joinToString("|") + ":" +
        c.contentResolver.persistedUriPermissions.filter { it.isReadPermission }.map { it.uri.toString() }.sorted().joinToString("|")
    private fun shared(file: File, roots: List<File>): Boolean = roots.any {
        val relative = file.path.removePrefix(it.path).trimStart('/')
        file.path.startsWith(it.path + "/") && relative != "Android/data" && !relative.startsWith("Android/data/") && relative != "Android/obb" && !relative.startsWith("Android/obb/")
    }
    private fun pathFor(c: Context, uri: Uri, roots: List<File>): File? {
        if (uri.scheme == "file") return uri.path?.let(::File)
        if (uri.authority != "com.android.externalstorage.documents") return null
        return runCatching {
            val id = if (uri.pathSegments.contains("document")) DocumentsContract.getDocumentId(uri) else DocumentsContract.getTreeDocumentId(uri)
            val root = if (id.substringBefore(':') == "primary") Environment.getExternalStorageDirectory()
                else roots.firstOrNull { it.name.equals(id.substringBefore(':'), true) } ?: return null
            File(root, id.substringAfter(':', "")).canonicalFile
        }.getOrNull()
    }
    private fun identity(c: Context, file: File, roots: List<File>, folders: List<String>): String {
        for (folder in folders) {
            val tree = Uri.parse(folder)
            val root = pathFor(c, tree, roots) ?: continue
            if (file.path.startsWith(root.path.trimEnd('/') + "/")) {
                val id = DocumentsContract.getTreeDocumentId(tree).trimEnd('/') + "/" + file.path.removePrefix(root.path.trimEnd('/') + "/")
                return DocumentsContract.buildDocumentUriUsingTree(tree, id).toString()
            }
        }
        return Uri.fromFile(file).toString()
    }
    private fun stateFile(c: Context) = AtomicFile(File(c.filesDir, ".automatic-library-v1.json"))
    private fun read(c: Context): JSONObject = try { stateFile(c).openRead().use { JSONObject(it.bufferedReader().readText()) } } catch (_: Exception) { JSONObject() }
    private fun write(c: Context, value: JSONObject) {
        val file = stateFile(c)
        val output = file.startWrite()
        try { output.write(value.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(output) }
        catch (e: Exception) { file.failWrite(output); throw e }
    }
    private fun array(value: JSONArray?): List<JSONObject> = if (value == null) emptyList() else (0 until value.length()).map { value.getJSONObject(it) }
    private fun strings(value: JSONArray?): Set<String> = if (value == null) emptySet() else (0 until value.length()).map { value.getString(it) }.toSet()

    /** Seed watched directory stamps from the existing one-time scan, not another crawl. */
    fun seed(c: Context, directories: Set<String>) {
        val app = c.applicationContext
        val copy = directories.toList()
        worker.execute {
            synchronized(this) {
                val state = read(app)
                if (state.optString("scope") != scope(app)) return@synchronized
                val dirs = state.optJSONObject("dirs") ?: JSONObject()
                val common = roots(app).flatMap { listOf(File(it, "Download"), File(it, "Documents")) }
                for (path in copy) if (common.any { path == it.path || path.startsWith(it.path + "/") }) {
                    // Zero forces a first direct-folder check for files absent from MediaStore.
                    if (!dirs.has(path)) dirs.put(path, 0)
                }
                state.put("dirs", dirs)
                write(app, state)
            }
            onSeeded?.invoke()
        }
    }

    @Synchronized fun refresh(c: Context, forced: Set<String> = emptySet()): Long {
        val signature = scope(c)
        var state = read(c)
        if (state.optString("scope") != signature) state = JSONObject().put("scope", signature)
        val roots = roots(c)
        val folders = folders(c)
        val previous = array(state.optJSONArray("files")).associateBy { it.getString("uri") }.toMutableMap()
        // Reconcile against the complete cached list too, including files not in MediaStore.
        val baseline = runCatching { JSONObject(File(c.filesDir, "library/.device-index-v1.json").readText()) }.getOrNull()
        if (baseline?.optString("scope") == "browse-v1:$signature") array(baseline.optJSONArray("files")).forEach { previous.putIfAbsent(it.getString("uri"), it) }
        val current = previous.toMutableMap()
        val dirs = state.optJSONObject("dirs") ?: JSONObject()
        val seenDirectories = mutableSetOf<String>()
        val broad = allowed(c)
        fun put(file: File) {
            try {
                val real = file.canonicalFile
                if (!shared(real, roots) || !real.isFile || !supported(real.name)) return
                val uri = identity(c, real, roots, folders)
                val folder = folders.firstOrNull { uri.startsWith(it) } ?: roots.firstOrNull { real.path.startsWith(it.path + "/") }?.path ?: ""
                current[uri] = JSONObject().put("uri", uri).put("name", real.name).put("folder", folder).put("size", real.length()).put("modified", real.lastModified())
                real.parent?.let { if (!dirs.has(it)) dirs.put(it, 0) }
            } catch (_: Exception) { /* Retain metadata while a provider/storage volume is unavailable. */ }
        }
        if (broad) {
            for (entry in previous.values) {
                val file = pathFor(c, Uri.parse(entry.getString("uri")), roots) ?: continue
                try { if (shared(file.canonicalFile, roots)) { if (!file.exists()) current.remove(entry.getString("uri")) else put(file) } }
                catch (_: Exception) { /* An access failure is not a deletion. */ }
            }
            // Query Android's document rows, never recursively walk all storage.
            try {
                c.contentResolver.query(MediaStore.Files.getContentUri("external"), arrayOf("_data"),
                    extensions.joinToString(" OR ") { "_display_name LIKE ?" }, extensions.map { "%.$it" }.toTypedArray(), null)?.use { cursor ->
                    while (cursor.moveToNext() && !Thread.currentThread().isInterrupted) cursor.getString(0)?.let { put(File(it)) }
                }
            } catch (_: Exception) { /* Direct download/folder checks below remain available. */ }
            for (root in roots) for (name in listOf("Download", "Documents")) if (!dirs.has(File(root, name).path)) dirs.put(File(root, name).path, 0)
            val queue = java.util.ArrayDeque<String>()
            dirs.keys().forEach { queue.add(it) }
            while (queue.isNotEmpty() && !Thread.currentThread().isInterrupted) {
                val path = queue.removeFirst()
                if (!seenDirectories.add(path)) continue
                val directory = File(path)
                if (!shared(directory.canonicalFile, roots)) continue
                val modified = directory.lastModified()
                if (path !in forced && dirs.optLong(path, -1) == modified) continue
                val children = directory.listFiles() ?: continue
                dirs.put(path, modified)
                for (child in children) {
                    val real = runCatching { child.canonicalFile }.getOrNull() ?: continue
                    if (!shared(real, roots)) continue
                    if (real.isDirectory) {
                        if (!dirs.has(real.path)) { dirs.put(real.path, 0); queue.add(real.path) }
                    } else put(real)
                }
            }
        } else {
            // Scoped providers have their own change notifications. Work stays off the UI.
            for (folder in folders) {
                val tree = Uri.parse(folder)
                val queue = java.util.ArrayDeque<String>()
                val visited = mutableSetOf<String>()
                val found = mutableMapOf<String, JSONObject>()
                var complete = true
                queue.add(DocumentsContract.getTreeDocumentId(tree))
                while (queue.isNotEmpty() && !Thread.currentThread().isInterrupted) {
                    val parent = queue.removeFirst()
                    if (!visited.add(parent)) continue
                    try {
                        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
                        c.contentResolver.query(uri, arrayOf("document_id", "_display_name", "mime_type", "_size", "last_modified"), null, null, null)?.use { cursor ->
                            while (cursor.moveToNext()) {
                                val id = cursor.getString(0)
                                val name = cursor.getString(1) ?: continue
                                if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) queue.add(id)
                                else if (supported(name)) {
                                    val location = DocumentsContract.buildDocumentUriUsingTree(tree, id).toString()
                                    found[location] = JSONObject().put("uri", location).put("name", name).put("folder", folder).put("size", cursor.getLong(3)).put("modified", cursor.getLong(4))
                                }
                            }
                        } ?: run { complete = false }
                    } catch (_: Exception) { complete = false }
                }
                if (complete && queue.isEmpty()) current.entries.removeAll { it.value.optString("folder") == folder }
                current.putAll(found)
            }
        }
        if (Thread.currentThread().isInterrupted) return state.optLong("revision", 0)
        val removed = strings(state.optJSONArray("removed")).toMutableSet()
        removed.addAll(previous.keys - current.keys)
        removed.removeAll(current.keys)
        fun same(a: JSONObject, b: JSONObject) = a.optString("name") == b.optString("name") && a.optString("folder") == b.optString("folder") && a.optLong("size") == b.optLong("size") && a.optLong("modified") == b.optLong("modified")
        val old = array(state.optJSONArray("files")).associateBy { it.getString("uri") }
        val changed = old.keys != current.keys || current.any { (key, value) -> old[key]?.let { same(it, value) } != true } || removed != strings(state.optJSONArray("removed"))
        val revision = state.optLong("revision", 0) + if (changed) 1 else 0
        state.put("revision", revision).put("files", JSONArray(current.values.toList())).put("dirs", dirs).put("removed", JSONArray(removed.toList()))
        write(c, state)
        if (changed) onDelta?.invoke(revision)
        return revision
    }

    @Synchronized fun changes(c: Context): Map<String, Any> {
        val value = read(c)
        if (value.optString("scope") != scope(c)) return mapOf("revision" to 0L, "files" to emptyList<Any>(), "removed" to emptyList<String>())
        return mapOf("scope" to value.getString("scope"), "revision" to value.optLong("revision", 0), "files" to array(value.optJSONArray("files")).map {
            mapOf("uri" to it.getString("uri"), "name" to it.getString("name"), "folder" to it.getString("folder"), "size" to it.getLong("size"), "modified" to it.getLong("modified"))
        }, "removed" to strings(value.optJSONArray("removed")).toList())
    }
    @Synchronized fun acknowledge(c: Context, revision: Long) {
        val value = read(c)
        if (value.optLong("revision", -1) == revision) { value.put("removed", JSONArray()); write(c, value) }
    }
    fun watchDirectories(c: Context): List<File> {
        val value = synchronized(this) { read(c) }
        val paths = mutableSetOf<String>()
        roots(c).forEach { paths.add(File(it, "Download").path); paths.add(File(it, "Documents").path) }
        value.optJSONObject("dirs")?.keys()?.forEach { paths.add(it) }
        return paths.map(::File).filter { it.isDirectory }.take(512)
    }
    fun schedule(c: Context) {
        val scheduler = c.getSystemService(JobScheduler::class.java)
        if (!allowed(c) && folders(c).isEmpty()) { scheduler.cancel(PERIODIC); scheduler.cancel(CONTENT); return }
        if (scheduler.getPendingJob(PERIODIC) == null) scheduler.schedule(JobInfo.Builder(PERIODIC, ComponentName(c, AutomaticLibraryJob::class.java))
            .setPersisted(true).setPeriodic(15 * 60 * 1000L).build())
        contentJob(c)
    }
    fun contentJob(c: Context) {
        val builder = JobInfo.Builder(CONTENT, ComponentName(c, AutomaticLibraryJob::class.java))
            .addTriggerContentUri(JobInfo.TriggerContentUri(Uri.parse("content://media"), JobInfo.TriggerContentUri.FLAG_NOTIFY_FOR_DESCENDANTS))
            .setTriggerContentUpdateDelay(2000).setTriggerContentMaxDelay(15000)
        for (folder in folders(c)) builder.addTriggerContentUri(JobInfo.TriggerContentUri(Uri.parse(folder), JobInfo.TriggerContentUri.FLAG_NOTIFY_FOR_DESCENDANTS))
        c.getSystemService(JobScheduler::class.java).schedule(builder.build())
    }
}

class AutomaticLibraryJob : JobService() {
    private var work: java.util.concurrent.Future<*>? = null
    override fun onStartJob(params: JobParameters): Boolean {
        work = AutomaticLibrary.worker.submit {
            try { AutomaticLibrary.refresh(this) } catch (_: Exception) { /* Keep the previous index on transient failures. */ }
            finally {
                jobFinished(params, false)
                if (params.jobId == AutomaticLibrary.CONTENT) Handler(Looper.getMainLooper()).post { AutomaticLibrary.schedule(this) }
            }
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean { work?.cancel(true); return true }
}

class AutomaticLibraryBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) AutomaticLibrary.schedule(context)
    }
}

class AutomaticLibraryBridge(private val activity: FlutterActivity, engine: FlutterEngine) {
    private val context = activity.applicationContext
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "documentz/library_index")
    private val handler = Handler(Looper.getMainLooper())
    @Volatile private var closed = false
    private var queued = false
    private var running = false
    private var again = false
    private var deliveredRevision = -1L
    private var watchedPaths = emptySet<String>()
    private var registeredFolders = emptySet<String>()
    private val dirtyDirectories = mutableSetOf<String>()
    private val watchers = mutableListOf<FileObserver>()
    private val observer = object : ContentObserver(handler) { override fun onChange(selfChange: Boolean, uri: Uri?) {
        if (uri?.pathSegments?.any { it in setOf("images", "audio", "video") } != true) requestRefresh()
    } }
    private val refresh: Runnable = Runnable {
        queued = false
        running = true
        val forced = dirtyDirectories.toSet()
        dirtyDirectories.clear()
        AutomaticLibrary.worker.execute {
            try {
                val revision = AutomaticLibrary.refresh(context, forced)
                val directories = AutomaticLibrary.watchDirectories(context)
                handler.post { if (!closed) {
                    updateWatchers(directories)
                    if (revision != deliveredRevision) { deliveredRevision = revision; channel.invokeMethod("changed", null) }
                } }
            } catch (_: Exception) { /* The persisted index remains usable. */ }
            finally { handler.post { running = false; if (!closed && again) { again = false; requestRefresh() } } }
        }
    }
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> { AutomaticLibrary.schedule(context); requestRefresh(); result.success(null) }
                "changes" -> AutomaticLibrary.worker.execute {
                    try { val value = AutomaticLibrary.changes(context); if (!closed) result.success(value) }
                    catch (_: Exception) { if (!closed) result.error("index", "Could not load file changes.", null) }
                }
                "acknowledge" -> {
                    val revision = call.argument<Number>("revision")?.toLong() ?: -1
                    AutomaticLibrary.worker.execute {
                        try { AutomaticLibrary.acknowledge(context, revision); if (!closed) result.success(null) }
                        catch (_: Exception) { if (!closed) result.error("index", "Could not save the file-change acknowledgement.", null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
        runCatching { context.contentResolver.registerContentObserver(Uri.parse("content://media"), true, observer) }
        foldersObserver()
        AutomaticLibrary.schedule(context)
        AutomaticLibrary.onSeeded = { handler.post { requestRefresh() } }
        AutomaticLibrary.onDelta = { revision -> handler.post {
            if (!closed && revision != deliveredRevision) { deliveredRevision = revision; channel.invokeMethod("changed", null) }
        } }
        requestRefresh()
    }
    private fun foldersObserver() {
        val folders = AutomaticLibrary.folders(context).toSet()
        if (folders == registeredFolders) return
        context.contentResolver.unregisterContentObserver(observer)
        runCatching { context.contentResolver.registerContentObserver(Uri.parse("content://media"), true, observer) }
        for (folder in folders) runCatching { context.contentResolver.registerContentObserver(Uri.parse(folder), true, observer) }
        registeredFolders = folders
    }
    private fun requestRefresh(path: String? = null) {
        if (closed) return
        if (path != null) dirtyDirectories.add(path)
        if (running) { again = true; return }
        if (!queued) { queued = true; handler.postDelayed(refresh, 1500) }
    }
    @Suppress("DEPRECATION")
    private fun updateWatchers(directories: List<File>) {
        foldersObserver()
        val paths = directories.map { it.path }.toSet()
        if (paths == watchedPaths) return
        watchedPaths = paths
        watchers.forEach { it.stopWatching() }
        watchers.clear()
        for (directory in directories) {
            val watcher = object : FileObserver(directory.path, CLOSE_WRITE or MOVED_TO or MOVED_FROM or DELETE or CREATE or DELETE_SELF or MOVE_SELF) {
                override fun onEvent(event: Int, path: String?) {
                    if (path == null || AutomaticLibrary.supported(path) || event and (CREATE or MOVED_TO or MOVED_FROM or DELETE_SELF or MOVE_SELF) != 0) handler.post { requestRefresh(directory.path) }
                }
            }
            runCatching { watcher.startWatching(); watchers.add(watcher) }
        }
    }
    fun resume() { requestRefresh() }
    fun close() {
        closed = true
        AutomaticLibrary.onSeeded = null
        AutomaticLibrary.onDelta = null
        handler.removeCallbacks(refresh)
        watchers.forEach { it.stopWatching() }
        watchers.clear()
        context.contentResolver.unregisterContentObserver(observer)
        channel.setMethodCallHandler(null)
    }
}
