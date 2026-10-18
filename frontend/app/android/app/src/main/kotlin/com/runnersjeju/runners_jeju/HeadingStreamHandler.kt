package com.runnersjeju.runners_jeju

import android.app.Activity
import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.view.Surface
import io.flutter.plugin.common.EventChannel
import kotlin.math.atan2
import kotlin.math.hypot

/// 폰이 향한 방향(진북 기준, 도)을 Flutter(HeadingService)로 흘려보낸다.
///
/// 자이로·가속도·지자기를 OS가 융합한 ROTATION_VECTOR를 쓴다. 이벤트는
/// {heading, accuracy(도, 모르면 -1), calibrated}. 판정은 Dart가 한다.
class HeadingStreamHandler(private val activity: Activity) :
    EventChannel.StreamHandler, SensorEventListener {

    private val sensorManager =
        activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val sensor: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

    private var sink: EventChannel.EventSink? = null
    private var declination = 0f
    private var sensorStatus = SensorManager.SENSOR_STATUS_UNRELIABLE
    private val rotation = FloatArray(9)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (sensor == null) {
            events.error("UNAVAILABLE", "rotation vector sensor not found", null)
            return
        }
        // 지도는 진북 기준이라 자북→진북 편각을 더한다(제주 약 -9°).
        val args = arguments as? Map<*, *>
        val lat = (args?.get("lat") as? Number)?.toFloat()
        val lng = (args?.get("lng") as? Number)?.toFloat()
        declination = if (lat != null && lng != null) {
            GeomagneticField(lat, lng, 0f, System.currentTimeMillis()).declination
        } else {
            0f
        }
        sink = events
        sensorStatus = SensorManager.SENSOR_STATUS_UNRELIABLE
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        sink = null
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        sensorStatus = accuracy
    }

    override fun onSensorChanged(event: SensorEvent) {
        val events = sink ?: return
        // 일부 기기는 5개 이상 넘기면 행렬 변환에서 예외를 낸다. 쿼터니언 4개만 넘긴다.
        SensorManager.getRotationMatrixFromVector(rotation, event.values.copyOf(4))

        // 화면 위쪽 벡터와 뒷면(-Z) 벡터를 더해 수평면에 투영한다. 눕혀 들면 앞쪽이,
        // 세워 들면 뒤쪽이 수평 성분을 맡아 자세가 바뀌어도 값이 튀지 않는다.
        val (upX, upY) = screenUpInDevice()
        val east = rotation[0] * upX + rotation[1] * upY - rotation[2]
        val north = rotation[3] * upX + rotation[4] * upY - rotation[5]
        // 폰을 거의 수직으로 위/아래로 겨누면 수평 성분이 없어 방향이 정의되지 않는다.
        if (hypot(east, north) < 0.2f) return

        val magnetic = Math.toDegrees(atan2(east, north).toDouble())
        val heading = ((magnetic + declination) % 360 + 360) % 360

        // values[4]는 추정 방위 오차(라디안). 없거나 -1이면 모른다.
        val accuracy = if (event.values.size > 4 && event.values[4] >= 0) {
            Math.toDegrees(event.values[4].toDouble())
        } else {
            -1.0
        }
        events.success(
            mapOf(
                "heading" to heading,
                "accuracy" to accuracy,
                "calibrated" to (sensorStatus >= SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM),
            )
        )
    }

    /// 지금 화면의 위쪽이 기기 좌표계(자연 방향 기준)에서 어느 축인지.
    /// ROTATION_90은 기기를 반시계로 눕힌 상태라 원래 오른쪽(+X)이 위가 된다.
    private fun screenUpInDevice(): Pair<Float, Float> {
        val displayRotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.rotation
        }
        return when (displayRotation) {
            Surface.ROTATION_90 -> 1f to 0f
            Surface.ROTATION_180 -> 0f to -1f
            Surface.ROTATION_270 -> -1f to 0f
            else -> 0f to 1f
        }
    }
}
