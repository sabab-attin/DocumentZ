package com.example.documentz

import android.Manifest
import android.app.*
import android.app.job.*
import android.content.*
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

object AppUpdates {
    private const val JOB = 57403
    private const val NOTICE = 57404
    private const val CHANNEL = "documentz_updates"
    const val DOWNLOAD = "com.example.quiet_reader.UPDATE_DOWNLOAD"
    const val INSTALL = "com.example.quiet_reader.UPDATE_INSTALL"
    val worker = Executors.newSingleThreadExecutor()
    val verificationWorker = Executors.newSingleThreadExecutor()
    private fun prefs(c: Context) = c.getSharedPreferences("documentz.updates.v1", Context.MODE_PRIVATE)
    @Suppress("DEPRECATION")
    private fun installed(c: Context) = c.packageManager.getPackageInfo(c.packageName, 0)
    private fun manager(c: Context) = c.getSystemService(DownloadManager::class.java)
    private fun notifications(c: Context): Boolean =
        c.getSystemService(NotificationManager::class.java).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)

    fun state(c: Context): Map<String, Any?> {
        val p = prefs(c)
        val release = p.getString("release", null)?.let { runCatching { JSONObject(it) }.getOrNull() }
        val version = installed(c).versionName ?: ""
        val available = release != null && UpdatePolicy.newer(release.getString("tag"), version)
        var progress = ""
        var recoverDownload = false
        val downloadId = p.getLong("download", -1)
        if (downloadId >= 0) manager(c).query(DownloadManager.Query().setFilterById(downloadId))?.use { cursor ->
            if (cursor.moveToFirst()) {
                val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                val bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                if (status in listOf(DownloadManager.STATUS_RUNNING, DownloadManager.STATUS_PENDING, DownloadManager.STATUS_PAUSED)) {
                    progress = if (total > 0) "Downloading update: ${bytes * 100 / total}%" else "Waiting for the update download…"
                } else if (status == DownloadManager.STATUS_FAILED) {
                    p.edit().remove("download").putString("status", "Download failed. Check your connection and storage, then retry.").apply()
                } else if (status == DownloadManager.STATUS_SUCCESSFUL && !p.getBoolean("ready", false)) recoverDownload = true
            } else p.edit().remove("download").apply()
        }
        if (recoverDownload) completed(c, downloadId)
        if (!available && release != null) {
            c.getSystemService(NotificationManager::class.java).cancel(NOTICE)
            p.edit().remove("ready").remove("release").apply()
        }
        return mapOf("version" to version, "automatic" to p.getBoolean("automatic", false),
            "notifications" to notifications(c), "available" to if (available) release.getString("tag") else null,
            "ready" to (available && p.getBoolean("ready", false)), "downloading" to progress.isNotEmpty(),
            "status" to progress.ifEmpty { p.getString("status", "Check GitHub for a newer version.") },
            "lastChecked" to p.getLong("lastChecked", 0))
    }

    fun schedule(c: Context, enabled: Boolean) {
        val scheduler = c.getSystemService(JobScheduler::class.java)
        if (enabled) {
            val result = scheduler.schedule(JobInfo.Builder(JOB, ComponentName(c, UpdateCheckJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true)
                .setPeriodic(6 * 60 * 60 * 1000L).build())
            check(result == JobScheduler.RESULT_SUCCESS) { "Android could not schedule update checks." }
        } else {
            scheduler.cancel(JOB)
            c.getSystemService(NotificationManager::class.java).cancel(NOTICE)
        }
        prefs(c).edit().putBoolean("automatic", enabled).apply()
    }

    fun resume(c: Context) {
        if (!prefs(c).getBoolean("automatic", false)) return
        schedule(c, true)
        if (System.currentTimeMillis() - prefs(c).getLong("lastChecked", 0) >= 6 * 60 * 60 * 1000L) check(c, background = true)
    }

    private fun json(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15000
        connection.readTimeout = 20000
        connection.instanceFollowRedirects = false
        connection.setRequestProperty("User-Agent", "DocumentZ-Updater")
        connection.setRequestProperty("Accept", "application/vnd.github+json")
        try {
            check(connection.responseCode == 200) {
                if (connection.responseCode == 403 || connection.responseCode == 429) "GitHub is limiting update checks. Try again later." else "Could not check GitHub for updates. Try again later."
            }
            connection.inputStream.use { input ->
                val data = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(data.size() + count <= 1024 * 1024) { "The release response is too large." }
                    data.write(buffer, 0, count)
                }
                return data.toString("UTF-8")
            }
        } finally { connection.disconnect() }
    }

    fun check(c: Context, background: Boolean = false) {
        val p = prefs(c)
        // Only the public release feed is contacted; no documents or device IDs.
        val response = JSONObject(json("https://api.github.com/repos/sabab-attin/DocumentZ/releases/latest"))
        require(!response.optBoolean("draft") && !response.optBoolean("prerelease")) { "No stable release is available." }
        val tag = response.getString("tag_name")
        require(UpdatePolicy.version(tag) != null) { "The release needs a stable version tag, such as v1.0.4." }
        if (!UpdatePolicy.newer(tag, installed(c).versionName ?: "")) {
            p.edit().remove("release").remove("ready").putLong("lastChecked", System.currentTimeMillis()).putString("status", "You’re up to date.").apply()
            c.getSystemService(NotificationManager::class.java).cancel(NOTICE)
            return
        }
        val filename = UpdatePolicy.assetName(Build.SUPPORTED_ABIS.toList()) ?: error("No update build is available for this architecture.")
        val assets = response.getJSONArray("assets")
        val asset = (0 until assets.length()).map { assets.getJSONObject(it) }.firstOrNull { it.optString("name") == filename && it.optString("state") == "uploaded" }
            ?: error("The release APK is not uploaded yet. Try again later.")
        val digest = asset.optString("digest")
        require(Regex("sha256:[a-fA-F0-9]{64}").matches(digest)) { "The release has no SHA-256 digest yet. Try again later." }
        val url = asset.getString("browser_download_url")
        require(UpdatePolicy.trustedAsset(url, tag, filename)) { "The release download address is invalid." }
        val size = asset.getLong("size")
        require(size in 1..262144000) { "The release APK size is invalid." }
        val release = JSONObject().put("tag", tag).put("name", filename).put("url", url).put("sha256", digest.substringAfter(':').lowercase()).put("size", size)
        val previous = p.getString("release", "")
        val changed = previous != release.toString()
        if (changed) {
            p.getLong("download", -1).takeIf { it >= 0 }?.let { manager(c).remove(it) }
            p.edit().remove("download").remove("ready").apply()
        }
        p.edit().putString("release", release.toString()).putLong("lastChecked", System.currentTimeMillis()).putString("status", "$tag is available.").apply()
        if (background && p.getBoolean("automatic", false) && p.getString("notified", "") != release.toString()) {
            if (notify(c, "DocumentZ $tag is available", "Tap to download the update.", DOWNLOAD)) {
                p.edit().putString("notified", release.toString()).apply()
            }
        }
    }

    fun failure(c: Context, error: Exception) {
        prefs(c).edit().putString("status", error.message ?: "Update failed. Try again.").apply()
    }

    @Suppress("DEPRECATION")
    private fun notify(c: Context, title: String, text: String, action: String): Boolean {
        if (!notifications(c)) return false
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "App updates", NotificationManager.IMPORTANCE_DEFAULT))
        val nonce = UUID.randomUUID().toString()
        prefs(c).edit().putString("notificationNonce", nonce).apply()
        val intent = Intent(c, MainActivity::class.java).setAction(action).putExtra("nonce", nonce).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(c, NOTICE, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
        manager.notify(NOTICE, builder.setSmallIcon(android.R.drawable.stat_sys_download_done).setContentTitle(title).setContentText(text)
            .setContentIntent(pending).setAutoCancel(true).build())
        return true
    }

    fun acceptNotification(c: Context, intent: Intent): String? {
        if (intent.action !in setOf(DOWNLOAD, INSTALL)) return null
        val p = prefs(c)
        val nonce = p.getString("notificationNonce", null) ?: return null
        if (intent.getStringExtra("nonce") != nonce) return null
        p.edit().remove("notificationNonce").apply()
        return intent.action.also { intent.action = null }
    }

    @Synchronized fun download(c: Context) {
        val p = prefs(c)
        val current = state(c)
        require(current["available"] != null) { "Check for a newer release first." }
        if (current["downloading"] == true || current["ready"] == true) return
        val release = JSONObject(p.getString("release", null) ?: error("Check for updates first."))
        require(UpdatePolicy.trustedAsset(release.getString("url"), release.getString("tag"), release.getString("name")))
        val root = File(c.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: error("Download storage is unavailable."), "updates").apply { mkdirs() }
        val filename = "documentz-${release.getString("tag")}.apk"
        val output = File(root, filename)
        if (output.exists()) check(output.delete()) { "Could not replace the previous download." }
        val request = DownloadManager.Request(Uri.parse(release.getString("url")))
            .setTitle("DocumentZ ${release.getString("tag")}")
            .setDescription("Downloading app update")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setAllowedOverRoaming(false)
            .setDestinationInExternalFilesDir(c, Environment.DIRECTORY_DOWNLOADS, "updates/$filename")
        val id = manager(c).enqueue(request)
        p.edit().putLong("download", id).putString("file", output.absolutePath).putString("downloadRelease", release.toString())
            .putBoolean("ready", false).putString("status", "Downloading update…").apply()
    }

    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> {
        val certs = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return certs?.map { cert -> MessageDigest.getInstance("SHA-256").digest(cert.toByteArray()).joinToString("") { "%02x".format(it) } }?.toSet() ?: emptySet()
    }

    @Suppress("DEPRECATION")
    fun verifiedFile(c: Context): File {
        val p = prefs(c)
        val release = JSONObject(p.getString("downloadRelease", null) ?: error("No update has been downloaded."))
        val root = File(c.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "updates").canonicalFile
        val file = File(p.getString("file", "")!!).canonicalFile
        require(file.parentFile == root && file.isFile && file.length() == release.getLong("size")) { "The update download is incomplete." }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input -> val buffer = ByteArray(65536); while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) } }
        require(digest.digest().joinToString("") { "%02x".format(it) } == release.getString("sha256")) { "The update checksum does not match. Download it again." }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = c.packageManager.getPackageArchiveInfo(file.path, flags) ?: error("The update is not a valid APK.")
        val local = c.packageManager.getPackageInfo(c.packageName, flags)
        val localCode = if (Build.VERSION.SDK_INT >= 28) local.longVersionCode else local.versionCode.toLong()
        val archiveCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        require(archive.packageName == c.packageName && archiveCode > localCode && UpdatePolicy.version(archive.versionName ?: "") == UpdatePolicy.version(release.getString("tag"))) { "This APK is not a newer compatible DocumentZ update." }
        val expected = signatures(local)
        require(expected.isNotEmpty() && signatures(archive) == expected) { "The update signing certificate does not match your installed app." }
        return file
    }

    @Synchronized fun completed(c: Context, id: Long) {
        val p = prefs(c)
        if (id < 0 || p.getLong("download", -1) != id) return
        var complete = false
        manager(c).query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
            complete = cursor.moveToFirst() && cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) == DownloadManager.STATUS_SUCCESSFUL
        }
        if (!complete) return
        val expectedRelease = p.getString("downloadRelease", null)
        try {
            verifiedFile(c)
            if (p.getLong("download", -1) != id || p.getString("release", null) != expectedRelease) return
            p.edit().putBoolean("ready", true).remove("download").putString("status", "Download verified. Ready to install.").apply()
            notify(c, "DocumentZ update is ready", "Tap to install. Android will ask for confirmation.", INSTALL)
        } catch (error: Exception) {
            manager(c).remove(id)
            if (p.getLong("download", -1) != id) return
            p.edit().remove("download").remove("ready").apply()
            failure(c, error)
            notify(c, "DocumentZ update could not be verified", "Open Settings → App updates and try again.", DOWNLOAD)
        }
    }
}

