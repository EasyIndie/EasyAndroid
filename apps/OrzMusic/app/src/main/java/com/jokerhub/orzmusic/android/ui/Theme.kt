package com.jokerhub.orzmusic.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme

/**
 * OrzMusic 的配色来自项目品牌:近黑底 + 暖白 + 薄荷绿波形。
 * 不自定义 tv-material3 的 ColorScheme(它的参数集和 Material3 不完全一样),
 * 直接用显式颜色常量,避免版本升级时编译不过。
 */
object OrzColors {
    val Bg = Color(0xFF080C10)
    val Surface = Color(0xFF111A21)
    val SurfaceHigh = Color(0xFF1A262F)
    val Mint = Color(0xFF7EF0C0)
    val MintDim = Color(0xFF2E6B55)
    val Text = Color(0xFFE9F0F4)
    val Muted = Color(0xFF8FA3B0)
    val Warm = Color(0xFFF2EADF)
    val Danger = Color(0xFFFF8A80)
}

@Composable
fun OrzTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = darkColorScheme(), content = content)
}
