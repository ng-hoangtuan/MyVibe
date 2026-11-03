package com.example.task_habit_app

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "myvibe/lockscreen"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showOverLockScreen" -> {
                        setShowOverLockScreen(true)
                        // Trả về việc máy có đang khóa hay không, để phía Flutter
                        // biết lúc tắt nhắc thì nên quay lại màn hình khóa.
                        result.success(isDeviceLocked())
                    }
                    "releaseLockScreen" -> {
                        setShowOverLockScreen(false)
                        result.success(true)
                    }
                    "moveToBackground" -> {
                        setShowOverLockScreen(false)
                        // Đưa app về background -> người dùng thấy lại màn hình
                        // khóa chứ không thấy giao diện app.
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isDeviceLocked(): Boolean {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            ?: return false
        return keyguard.isKeyguardLocked
    }

    /**
     * Cho phép màn hình nhắc hiện đè lên màn hình khóa và bật sáng màn hình,
     * giống cách app đồng hồ báo thức hoạt động.
     */
    private fun setShowOverLockScreen(enable: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enable)
            setTurnScreenOn(enable)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (enable) window.addFlags(flags) else window.clearFlags(flags)
        }

        // Giữ màn hình sáng trong lúc màn hình nhắc đang hiện.
        // Không gọi requestDismissKeyguard: ta muốn hiện ĐÈ LÊN màn hình khóa,
        // không bắt người dùng mở khóa máy.
        if (enable) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}
