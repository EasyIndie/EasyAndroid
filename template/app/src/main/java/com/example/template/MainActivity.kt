package com.example.template

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Card
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import androidx.tv.material3.darkColorScheme

/**
 * 应用入口。
 *
 * 这个工程是 `tools/new-app.sh` 的模板:内容刻意保持最小,
 * 只演示「TV 遥控 D-pad 能聚焦 + 手机/VR 也能跑」这一层。
 * 新建工程后从这里开始写业务,不需要动 [AppRoot] 之外的脚手架。
 */
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

/**
 * 应用根界面。
 *
 * 用 tv-material3 的 [Card] 而不是普通 `Box`:它在 TV 上有焦点态,
 * 遥控上下键能切换 —— 真机验收 D-pad 时第一眼就能看出有没有接上。
 *
 * 换成业务 UI 时保留这几条就够了:
 *   · 根节点 `fillMaxSize()` + 深色背景(TV 上没有系统状态栏可依靠)
 *   · 可聚焦元素之间留出上下间距,10-foot UI 不要挤
 *   · 版本号用 `BuildConfig.VERSION_NAME`,不要写字面量
 */
@Composable
fun AppRoot() {
    // 占位内容 —— 新工程的第一屏。改成真实业务数据即可。
    val rows = remember { listOf("第一项", "第二项", "第三项") }

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
                    text = "用遥控 / 手柄上下键切换焦点,按确认查看详情",
                    fontSize = 14.sp,
                    color = Color(0xFF8A93A5),
                    modifier = Modifier.padding(bottom = 14.dp)
                )
            }
            items(rows) { label ->
                Card(onClick = { /* TODO: 业务动作 */ }) {
                    Text(
                        text = label,
                        fontSize = 16.sp,
                        color = Color(0xFFE6ECF5),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 14.dp)
                    )
                }
            }
            item {
                Text(
                    text = "构建 v${BuildConfig.VERSION_NAME}",
                    fontSize = 13.sp,
                    color = Color(0xFF5A6478),
                    modifier = Modifier.padding(top = 12.dp)
                )
            }
        }
    }
}
