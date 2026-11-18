package com.jokerhub.orzmusic.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.content.ContextCompat
import com.jokerhub.orzmusic.android.ui.AppRoot
import com.jokerhub.orzmusic.android.ui.OrzTheme
import com.jokerhub.orzmusic.android.ui.WindowFocusEvents

class MainActivity : ComponentActivity() {

    private val notificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* 拒绝也不阻塞播放；只是没有通知栏图标 */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        // 深色应用:系统栏用深色背景 + 浅色图标,避免 edge-to-edge 下图标看不见
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        setContent {
            OrzTheme {
                AppRoot()
            }
        }
    }

    /**
     * Pico 上系统 BACK 会同时触发 VRSHELL 的面板焦点回收，导致 Compose
     * 收不到下一次按键。这里在 Activity 层把 BACK 完整消费掉，交给
     * OnBackPressedDispatcher / Compose BackHandler，避免事件继续冒泡到 VRSHELL。
     */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) WindowFocusEvents.notifyFocus()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.action == KeyEvent.ACTION_UP) {
                onBackPressedDispatcher.onBackPressed()
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