class UpdateCheckJob : JobService() {
    private var task: java.util.concurrent.Future<*>? = null
    override fun onStartJob(params: JobParameters): Boolean {
        task = AppUpdates.worker.submit {
            try { AppUpdates.check(this, background = true) } catch (error: Exception) { AppUpdates.failure(this, error) }
            jobFinished(params, false)
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean { task?.cancel(true); return true }
}

class UpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val pending = goAsync()
        AppUpdates.verificationWorker.execute {
            try { AppUpdates.completed(context, intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)) } finally { pending.finish() }
        }
    }
}

class AppUpdateBridge(private val activity: FlutterActivity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "documentz/updates")
    private var permissionResult: MethodChannel.Result? = null
    private var closed = false
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> run(result) { AppUpdates.state(activity) }
                "check" -> run(result) { AppUpdates.check(activity); AppUpdates.state(activity) }
                "download" -> run(result) { AppUpdates.download(activity); AppUpdates.state(activity) }
                "install" -> install(result)
                "automatic" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    if (enabled && Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) result.error("updates", "Finish the notification permission request first.", null)
                        else { permissionResult = result; activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 8441) }
                    } else run(result) {
                        AppUpdates.schedule(activity, enabled)
                        if (enabled) AppUpdates.check(activity, background = true)
                        AppUpdates.state(activity)
                    }
                }
                "notificationSettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(activity.intent)
        run(null) { AppUpdates.resume(activity); null }
    }
    private fun run(result: MethodChannel.Result?, action: () -> Any?) {
        AppUpdates.worker.execute {
            try {
                val value = action()
                activity.runOnUiThread { if (!closed) result?.success(value) }
            } catch (error: Exception) {
                AppUpdates.failure(activity, error)
                activity.runOnUiThread {
                    if (!closed) {
                        if (result != null) result.error("updates", error.message ?: "Could not update the app.", null)
                        else android.widget.Toast.makeText(activity, error.message ?: "Update failed. Open App updates in Settings.", android.widget.Toast.LENGTH_LONG).show()
                    }
                }
            }
        }
    }
    private fun install(result: MethodChannel.Result?) {
        run(result) {
            val file = AppUpdates.verifiedFile(activity)
            activity.runOnUiThread {
                if (!closed) {
                    try {
                        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                            android.widget.Toast.makeText(activity, "Allow updates from DocumentZ, then return and tap Install update.", android.widget.Toast.LENGTH_LONG).show()
                        } else {
                            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                            activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        }
                    } catch (_: Exception) {
                        android.widget.Toast.makeText(activity, "Android could not open the installer. Try again from App updates.", android.widget.Toast.LENGTH_LONG).show()
                    }
                }
            }
            AppUpdates.state(activity)
        }
    }
    fun handleIntent(intent: Intent?) {
        if (intent == null) return
        when (AppUpdates.acceptNotification(activity, intent)) {
            AppUpdates.DOWNLOAD -> run(null) { AppUpdates.download(activity); null }
            AppUpdates.INSTALL -> install(null)
        }
    }
    fun permissionResult(code: Int, grants: IntArray): Boolean {
        if (code != 8441) return false
        val result = permissionResult
        permissionResult = null
        if (grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED) {
            run(result) { AppUpdates.schedule(activity, true); AppUpdates.check(activity, background = true); AppUpdates.state(activity) }
        } else result?.error("updates", "Allow notifications to receive automatic update alerts. Manual checks are still available.", null)
        return true
    }
    fun close() { closed = true; permissionResult?.success(null); permissionResult = null; channel.setMethodCallHandler(null) }
}
