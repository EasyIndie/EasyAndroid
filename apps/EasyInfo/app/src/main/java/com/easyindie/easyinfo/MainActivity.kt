package com.easyindie.easyinfo

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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
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
                AppRoot()
            }
        }
    }
}

data class Fact(val key: String, val value: String)
data class Section(val title: String, val facts: List<Fact>)

/**
 * 设备信息 —— 首屏。
 *
 * 设计约束(也是上架审核相关):
 *   · **不申请任何权限**,不联网,不采集、不上传任何数据
 *   · 只读取本机公开的 Build/DisplayMetrics/ActivityManager 信息
 *   · 点任意一行把值复制到剪贴板(复制是本地行为,不涉及隐私)
 *
 * UI 上用 tv-material 的 [Card],遥控上下键能移动焦点;手机/VR 上同样可点。
 */
@Composable
fun AppRoot() {
    val ctx = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val sections = remember { collectSections(ctx) }
    var copied by remember { mutableStateOf<String?>(null) }

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
                    text = stringResource(R.string.app_name),
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF7FD4FF)
                )
            }
            item {
                Text(
                    text = copied?.let { "已复制: $it" } ?: "选一行按确认可复制该值",
                    fontSize = 14.sp,
                    color = if (copied != null) Color(0xFF6FD08C) else Color(0xFF8A93A5),
                    modifier = Modifier.padding(bottom = 12.dp)
                )
            }

            sections.forEach { section ->
                item {
                    Text(
                        text = section.title,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF5A6478),
                        modifier = Modifier.padding(top = 12.dp, bottom = 4.dp)
                    )
                }
                items(section.facts) { fact ->
                    Card(
                        onClick = {
                            clipboard.setText(AnnotatedString(fact.value))
                            copied = "${fact.key} = ${fact.value}"
                        }
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 20.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = fact.key,
                                fontSize = 14.sp,
                                color = Color(0xFF8A93A5),
                                modifier = Modifier.padding(end = 20.dp)
                            )
                            Text(
                                text = fact.value,
                                fontSize = 15.sp,
                                color = Color(0xFFE6ECF5)
                            )
                        }
                    }
                }
            }

            item {
                Text(
                    text = "构建 v${BuildConfig.VERSION_NAME} · 无权限 · 不联网 · 不采集数据",
                    fontSize = 12.sp,
                    color = Color(0xFF5A6478),
                    modifier = Modifier.padding(top = 16.dp)
                )
            }
        }
    }
}

private fun collectSections(ctx: Context): List<Section> {
    val pm = ctx.packageManager
    val dm = ctx.resources.displayMetrics
    val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
    val stat = StatFs(Environment.getDataDirectory().path)
    val gb = 1024.0 * 1024.0 * 1024.0

    fun feature(name: String): String = if (pm.hasSystemFeature(name)) "支持" else "不支持"

    return listOf(
        Section(
            "设备",
            listOf(
                Fact("品牌 / 型号", "${Build.MANUFACTURER} ${Build.MODEL}"),
                Fact("设备代号", Build.DEVICE),
                Fact("Android", "Android ${Build.VERSION.RELEASE}  (API ${Build.VERSION.SDK_INT})"),
                Fact("系统构建", "${Build.ID} / ${Build.TYPE}")
            )
        ),
        Section(
            "屏幕",
            listOf(
                Fact("分辨率", "${dm.widthPixels} x ${dm.heightPixels} px"),
                Fact("密度", "${dm.densityDpi} dpi"),
                Fact(
                    "逻辑尺寸",
                    "${(dm.widthPixels / dm.density).toInt()} x ${(dm.heightPixels / dm.density).toInt()} dp"
                ),
                Fact("方向", if (ctx.resources.configuration.orientation == 1) "竖屏" else "横屏")
            )
        ),
        Section(
            "硬件",
            listOf(
                Fact("CPU 架构", Build.SUPPORTED_ABIS.joinToString(", ")),
                Fact("内存", "${mi.availMem / 1048576} MB 可用 / ${mi.totalMem / 1048576} MB"),
                Fact(
                    "存储",
                    String.format("%.1f GB 可用 / %.1f GB", stat.availableBytes / gb, stat.totalBytes / gb)
                ),
                Fact("OpenGL ES", am.deviceConfigurationInfo.glEsVersion)
            )
        ),
        Section(
            "能力",
            listOf(
                Fact("Android TV", feature(PackageManager.FEATURE_LEANBACK)),
                Fact("触摸屏", feature(PackageManager.FEATURE_TOUCHSCREEN)),
                Fact("HDMI-CEC", feature("android.hardware.hdmi.cec")),
                Fact("Vulkan", feature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION)),
                Fact("VR 头显", feature("android.hardware.vr.headtracking"))
            )
        )
    )
}
