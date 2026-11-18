package com.jokerhub.orzmusic.android.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Button
import androidx.tv.material3.Text
import com.jokerhub.orzmusic.android.ui.BrandBadge
import com.jokerhub.orzmusic.android.ui.FormatTag
import com.jokerhub.orzmusic.android.ui.OrzColors
import com.jokerhub.orzmusic.android.ui.orzButtonColors
import com.jokerhub.orzmusic.android.ui.SeekBar
import com.jokerhub.orzmusic.android.ui.VisualizerBars
import com.jokerhub.orzmusic.android.ui.VolumeSlider
import com.jokerhub.orzmusic.android.ui.formatTime
import com.jokerhub.orzmusic.core.model.PlayStrategy
import com.jokerhub.orzmusic.core.model.Song
import com.jokerhub.orzmusic.core.model.strategy

/**
 * 全屏“正在播放”。网页端的底栏 + 声场面板在这里合并成一页：
 * 进度（点击/拖动/D-pad）、前后 5/15 秒、播放控制、音量、队列入口、装饰声场。
 *
 * 声场只是动画，不读取音频采样，因此不需要 RECORD_AUDIO 权限。
 */
@Composable
fun NowPlayingScreen(
    song: Song,
    isPlaying: Boolean,
    decoding: Boolean,
    notice: String?,
    positionMs: Long,
    durationMs: Long,
    volume: Float,
    levels: FloatArray,
    queueCount: Int,
    serverUrl: String,
    onBack: () -> Unit,
    onToggle: () -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onSeek: (Long) -> Unit,
    onSeekBy: (Long) -> Unit,
    onVolume: (Float) -> Unit,
    onMute: () -> Unit,
    onQueue: () -> Unit,
    onLocate: () -> Unit,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val unsupported = song.strategy == PlayStrategy.WasmDecode && !decoding
    val fraction = if (durationMs > 0) positionMs.toFloat() / durationMs.toFloat() else 0f

    Box(
        modifier = modifier
            .fillMaxSize()
            // 先铺不透明底色，再叠一层径向光晕；否则渐变中心是透明的，
            // 下面整个曲库会透上来（实机验收时踩到）。
            .background(OrzColors.Bg)
            .background(
                Brush.radialGradient(
                    listOf(OrzColors.Mint.copy(alpha = 0.10f), OrzColors.Bg.copy(alpha = 0f)),
                    radius = 900f
                )
            )
            // 覆盖层不能把点击透给下面的曲库；空白区域也要吃掉事件。
            .pointerInput(Unit) { detectTapGestures { } }
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 22.dp, vertical = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Button(
                    colors = orzButtonColors(),
                    onClick = onBack,
                    modifier = Modifier.focusRequester(focusRequester)
                ) { Text("‹ 返回") }
                Spacer(Modifier.weight(1f))
                FormatTag(song.fileFormat)
                Spacer(Modifier.width(4.dp))
                Button(colors = orzButtonColors(), onClick = onLocate) { Text("定位") }
                Spacer(Modifier.width(4.dp))
                Button(colors = orzButtonColors(), onClick = onQueue) { Text("队列 $queueCount") }
            }

            Spacer(Modifier.height(14.dp))
            VisualizerBars(
                levels = levels,
                active = isPlaying,
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = 720.dp)
                    .height(64.dp)
            )

            BrandBadge(format = song.fileFormat, size = 108.dp)
            Spacer(Modifier.height(16.dp))
            Text(
                text = song.title,
                color = OrzColors.Text,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = 720.dp)
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "${song.artistName} · ${song.durationText} · ${strategyLabel(song)}",
                color = OrzColors.Muted,
                fontSize = 12.sp,
                textAlign = TextAlign.Center
            )

            if (decoding) {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = "正在解码 ${song.fileFormat.uppercase()}…",
                    color = OrzColors.Mint,
                    fontSize = 13.sp
                )
            } else if (unsupported && notice != null) {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = notice,
                    color = OrzColors.Amber,
                    fontSize = 12.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.widthIn(max = 620.dp)
                )
                Button(colors = orzButtonColors(), onClick = {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(serverUrl))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                }) {
                    Text("在网页播放器打开")
                }
            }

            if (!decoding) {
                Spacer(Modifier.height(16.dp))
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .widthIn(max = 720.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    SeekBar(
                        fraction = fraction,
                        onSeek = { value -> if (durationMs > 0) onSeek((value * durationMs).toLong()) },
                        onSeekBy = onSeekBy,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(formatTime(positionMs), color = OrzColors.Muted, fontSize = 10.sp)
                        Text(formatTime(durationMs), color = OrzColors.Muted, fontSize = 10.sp)
                    }
                }

                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Button(colors = orzButtonColors(), onClick = { onSeekBy(-15_000) }) { Text("−15s") }
                    Button(colors = orzButtonColors(), onClick = { onSeekBy(-5_000) }) { Text("−5s") }
                    Button(colors = orzButtonColors(), onClick = { onSeekBy(5_000) }) { Text("+5s") }
                    Button(colors = orzButtonColors(), onClick = { onSeekBy(15_000) }) { Text("+15s") }
                }

                Spacer(Modifier.height(12.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Button(colors = orzButtonColors(), onClick = onPrevious) { Text("|◀") }
                    Button(colors = orzButtonColors(), onClick = onToggle) { Text(if (isPlaying) "II 暂停" else "▶ 播放") }
                    Button(colors = orzButtonColors(), onClick = onNext) { Text("▶|") }
                }

                Spacer(Modifier.height(14.dp))
                Row(
                    modifier = Modifier.widthIn(max = 420.dp).fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = if (volume <= 0f) "🔇" else "🔊",
                        modifier = Modifier.clickable { onMute() }.padding(4.dp),
                        fontSize = 14.sp
                    )
                    VolumeSlider(volume = volume, onChange = onVolume, modifier = Modifier.weight(1f))
                    Text("${(volume * 100).toInt()}%", color = OrzColors.Muted, fontSize = 10.sp)
                }
            }

            Spacer(Modifier.height(18.dp))
            Text(
                text = "OrzMusic · ${serverUrl.removePrefix("https://").removePrefix("http://").trimEnd('/')}",
                color = OrzColors.MutedDim,
                fontSize = 10.sp
            )
        }
    }
}

private fun strategyLabel(song: Song): String = when (song.strategy) {
    PlayStrategy.DirectFile -> "直接播放"
    PlayStrategy.ServerDecode -> "服务端解码"
    PlayStrategy.WasmDecode -> "原生 / WASM 解码"
}
