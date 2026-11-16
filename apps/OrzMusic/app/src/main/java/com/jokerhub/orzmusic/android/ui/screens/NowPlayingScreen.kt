package com.jokerhub.orzmusic.android.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Button
import androidx.tv.material3.Text
import com.jokerhub.orzmusic.core.model.PlayStrategy
import com.jokerhub.orzmusic.core.model.Song
import com.jokerhub.orzmusic.core.model.strategy
import com.jokerhub.orzmusic.android.ui.BrandBadge
import com.jokerhub.orzmusic.android.ui.OrzColors
import com.jokerhub.orzmusic.android.ui.ProgressTrack

/**
 * 全屏"正在播放"。
 *
 * `wasmDecode` 的曲目在这里会显示解释 + 网页播放器入口 —— 不是 UI 缺陷,
 * 而是服务端设计如此:模块音乐的解码在浏览器 WASM 里。
 */
@Composable
fun NowPlayingScreen(
    song: Song,
    isPlaying: Boolean,
    decoding: Boolean,
    notice: String?,
    positionMs: Long,
    durationMs: Long,
    serverUrl: String,
    onBack: () -> Unit,
    onToggle: () -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val unsupported = song.strategy == PlayStrategy.WasmDecode && !decoding
    val fraction = if (durationMs > 0) positionMs.toFloat() / durationMs.toFloat() else 0f

    Box(modifier = modifier.fillMaxSize().background(OrzColors.Bg)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 28.dp, vertical = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Button(onClick = onBack) { Text("返回") }
                Spacer(Modifier.weight(1f))
                Text(
                    text = song.fileFormat.uppercase(),
                    color = OrzColors.Muted,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Spacer(Modifier.weight(1f))

            BrandBadge(format = song.fileFormat, size = 120.dp)
            Spacer(Modifier.height(22.dp))
            Text(
                text = song.title,
                color = OrzColors.Text,
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = "${song.artistName} · ${song.durationText} · ${song.sizeText}",
                color = OrzColors.Muted,
                fontSize = 13.sp
            )

            if (decoding) {
                Spacer(Modifier.height(20.dp))
                Text(
                    text = "正在解码 ${song.fileFormat.uppercase()}…",
                    color = OrzColors.Mint,
                    fontSize = 14.sp,
                    textAlign = TextAlign.Center
                )
            } else if (unsupported && notice != null) {
                Spacer(Modifier.height(20.dp))
                Text(
                    text = notice,
                    color = OrzColors.Warm,
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth(0.8f)
                        .padding(14.dp)
                )
                Button(onClick = {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(serverUrl))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                }) {
                    Text("在网页播放器打开")
                }
            }

            if (!decoding) {
                Spacer(Modifier.height(26.dp))
                ProgressTrack(fraction = fraction, modifier = Modifier.fillMaxWidth(0.75f))
                Row(
                    modifier = Modifier
                        .fillMaxWidth(0.75f)
                        .padding(top = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(formatTime(positionMs), color = OrzColors.Muted, fontSize = 11.sp)
                    Text(formatTime(durationMs), color = OrzColors.Muted, fontSize = 11.sp)
                }

                Spacer(Modifier.height(18.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Button(onClick = onPrevious) { Text("上一首") }
                    Button(onClick = onToggle) {
                        Text(if (isPlaying) "暂停" else "播放")
                    }
                    Button(onClick = onNext) { Text("下一首") }
                }
                if (durationMs > 0) {
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = { onSeek(0L) }) { Text("回到开头") }
                }
            }

            Spacer(Modifier.weight(1f))
            Text(
                text = "OrzMusic · ${serverUrl.removePrefix("https://").removePrefix("http://").trimEnd('/')}",
                color = OrzColors.Muted,
                fontSize = 10.sp
            )
        }
    }
}

private fun formatTime(ms: Long): String {
    if (ms <= 0) return "0:00"
    val total = ms / 1000
    return "%d:%02d".format(total / 60, total % 60)
}
