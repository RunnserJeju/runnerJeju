package com.runnersjeju.runners_jeju

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "runners_jeju/heading")
            .setStreamHandler(HeadingStreamHandler(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "runners_jeju/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    result.success(
                        saveToDownloads(
                            call.argument<String>("path")!!,
                            call.argument<String>("name")!!,
                            call.argument<String>("mimeType")!!,
                        )
                    )
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
                }
            }
    }

    // 공용 다운로드 폴더에 복사한다. MediaStore는 API 29+에서만 권한 없이 쓸 수 있어
    // 그 아래는 false를 돌려 호출부가 공유 시트로 넘어가게 한다.
    private fun saveToDownloads(path: String, name: String, mimeType: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false

        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        // 같은 코스를 다시 받으면 덮어쓴다. 안 지우면 '이름 (1).gpx'로 쌓인다.
        contentResolver.delete(
            collection,
            "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?",
            arrayOf(name, "${Environment.DIRECTORY_DOWNLOADS}/"),
        )

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values) ?: return false
        try {
            contentResolver.openOutputStream(uri)!!.use { out ->
                File(path).inputStream().use { it.copyTo(out) }
            }
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        contentResolver.update(uri, values, null, null)
        return true
    }
}
