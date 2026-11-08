package com.runnersjeju.runners_jeju

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.UUID

/// 크래시 콜스택 수집. 결과는 [CrashOutbox]에 쌓이고 Dart가 서버로 올린다.
///
/// - Kotlin/Java 크래시: 죽기 직전 예외 처리기가 스택을 남긴다(OS는 덤프를 안 준다).
/// - C++ 크래시·ANR: 다음 실행 때 OS 종료 기록(API 30+)에서 덤프를 꺼낸다.
///   C++ 덤프(tombstone)는 API 31+부터 준다.
object CrashCollector {
    private const val PREFS = "crash_collector"
    private const val LAST_EXIT_AT = "last_exit_at"
    private const val DUMP_MAX_BYTES = 16 * 1024 * 1024
    private const val STACK_MAX_CHARS = 64 * 1024
    private const val FIRST_RUN_LOOKBACK_MS = 7L * 24 * 60 * 60 * 1000

    private var handlerInstalled = false

    /// 프로세스당 한 번. Activity가 다시 만들어져도 처리기가 겹쳐 같은 크래시가 여러 번 남지 않게.
    fun installUncaughtHandler(context: Context) {
        if (handlerInstalled) return
        handlerInstalled = true
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                CrashOutbox.write(
                    app,
                    mapOf(
                        "id" to UUID.randomUUID().toString(),
                        "kind" to "android_crash",
                        "occurred_at" to CrashOutbox.iso(System.currentTimeMillis()),
                        "summary" to "${error.javaClass.name}: ${error.message}".take(500),
                        "stack" to Log.getStackTraceString(error).take(STACK_MAX_CHARS),
                        "device" to CrashOutbox.device,
                        "os_version" to CrashOutbox.osVersion,
                        "context" to mapOf("thread" to thread.name),
                    ),
                )
            } catch (_: Throwable) {
                // 기록에 실패해도 원래 처리(앱 종료)는 그대로 간다.
            }
            previous?.uncaughtException(thread, error)
        }
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, "runners_jeju/crash").setMethodCallHandler { call, result ->
            when (call.method) {
                "outboxDir" -> result.success(CrashOutbox.dir(app).absolutePath)
                "collect" -> {
                    // 덤프 읽기는 수 MB일 수 있어 메인 스레드를 막지 않는다.
                    Thread {
                        val count = try { collectExitTraces(app) } catch (_: Throwable) { 0 }
                        Handler(Looper.getMainLooper()).post { result.success(count) }
                    }.start()
                }
                "testCrash" -> {
                    testCrash(call.argument<String>("type"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// 지난번 이후 새로 생긴 C++ 크래시·ANR 종료 기록을 보관함에 옮긴다. 옮긴 건수.
    private fun collectExitTraces(context: Context): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return 0
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val since = prefs.getLong(LAST_EXIT_AT, System.currentTimeMillis() - FIRST_RUN_LOOKBACK_MS)
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val exits = am.getHistoricalProcessExitReasons(context.packageName, 0, 16)
            .filter { it.timestamp > since }

        var count = 0
        for (info in exits) {
            val kind = when (info.reason) {
                ApplicationExitInfo.REASON_CRASH_NATIVE -> "android_native"
                ApplicationExitInfo.REASON_ANR -> "android_anr"
                else -> null // Kotlin 크래시는 예외 처리기가, OS 종료는 run_recover 로그가 맡는다.
            } ?: continue
            val dump = try { info.traceInputStream?.use { readCapped(it) } } catch (_: Throwable) { null }
            CrashOutbox.write(
                context,
                mapOf(
                    // 같은 종료 기록을 다시 읽어도 같은 id — 서버가 한 건으로 친다.
                    "id" to UUID.nameUUIDFromBytes("${info.pid}:${info.timestamp}".toByteArray()).toString(),
                    "kind" to kind,
                    "occurred_at" to CrashOutbox.iso(info.timestamp),
                    "summary" to (info.description ?: kind).take(500),
                    "device" to CrashOutbox.device,
                    "os_version" to CrashOutbox.osVersion,
                    "context" to mapOf(
                        "importance" to info.importance,
                        "pss_kb" to info.pss,
                        "rss_kb" to info.rss,
                        "status" to info.status,
                        "process" to info.processName,
                    ),
                ),
                dump,
            )
            count++
        }
        exits.maxOfOrNull { it.timestamp }?.let { prefs.edit().putLong(LAST_EXIT_AT, it).apply() }
        return count
    }

    private fun readCapped(input: InputStream): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        while (out.size() < DUMP_MAX_BYTES) {
            val read = input.read(buffer, 0, minOf(buffer.size, DUMP_MAX_BYTES - out.size()))
            if (read < 0) break
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }

    /// 수집 경로 확인용(디버그 화면에서만 부른다). 앱이 실제로 죽는다.
    private fun testCrash(type: String?) {
        val main = Handler(Looper.getMainLooper())
        when (type) {
            "native" -> Process.sendSignal(Process.myPid(), 11) // SIGSEGV
            "anr" -> main.post { Thread.sleep(20_000) } // 이 사이 화면을 몇 번 눌러야 ANR이 난다.
            else -> main.post { throw IllegalStateException("RunnersJeju test crash") }
        }
    }
}
