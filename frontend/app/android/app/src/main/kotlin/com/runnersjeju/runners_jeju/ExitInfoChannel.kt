package com.runnersjeju.runners_jeju

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// 직전 프로세스가 왜 끝났는지 OS에 묻는다(API 30+). 러닝 복구 로그에 붙인다.
/// 크래시 리포트로는 안 잡히는 OS 강제 종료(메모리 부족 등)까지 구분된다.
object ExitInfoChannel {
    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, "runners_jeju/exit_info").setMethodCallHandler { call, result ->
            if (call.method != "lastExit") return@setMethodCallHandler result.notImplemented()
            try {
                result.success(lastExit(context))
            } catch (e: Exception) {
                result.success(null)
            }
        }
    }

    private fun lastExit(context: Context): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = am.getHistoricalProcessExitReasons(context.packageName, 0, 1)
            .firstOrNull() ?: return null
        return mapOf(
            "reason" to reasonName(info.reason),
            "status" to info.status,
            // 100 포그라운드, 125 포그라운드 서비스, 200+ 백그라운드 쪽.
            "importance" to info.importance,
            "description" to info.description?.take(200),
            "at" to info.timestamp,
            "pss_kb" to info.pss,
            "rss_kb" to info.rss,
        )
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        ApplicationExitInfo.REASON_SIGNALED -> "signaled"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "init_failure"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission_change"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency_died"
        ApplicationExitInfo.REASON_OTHER -> "other"
        ApplicationExitInfo.REASON_FREEZER -> "freezer"
        ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE -> "package_state_change"
        ApplicationExitInfo.REASON_PACKAGE_UPDATED -> "package_updated"
        else -> "unknown_$reason"
    }
}
