package com.example.dualdemo

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Card
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import androidx.tv.material3.darkColorScheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                DeviceInspector()
            }
        }
    }
}

data class Fact(val key: String, val value: String)

@Composable
fun DeviceInspector() {
    val ctx = LocalContext.current
    val facts = remember { collectFacts(ctx) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0B0F16))
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 48.dp, vertical = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                Text(
                    text = "双端真机自检",
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF7FD4FF)
                )
            }
            item {
                Text(
                    text = "TCL 电视 192.0.2.11   |   Pico 4 192.0.2.29   |   用遥控上下键切换焦点并按确认",
                    fontSize = 14.sp,
                    color = Color(0xFF8A93A5),
                    modifier = Modifier.padding(bottom = 14.dp)
                )
            }
            items(facts) { fact ->
                Card(onClick = { }) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = fact.key,
                            fontSize = 15.sp,
                            color = Color(0xFF8A93A5),
                            modifier = Modifier.padding(end = 20.dp)
                        )
                        Text(
                            text = fact.value,
                            fontSize = 16.sp,
                            color = Color(0xFFE6ECF5)
                        )
                    }
                }
            }
            item {
                Text(
                    text = "共 ${facts.size} 项 · 构建 v0.1.0",
                    fontSize = 13.sp,
                    color = Color(0xFF5A6478),
                    modifier = Modifier.padding(top = 12.dp)
                )
            }
        }
    }
}

private fun collectFacts(ctx: Context): List<Fact> {
    val pm = ctx.packageManager
    val dm = ctx.resources.displayMetrics
    val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
    val stat = StatFs(Environment.getDataDirectory().path)
    val gb = 1024.0 * 1024.0 * 1024.0

    fun feature(name: String): String =
        if (pm.hasSystemFeature(name)) "支持" else "不支持"

    return listOf(
        Fact("品牌 / 型号", "${Build.MANUFACTURER} ${Build.MODEL}"),
        Fact("产品代号", "${Build.DEVICE}  (product=${Build.PRODUCT}, board=${Build.BOARD})"),
        Fact("Android", "Android ${Build.VERSION.RELEASE}   API ${Build.VERSION.SDK_INT}"),
        Fact("构建指纹", Build.FINGERPRINT),
        Fact("CPU 架构", Build.SUPPORTED_ABIS.joinToString(", ")),
        Fact("屏幕分辨率", "${dm.widthPixels} x ${dm.heightPixels} px"),
        Fact("屏幕密度", "${dm.densityDpi} dpi  (density=${dm.density})"),
        Fact(
            "逻辑尺寸",
            "${(dm.widthPixels / dm.density).toInt()} x ${(dm.heightPixels / dm.density).toInt()} dp"
        ),
        Fact(
            "内存",
            "可用 ${mi.availMem / 1048576} MB / 共 ${mi.totalMem / 1048576} MB  低内存=${mi.lowMemory}"
        ),
        Fact("存储", String.format("%.1f GB 可用 / %.1f GB", stat.availableBytes / gb, stat.totalBytes / gb)),
        Fact("Android TV", feature(PackageManager.FEATURE_LEANBACK)),
        Fact("触摸屏", feature(PackageManager.FEATURE_TOUCHSCREEN)),
        Fact("HDMI-CEC", feature("android.hardware.hdmi.cec")),
        Fact("Vulkan", feature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION)),
        Fact("OpenGL ES", am.deviceConfigurationInfo.glEsVersion),
        Fact("VR 头显模式", feature("android.hardware.vr.headtracking")),
        Fact("默认横竖屏", if (ctx.resources.configuration.orientation == 1) "竖屏" else "横屏"),
        Fact("应用包名", ctx.packageName)
    )
}
