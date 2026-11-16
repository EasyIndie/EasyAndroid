package com.jokerhub.orzmusic.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.jokerhub.orzmusic.android.ui.AppRoot
import com.jokerhub.orzmusic.android.ui.OrzTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 深色应用:系统栏用深色背景 + 浅色图标,避免 edge-to-edge 下图标看不见
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )
        super.onCreate(savedInstanceState)
        setContent {
            OrzTheme {
                AppRoot()
            }
        }
    }
}
