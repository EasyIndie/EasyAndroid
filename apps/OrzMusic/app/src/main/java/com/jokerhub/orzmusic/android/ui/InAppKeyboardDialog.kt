package com.jokerhub.orzmusic.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Card
import androidx.tv.material3.Text

class InAppKeyboardState {
    var open by mutableStateOf(false)
        private set
    var value by mutableStateOf("")
        private set
    var onChange: ((String) -> Unit)? = null
        private set
    var returnFocus: FocusRequester? = null
        private set

    fun show(initial: String, onChange: (String) -> Unit, returnFocus: FocusRequester?) {
        value = initial
        this.onChange = onChange
        this.returnFocus = returnFocus
        open = true
    }

    fun update(next: String) {
        value = next
        onChange?.invoke(next)
    }

    fun close() {
        open = false
    }
}

val LocalInAppKeyboard = compositionLocalOf<InAppKeyboardState?> { null }

/**
 * Pico 专用的应用内键盘。
 *
 * Pico 的系统输入法会创建 `PicoXR_CustomDialog` 抢走 display 焦点，
 * 关闭后 BACK 经常回不到 Compose。这里用应用内键盘完全绕开系统 IME：
 * 文本字段只读，按键是普通 Compose 焦点节点，焦点始终留在 App 的 display。
 *
 * 只覆盖 ASCII（曲名/艺术家/URL/歌单名主要场景）；中文输入仍建议在手机端完成。
 */
@Composable
fun InAppKeyboardDialog(
    value: String,
    onValueChange: (String) -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier
) {
    var upper by remember { mutableStateOf(false) }
    val firstKey = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(80)
        runCatching { firstKey.requestFocus() }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(OrzColors.Bg.copy(alpha = 0.97f))
            .padding(20.dp),
        contentAlignment = Alignment.Center
    ) {
            Column(
                modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text("输入", color = OrzColors.Mint, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Text(
                    text = value.ifEmpty { " " },
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(OrzColors.SurfaceHigh, RoundedCornerShape(10.dp))
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    color = OrzColors.Text,
                    fontSize = 16.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )

                KeyRow(listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"), onKey = { onValueChange(value + it) })
                KeyRow(listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"), upper, onKey = { onValueChange(value + it) })
                KeyRow(listOf("a", "s", "d", "f", "g", "h", "j", "k", "l"), upper, onKey = { onValueChange(value + it) })
                KeyRow(listOf("z", "x", "c", "v", "b", "n", "m"), upper, onKey = { onValueChange(value + it) })
                KeyRow(listOf("-", "_", ".", "/", ":", "@", "(", ")"), onKey = { onValueChange(value + it) })

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Key("⇧ ${if (upper) "ABC" else "abc"}", Modifier.weight(0.8f), firstKey) { upper = !upper }
                    Key("空格", Modifier.weight(2f)) { onValueChange("$value ") }
                    Key("⌫", Modifier.weight(0.8f)) { onValueChange(value.dropLast(1)) }
                    Key("清空", Modifier.weight(0.8f)) { onValueChange("") }
                    Key("完成", Modifier.weight(0.9f), accent = true, onDone = onDone) { onDone() }
                }
            }
        }
    }

@Composable
private fun KeyRow(
    keys: List<String>,
    upper: Boolean = false,
    onKey: (String) -> Unit
) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        keys.forEach { key ->
            Key(
                text = if (upper) key.uppercase() else key,
                modifier = Modifier.weight(1f)
            ) { onKey(if (upper) key.uppercase() else key) }
        }
    }
}

@Composable
private fun Key(
    text: String,
    modifier: Modifier = Modifier,
    focusRequester: FocusRequester? = null,
    accent: Boolean = false,
    onDone: () -> Unit = {},
    onClick: () -> Unit = onDone
) {
    Card(
        onClick = onClick,
        modifier = modifier.then(
            if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier
        ),
        colors = orzCardColors(if (accent) OrzColors.Mint else OrzColors.SurfaceHigh)
    ) {
        Box(
            modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = text,
                color = if (accent) OrzColors.Bg else OrzColors.Text,
                fontSize = 13.sp,
                fontWeight = if (accent) FontWeight.Bold else FontWeight.Normal,
                maxLines = 1
            )
        }
    }
}
