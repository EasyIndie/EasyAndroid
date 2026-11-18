package com.jokerhub.orzmusic.android.ui

import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonColors
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.Card
import androidx.tv.material3.CardColors
import androidx.tv.material3.CardDefaults
import androidx.tv.material3.Text
import com.jokerhub.orzmusic.core.model.Song

/**
 * tv-material3 的 Card 默认用 `surfaceVariant`，在本应用的深色底上会发灰。
 * 统一改成透明容器，由内容自己画背景；焦点态仍由 tv-material3 提供。
 */
/** 统一按钮配色：深色底、薄荷焦点，避免默认主题的橙色/紫色。 */
@Composable
fun orzButtonColors(): ButtonColors =
    ButtonDefaults.colors(
        containerColor = OrzColors.SurfaceHigh,
        contentColor = OrzColors.Text,
        focusedContainerColor = OrzColors.Mint,
        focusedContentColor = OrzColors.Bg,
        pressedContainerColor = OrzColors.MintDim,
        pressedContentColor = OrzColors.Text
    )

@Composable
fun orzCardColors(container: Color = Color.Transparent): CardColors =
    CardDefaults.colors(
        containerColor = container,
        contentColor = OrzColors.Text
    )

/** 品牌波形标记（Web 端 logo 的极简化）。 */
@Composable
fun BrandMark(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        listOf(7, 15, 22, 11, 18).forEach { h ->
            Box(
                modifier = Modifier
                    .width(3.dp)
                    .height(h.dp)
                    .background(OrzColors.Mint, RoundedCornerShape(2.dp))
            )
        }
    }
}

/** 格式徽标：后端没有专辑封面，用带格式色的 badge 代替。 */
@Composable
fun BrandBadge(
    format: String,
    modifier: Modifier = Modifier,
    size: Dp = 44.dp
) {
    val meta = FormatCatalog.meta(format)
    Box(
        modifier = modifier
            .size(size)
            .background(
                brush = Brush.linearGradient(
                    listOf(meta.color.copy(alpha = 0.95f), meta.color.copy(alpha = 0.55f), OrzColors.SurfaceHigh)
                ),
                shape = RoundedCornerShape(12.dp)
            )
            .border(1.dp, meta.color.copy(alpha = 0.25f), RoundedCornerShape(12.dp)),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = meta.label.take(4).uppercase(),
            color = OrzColors.Bg,
            fontSize = if (size >= 80.dp) 16.sp else 9.sp,
            fontWeight = FontWeight.Black,
            maxLines = 1
        )
    }
}

@Composable
fun FormatTag(format: String, modifier: Modifier = Modifier) {
    val meta = FormatCatalog.meta(format)
    Text(
        text = meta.label.uppercase(),
        modifier = modifier
            .background(meta.color.copy(alpha = 0.11f), RoundedCornerShape(6.dp))
            .border(1.dp, meta.color.copy(alpha = 0.24f), RoundedCornerShape(6.dp))
            .padding(horizontal = 6.dp, vertical = 3.dp),
        color = meta.color,
        fontSize = 9.sp,
        fontWeight = FontWeight.Black,
        maxLines = 1
    )
}

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier,
        color = OrzColors.MutedDim,
        fontSize = 10.sp,
        fontWeight = FontWeight.Bold
    )
}

/**
 * 歌曲行。信息层级对齐网页端表格：标题 / 艺术家 / 专辑 / 格式 / 大小 / 时长。
 * 窄屏只保留标题、艺术家、格式、时长，避免横向滚动。
 */
