package com.laantech.public_downloads

import android.Manifest
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Publishes finished downloads into the public `Download/<folder>/` directory.
 *
 * Registered in every Flutter engine, including the foreground-service engine
 * that runs transfers. Permission requests need an Activity and therefore only
 * work from the UI engine; publishing works from either.
 */
class PublicDownloadsPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null

    // A single worker serialises publishes, so two downloads with the same
    // name can never race for the same free file name.
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainThread = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasWriteAccess" -> result.success(hasWriteAccess())
            "requestWriteAccess" -> requestWriteAccess(result)
            "publish" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val fileName = call.argument<String>("fileName")
                val folder = call.argument<String>("folder")
                if (sourcePath.isNullOrEmpty() || fileName.isNullOrEmpty() || folder.isNullOrEmpty()) {
                    result.error(ERROR_INVALID, "sourcePath, fileName and folder are required.", null)
                    return
                }
                worker.execute {
                    try {
                        val published = publish(File(sourcePath), fileName, folder)
                        mainThread.post { result.success(published) }
                    } catch (e: Exception) {
                        val (code, message) = describe(e)
                        mainThread.post { result.error(code, message, null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // region Permissions (Android 7-9 only; scoped storage needs none)

    private fun hasWriteAccess(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestWriteAccess(result: MethodChannel.Result) {
        if (hasWriteAccess()) return result.success(true)
        val activity = activityBinding?.activity ?: return result.success(false)
        if (pendingPermission != null) {
            return result.error(ERROR_BUSY, "A storage permission request is already in progress.", null)
        }
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pendingPermission = null
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        pendingPermission?.success(false)
        pendingPermission = null
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    // endregion

    // region Publishing

    private fun publish(source: File, fileName: String, folder: String): Map<String, Any> {
        if (!source.isFile) throw FileNotFoundException("The downloaded file is missing: ${source.name}")
        val mimeType = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(fileName.substringAfterLast('.', "").lowercase())
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishToMediaStore(source, fileName, folder, mimeType)
        } else {
            publishToLegacyStorage(source, fileName, folder, mimeType)
        }
    }

    /** Android 10+: no permission; the file stays pending (hidden) until fully written. */
    private fun publishToMediaStore(source: File, fileName: String, folder: String, mimeType: String?): Map<String, Any> {
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$folder/"
        val directory = publicDirectory(folder)
        val name = availableName(fileName) { candidate ->
            File(directory, candidate).exists() || resolver.hasEntry(collection, relativePath, candidate)
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
            // Left unset for unknown types so MediaStore keeps the name as is
            // instead of appending an extension for a guessed type.
            if (mimeType != null) put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("The system refused to create the file in Downloads.")
        try {
            val output = resolver.openOutputStream(uri, "w")
                ?: throw IOException("Could not open the destination file in Downloads.")
            output.use { out -> source.inputStream().use { it.copyTo(out, BUFFER_SIZE) } }
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        // MediaStore may still have renamed the file if another app owns a
        // file with that name, so report the name it actually used.
        val finalName = resolver.displayName(uri) ?: name
        return result(File(directory, finalName), uri, source.length())
    }

    /** Android 7-9: classic shared storage with WRITE_EXTERNAL_STORAGE. */
    private fun publishToLegacyStorage(source: File, fileName: String, folder: String, mimeType: String?): Map<String, Any> {
        if (!hasWriteAccess()) throw SecurityException("Storage permission was not granted.")
        val directory = publicDirectory(folder)
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IOException("Could not create the Downloads/$folder folder.")
        }
        val name = availableName(fileName) { File(directory, it).exists() }
        val target = File(directory, name)
        // Hidden while being written, so a file manager never shows a partial copy.
        val temp = File(directory, ".$name.pending")
        try {
            source.inputStream().use { input -> temp.outputStream().use { input.copyTo(it, BUFFER_SIZE) } }
            if (!temp.renameTo(target)) throw IOException("Could not finalise ${target.name}.")
        } catch (e: Exception) {
            temp.delete()
            throw e
        }
        MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), mimeType?.let { arrayOf(it) }, null)
        return result(target, Uri.fromFile(target), target.length())
    }

    @Suppress("DEPRECATION") // Used only to build the user-visible path; access goes through MediaStore on Q+.
    private fun publicDirectory(folder: String): File =
        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), folder)

    private fun result(file: File, uri: Uri, size: Long): Map<String, Any> =
        mapOf("path" to file.absolutePath, "uri" to uri.toString(), "name" to file.name, "size" to size)

    /** "name.ext", then "name (1).ext", "name (2).ext", … until [taken] is false. */
    private fun availableName(fileName: String, taken: (String) -> Boolean): String {
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""
        var candidate = fileName
        var copy = 1
        while (taken(candidate)) {
            candidate = "$base ($copy)$extension"
            copy++
        }
        return candidate
    }

    private fun ContentResolver.hasEntry(collection: Uri, relativePath: String, name: String): Boolean =
        query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME}=?",
            arrayOf(relativePath, name),
            null,
        )?.use { it.count > 0 } ?: false

    private fun ContentResolver.displayName(uri: Uri): String? =
        query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }

    private fun describe(e: Exception): Pair<String, String> = when {
        e is SecurityException -> ERROR_PERMISSION to (e.message ?: "Storage permission was denied.")
        e is FileNotFoundException -> ERROR_SOURCE to (e.message ?: "The downloaded file is missing.")
        e.message?.contains("ENOSPC") == true || e.message?.contains("No space", ignoreCase = true) == true ->
            ERROR_NO_SPACE to "Not enough storage space on this device."
        else -> ERROR_IO to (e.message ?: e.javaClass.simpleName)
    }

    // endregion

    private companion object {
        const val CHANNEL = "laantech/public_downloads"
        const val PERMISSION_REQUEST = 0x4C54
        const val BUFFER_SIZE = 1 shl 16
        const val ERROR_INVALID = "invalid_arguments"
        const val ERROR_BUSY = "busy"
        const val ERROR_PERMISSION = "permission_denied"
        const val ERROR_SOURCE = "source_missing"
        const val ERROR_NO_SPACE = "no_space"
        const val ERROR_IO = "io_error"
    }
}
