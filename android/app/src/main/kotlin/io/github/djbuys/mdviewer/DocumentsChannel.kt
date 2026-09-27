package io.github.djbuys.mdviewer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Document access for Dart.
 *
 * "mdviewer/android_documents": pickFile, pickFolder, restoreFile, hasTreeAccess, list, read, stat.
 * "mdviewer/incoming": takePending (Dart -> native) and open (native -> Dart) for VIEW intents.
 *
 * Single files are copied into the app cache so Dart reads them as plain paths.
 * Folders are read in place through the Storage Access Framework.
 */
class DocumentsChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val documents = MethodChannel(messenger, "mdviewer/android_documents")
    private val incoming = MethodChannel(messenger, "mdviewer/incoming")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pickResult: MethodChannel.Result? = null
    private val pendingIncoming = mutableListOf<Map<String, String>>()
    private var dartReady = false

    init {
        documents.setMethodCallHandler(::onDocumentsCall)
        incoming.setMethodCallHandler { call, result ->
            if (call.method == "takePending") {
                dartReady = true
                result.success(pendingIncoming.toList())
                pendingIncoming.clear()
            } else {
                result.notImplemented()
            }
        }
    }

    fun handleViewIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        intent.action = null // handle once, even if the activity is recreated
        background({ copyToCache(uri) }, { path ->
            val document = mapOf("path" to path)
            if (dartReady) incoming.invokeMethod("open", listOf(document)) else pendingIncoming.add(document)
        })
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_FILE && requestCode != PICK_FOLDER) return
        val result = pickResult ?: return
        pickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
            // Not persistable (e.g. some cloud providers): works for this session only.
        }
        if (requestCode == PICK_FOLDER) {
            val name = DocumentFile.fromTreeUri(activity, uri)?.name ?: "Folder"
            result.success(mapOf("treeUri" to uri.toString(), "name" to name))
        } else {
            background(
                { copyToCache(uri) },
                { path -> result.success(mapOf("path" to path, "uri" to uri.toString(), "name" to File(path).name)) },
                { error -> result.error("read_failed", error.message, null) },
            )
        }
    }

    private fun onDocumentsCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFile" -> startPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        arrayOf("text/markdown", "text/x-markdown", "text/plain", "application/octet-stream"),
                    )
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                },
                PICK_FILE,
                result,
            )
            "pickFolder" -> startPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                },
                PICK_FOLDER,
                result,
            )
            "restoreFile" -> {
                val uri = Uri.parse(call.argument<String>("uri"))
                background({ copyToCache(uri) }, { result.success(mapOf("path" to it)) }, { result.success(null) })
            }
            "hasTreeAccess" -> {
                val uri = Uri.parse(call.argument<String>("treeUri"))
                result.success(activity.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission })
            }
            "list" -> background(
                { list(treeUri(call), path(call)) },
                { result.success(it) },
                { result.error("list_failed", it.message, null) },
            )
            "read" -> background(
                { read(treeUri(call), path(call)) },
                { result.success(it) },
                { result.error("read_failed", it.message, null) },
            )
            "stat" -> background(
                { stat(treeUri(call), path(call)) },
                { result.success(it) },
                { result.error("stat_failed", it.message, null) },
            )
            else -> result.notImplemented()
        }
    }

    private fun startPicker(intent: Intent, requestCode: Int, result: MethodChannel.Result) {
        if (pickResult != null) {
            result.error("busy", "A picker is already open", null)
            return
        }
        pickResult = result
        activity.startActivityForResult(intent, requestCode)
    }

    private fun <T> background(work: () -> T, done: (T) -> Unit, failed: (Exception) -> Unit = {}) {
        io.execute {
            try {
                val value = work()
                main.post { done(value) }
            } catch (e: Exception) {
                main.post { failed(e) }
            }
        }
    }

    private fun treeUri(call: MethodCall): Uri = Uri.parse(call.argument<String>("treeUri"))

    private fun path(call: MethodCall): String = call.argument<String>("path") ?: "/"

    private fun copyToCache(uri: Uri): String {
        val name = (displayName(uri) ?: "document.md").replace('/', '_')
        val dir = File(activity.cacheDir, "opened/${Integer.toHexString(uri.toString().hashCode())}")
        dir.mkdirs()
        val target = File(dir, name)
        val input = activity.contentResolver.openInputStream(uri) ?: throw IllegalStateException("Cannot open $uri")
        input.use { source -> target.outputStream().use { source.copyTo(it) } }
        return target.absolutePath
    }

    private fun displayName(uri: Uri): String? =
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }

    private fun resolve(treeUri: Uri, path: String): DocumentFile? {
        var node = DocumentFile.fromTreeUri(activity, treeUri) ?: return null
        for (segment in path.split('/').filter { it.isNotEmpty() }) {
            node = node.findFile(segment) ?: return null
        }
        return node
    }

    private fun list(treeUri: Uri, path: String): List<Map<String, Any>> {
        val dir = resolve(treeUri, path) ?: throw IllegalArgumentException("Not found: $path")
        if (!dir.isDirectory) throw IllegalArgumentException("Not a directory: $path")
        return dir.listFiles().mapNotNull { file ->
            file.name?.let { mapOf("name" to it, "isDirectory" to file.isDirectory) }
        }
    }

    private fun read(treeUri: Uri, path: String): ByteArray {
        val file = resolve(treeUri, path)?.takeIf { it.isFile } ?: throw IllegalArgumentException("File not found: $path")
        val input = activity.contentResolver.openInputStream(file.uri) ?: throw IllegalStateException("Cannot open $path")
        return input.use { it.readBytes() }
    }

    private fun stat(treeUri: Uri, path: String): Map<String, Any>? {
        val file = resolve(treeUri, path)?.takeIf { it.exists() } ?: return null
        return mapOf("size" to file.length(), "modified" to file.lastModified())
    }

    companion object {
        private const val PICK_FILE = 4101
        private const val PICK_FOLDER = 4102
    }
}