@Composable
fun SongRow(
    song: Song,
    isCurrent: Boolean,
    isPlaying: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    showArtist: Boolean = true,
    showAlbum: Boolean = false,
    showSize: Boolean = false
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        colors = orzCardColors()
    ) {
        Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(if (isCurrent) OrzColors.MintSoft else Color.Transparent)
                .padding(horizontal = 12.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier.width(30.dp),
                contentAlignment = Alignment.Center
            ) {
                if (isCurrent && isPlaying) {
                    PlayBars()
                } else {
                    Text(
                        text = if (isCurrent) "●" else "▶",
                        color = if (isCurrent) OrzColors.Mint else OrzColors.MutedDim,
                        fontSize = 10.sp
                    )
                }
            }
            BrandBadge(song.fileFormat, size = 36.dp)
            Column(
                modifier = Modifier
                    .weight(2f)
                    .padding(start = 12.dp)
            ) {
                Text(
                    text = song.title,
                    color = if (isCurrent) OrzColors.Mint else OrzColors.Text,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = if (showArtist) {
                        song.album?.title?.takeIf { it.isNotBlank() } ?: song.artistName
                    } else {
                        "${song.artistName} · ${song.fileFormat.uppercase()}"
                    },
                    color = OrzColors.Muted,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (showArtist) {
                Text(
                    text = song.artistName,
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 14.dp),
                    color = OrzColors.Muted,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (showAlbum) {
                Text(
                    text = song.album?.title?.takeIf { it.isNotBlank() } ?: "—",
                    modifier = Modifier
                        .weight(1.1f)
                        .padding(start = 14.dp),
                    color = OrzColors.Muted,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            FormatTag(song.fileFormat, Modifier.padding(start = 12.dp))
            if (showSize) {
                Text(
                    text = song.sizeText,
                    modifier = Modifier
                        .width(70.dp)
                        .padding(start = 12.dp),
                    color = OrzColors.Muted,
                    fontSize = 11.sp,
                    maxLines = 1
                )
            }
            Text(
                text = song.durationText,
                modifier = Modifier
                    .width(48.dp)
                    .padding(start = 10.dp),
                color = OrzColors.Muted,
                fontSize = 11.sp,
                maxLines = 1
            )
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(OrzColors.Line.copy(alpha = 0.55f))
        )
        }
    }
}

@Composable
fun SongTableHeader(
    showAlbum: Boolean,
    showSize: Boolean = false,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Spacer(Modifier.width(30.dp))
        Spacer(Modifier.width(36.dp))
        Text("标题", Modifier.weight(2f).padding(start = 12.dp), color = OrzColors.MutedDim, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        Text("艺术家", Modifier.weight(1f).padding(start = 14.dp), color = OrzColors.MutedDim, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        if (showAlbum) {
            Text("专辑", Modifier.weight(1.1f).padding(start = 14.dp), color = OrzColors.MutedDim, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
        Text("格式", Modifier.padding(start = 12.dp), color = OrzColors.MutedDim, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        if (showSize) {
            Text(
                "大小",
                Modifier.width(70.dp).padding(start = 12.dp),
                color = OrzColors.MutedDim,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Text(
            "时长",
            Modifier.width(48.dp).padding(start = 10.dp),
            color = OrzColors.MutedDim,
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
fun PlayBars(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        listOf(5, 9, 6, 11, 7).forEach { h ->
            Box(
                modifier = Modifier
                    .width(2.dp)
                    .height(h.dp)
                    .background(OrzColors.Mint, CircleShape)
            )
        }
    }
}

@Composable
fun ArtistRow(
    name: String,
    subtitle: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        colors = orzCardColors()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(if (selected) OrzColors.MintSoft else Color.Transparent)
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .background(OrzColors.SurfaceHigh, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = name.take(1).uppercase(),
                    color = OrzColors.Mint,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 12.dp)
            ) {
                Text(
                    text = name,
                    color = if (selected) OrzColors.Mint else OrzColors.Text,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = subtitle,
                    color = OrzColors.Muted,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Text("›", color = OrzColors.MutedDim, fontSize = 20.sp)
        }
    }
}

@Composable
fun NavItem(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    trailing: String? = null
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        colors = orzCardColors()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(if (selected) OrzColors.MintSoft else Color.Transparent)
                .padding(horizontal = 10.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .background(if (selected) OrzColors.Mint else Color.Transparent, CircleShape)
            )
            Text(
                text = label,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 9.dp),
                color = if (selected) OrzColors.Text else OrzColors.Muted,
                fontSize = 13.sp,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                maxLines = 1
            )
            if (trailing != null) {
                Text(trailing, color = if (selected) OrzColors.Mint else OrzColors.MutedDim, fontSize = 10.sp)
            }
        }
    }
}

@Composable
fun FormatNavItem(
    meta: FormatMeta,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        colors = orzCardColors()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(if (selected) OrzColors.MintSoft else Color.Transparent)
                .padding(horizontal = 10.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .background(meta.color, CircleShape)
            )
            Text(
                text = meta.label,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 9.dp),
                color = if (selected) OrzColors.Text else OrzColors.Muted,
                fontSize = 12.sp,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                maxLines = 1
            )
            Text(
                text = meta.count.toString(),
                color = if (selected) meta.color else OrzColors.MutedDim,
                fontSize = 10.sp
            )
        }
    }
}

@Composable
fun FormatChip(
    label: String,
    count: Int?,
    selected: Boolean,
    onClick: () -> Unit,
    color: Color = OrzColors.Mint
) {
    Card(onClick = onClick, colors = orzCardColors()) {
        Row(
            modifier = Modifier
                .background(if (selected) color.copy(alpha = 0.14f) else Color.Transparent, RoundedCornerShape(10.dp))
                .border(1.dp, if (selected) color.copy(alpha = 0.45f) else OrzColors.Line, RoundedCornerShape(10.dp))
                .padding(horizontal = 11.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Text(
                text = label.uppercase(),
                color = if (selected) color else OrzColors.Muted,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold
            )
            if (count != null) {
                Text(text = count.toString(), color = OrzColors.MutedDim, fontSize = 9.sp)
            }
        }
    }
}

/** 顶栏搜索框；对 TV 先把焦点落进去，再让系统弹输入法。 */
@Composable
fun SearchField(
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    focusRequester: FocusRequester? = null
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current
    val needsInAppKeyboard = remember {
        Build.MANUFACTURER.equals("Pico", ignoreCase = true) ||
            Build.MODEL.contains("A8110", ignoreCase = true)
    }
    val inAppKeyboard = LocalInAppKeyboard.current
    val localFocus = remember { FocusRequester() }
    val fieldFocus = focusRequester ?: localFocus

    if (needsInAppKeyboard && inAppKeyboard != null) {
        // Pico 的系统 IME 会创建 PicoXR_CustomDialog 抢焦点；这里改成只读卡片 +
        // 应用内键盘，整个输入过程焦点都留在 App 的 display。
        Card(
            onClick = { inAppKeyboard.show(value, onValueChange, fieldFocus) },
            modifier = modifier
                .fillMaxWidth()
                .then(Modifier.focusRequester(fieldFocus)),
            colors = orzCardColors(OrzColors.SurfaceHigh)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(38.dp)
                    .padding(horizontal = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("⌕", color = OrzColors.Muted, fontSize = 16.sp)
                Text(
                    text = value.ifEmpty { placeholder },
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                    color = if (value.isEmpty()) OrzColors.MutedDim else OrzColors.Text,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text("⌨", color = OrzColors.Muted, fontSize = 13.sp)
            }
        }
        return
    }

    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = true,
        interactionSource = interaction,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(
            onSearch = {
                runCatching { keyboard?.hide() }
                focusManager.clearFocus(force = true)
            }
        ),
        textStyle = TextStyle(color = OrzColors.Text, fontSize = 13.sp),
        cursorBrush = SolidColor(OrzColors.Mint),
        modifier = modifier
            .fillMaxWidth()
            .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier),
        decorationBox = { inner ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(38.dp)
                    .background(OrzColors.SurfaceHigh, RoundedCornerShape(10.dp))
                    .border(
                        1.dp,
                        if (focused) OrzColors.Mint.copy(alpha = 0.55f) else OrzColors.Line,
                        RoundedCornerShape(10.dp)
                    )
                    .padding(horizontal = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("⌕", color = OrzColors.Muted, fontSize = 16.sp)
                Box(modifier = Modifier.weight(1f).padding(horizontal = 8.dp)) {
                    if (value.isEmpty()) {
                        Text(placeholder, color = OrzColors.MutedDim, fontSize = 12.sp, maxLines = 1)
                    }
                    inner()
                }
                if (value.isNotEmpty()) {
                    Text(
                        text = "✕",
                        modifier = Modifier.clickable { onValueChange("") }.padding(4.dp),
                        color = OrzColors.Muted,
                        fontSize = 12.sp
                    )
                }
            }
        }
    )
}

/** 无 material3 依赖的进度条。 */
@Composable
fun ProgressTrack(
    fraction: Float,
    modifier: Modifier = Modifier,
    height: Dp = 4.dp,
    color: Color = OrzColors.Mint
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .background(OrzColors.Line, CircleShape)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction.coerceIn(0f, 1f))
                .height(height)
                .background(color, CircleShape)
        )
    }
}

