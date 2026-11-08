package com.runnersjeju.runners_jeju

import android.content.Context
import android.os.Build
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/// 서버로 올릴 크래시 리포트를 쌓아 두는 기기 안 폴더. Dart(CrashReporter)가 비운다.
///
/// 한 건이 <id>.json(요약) + 선택 <id>.dump(원본 덤프)다. json을 마지막에 이름을 바꿔
/// 내놓으므로, json이 보이면 덤프까지 다 써진 것이다.
object CrashOutbox {
    fun dir(context: Context): File = File(context.filesDir, "crash_outbox").apply { mkdirs() }

    fun write(context: Context, meta: Map<String, Any?>, dump: ByteArray? = null) {
        val dir = dir(context)
        val id = meta["id"] as String
        if (dump != null) File(dir, "$id.dump").writeBytes(dump)
        val tmp = File(dir, "$id.json.tmp")
        tmp.writeText(JSONObject(meta).toString())
        tmp.renameTo(File(dir, "$id.json"))
    }

    val device: String get() = "${Build.MANUFACTURER} ${Build.MODEL}"
    val osVersion: String get() = "Android ${Build.VERSION.RELEASE} (${Build.ID})"

    fun iso(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(millis))
}