/**
 * 可点击 / 可拖动 / 可用 D-pad 左右键 seek 的进度条。
 * Web 端是 `pointermove` 预览 + 点击 seek；Android 上同时照顾触屏与遥控。
 */
@Composable
fun SeekBar(
    fraction: Float,
    onSeek: (Float) -> Unit,
    onSeekBy: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(24.dp)
            .focusable()
            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (event.key) {
                    Key.DirectionLeft -> { onSeekBy(-5_000); true }
                    Key.DirectionRight -> { onSeekBy(5_000); true }
                    else -> false
                }
            }
            .pointerInput(Unit) {
                detectTapGestures { offset ->
                    onSeek((offset.x / size.width.toFloat()).coerceIn(0f, 1f))
                }
            }
            .pointerInput(Unit) {
                detectDragGestures { change, _ ->
                    onSeek((change.position.x / size.width.toFloat()).coerceIn(0f, 1f))
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(4.dp)
                .background(OrzColors.Line, CircleShape)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction.coerceIn(0f, 1f))
                    .height(4.dp)
                    .background(OrzColors.Mint, CircleShape)
            )
        }
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction.coerceIn(0f, 1f))
                .height(4.dp),
            contentAlignment = Alignment.CenterEnd
        ) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .background(OrzColors.Text, CircleShape)
                    .border(2.dp, OrzColors.Mint, CircleShape)
            )
        }
    }
}

/** 音量滑条：不依赖系统媒体音量，直接改 ExoPlayer 的 volume。 */
@Composable
fun VolumeSlider(
    volume: Float,
    onChange: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .height(24.dp)
            .focusable()
            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (event.key) {
                    Key.DirectionLeft, Key.DirectionDown -> { onChange(volume - 0.05f); true }
                    Key.DirectionRight, Key.DirectionUp -> { onChange(volume + 0.05f); true }
                    else -> false
                }
            }
            .pointerInput(Unit) {
                detectTapGestures { offset ->
                    onChange((offset.x / size.width.toFloat()).coerceIn(0f, 1f))
                }
            }
            .pointerInput(Unit) {
                detectDragGestures { change, _ ->
                    onChange((change.position.x / size.width.toFloat()).coerceIn(0f, 1f))
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(3.dp)
                .background(OrzColors.Line, CircleShape)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(volume.coerceIn(0f, 1f))
                    .height(3.dp)
                    .background(OrzColors.Mint, CircleShape)
            )
        }
    }
}

@Composable
fun EmptyPane(text: String, modifier: Modifier = Modifier) {
    Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("∿", color = OrzColors.MutedDim, fontSize = 34.sp)
            Text(text = text, color = OrzColors.Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
        }
    }
}

@Composable
fun StatusBanner(
    text: String,
    accent: Color,
    modifier: Modifier = Modifier,
    action: (@Composable () -> Unit)? = null
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(OrzColors.SurfaceHigh, RoundedCornerShape(12.dp))
            .border(1.dp, accent.copy(alpha = 0.25f), RoundedCornerShape(12.dp))
            .padding(horizontal = 14.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(text = text, color = accent, fontSize = 12.sp)
        action?.invoke()
    }
}

fun formatTime(ms: Long): String {
    if (ms <= 0) return "0:00"
    val total = ms / 1000
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}


/**
 * 真实 PCM 声场柱状图（数据来自 [com.jokerhub.orzmusic.android.player.VisualizerBus]）。
 *
 * 没有数据时保持低平柱，不伪造随机波形；这样“没接上”一眼能看出来。
 */
@Composable
fun VisualizerBars(
    levels: FloatArray,
    active: Boolean,
    modifier: Modifier = Modifier,
    color: Color = OrzColors.Mint
) {
    Canvas(modifier = modifier) {
        val bars = levels.size.coerceAtLeast(1)
        val gap = 3.dp.toPx()
        val barWidth = ((size.width - gap * (bars - 1)) / bars).coerceAtLeast(1f)
        val middle = size.height / 2f
        for (i in 0 until bars) {
            val level = levels.getOrElse(i) { 0f }.coerceIn(0f, 1f)
            val h = size.height * (0.07f + 0.93f * level)
            val x = i * (barWidth + gap)
            drawRoundRect(
                color = if (active) color.copy(alpha = 0.62f) else OrzColors.MintDim.copy(alpha = 0.35f),
                topLeft = Offset(x, middle - h / 2f),
                size = Size(barWidth, h),
                cornerRadius = CornerRadius(barWidth / 2f, barWidth / 2f)
            )
        }
    }
}
