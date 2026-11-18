package com.jokerhub.orzmusic.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.activity.compose.BackHandler
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.Button
import androidx.tv.material3.Card
import androidx.tv.material3.Text
import com.jokerhub.orzmusic.android.ui.screens.ArtistsList
import com.jokerhub.orzmusic.android.ui.screens.LibraryContent
import com.jokerhub.orzmusic.android.ui.screens.NowPlayingScreen
import com.jokerhub.orzmusic.android.ui.screens.PlaylistsList
import com.jokerhub.orzmusic.android.ui.screens.SettingsContent
import com.jokerhub.orzmusic.android.player.VisualizerBus
import com.jokerhub.orzmusic.android.ui.screens.SongListPane
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 应用根节点 —— 手机 / 平板 / TV / VR 共用同一套 Compose。
 *
 * 信息架构对齐 Web 端:
 *   · 宽屏:左侧「浏览 + 格式分组」栏 + 顶栏搜索 + 主内容 + 底部播放坞
 *   · 窄屏:顶部品牌/搜索/标签 + 主内容 + 底部播放坞
 *   · 队列抽屉、正在播放、快捷键说明都是覆盖层
 *
 * 所有可点元素仍用 tv-material3 的 Card/Button:TV 有焦点态,D-pad 能走,
 * 触屏就是普通点击。
 */
@Composable
fun AppRoot(vm: AppViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val visualizerLevels by VisualizerBus.levels.collectAsStateWithLifecycle()
    val latestState by rememberUpdatedState(state)
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val scope = rememberCoroutineScope()
    val initialFocus = remember { FocusRequester() }
    val searchFocus = remember { FocusRequester() }
    val nowPlayingFocus = remember { FocusRequester() }
    val inAppKeyboard = remember { InAppKeyboardState() }

    fun dismissInput() {
        runCatching { keyboard?.hide() }
        focusManager.clearFocus(force = true)
    }

    val openQueue = {
        dismissInput()
        vm.openQueue()
    }
    val openNowPlaying = {
        dismissInput()
        vm.openNowPlaying()
    }
    val openShortcuts = {
        dismissInput()
        vm.toggleShortcuts()
    }

    fun restoreFocus(nowPlaying: Boolean) {
        // Pico 在 IME / PicoXR_CustomDialog 关闭后，原焦点节点会被清掉。
        // 先让 Compose 的焦点系统重新选一个可聚焦节点，再显式请求目标节点。
        focusManager.clearFocus(force = true)
        focusManager.moveFocus(FocusDirection.Next)
        scope.launch {
            delay(260)
            runCatching {
                if (nowPlaying) nowPlayingFocus.requestFocus() else initialFocus.requestFocus()
            }
        }
    }

    // Pico 的 PicoXR_CustomDialog / 软键盘会短暂抢走窗口焦点；
    // 回到前台时主动清掉 IME 并重新把焦点交给当前层，避免 BACK 被系统吃掉。
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        runCatching { keyboard?.hide() }
        focusManager.clearFocus(force = false)
        scope.launch {
            delay(200)
            runCatching {
                when {
                    state.queueOpen || state.showShortcuts -> Unit // 覆盖层自己请求焦点
                    state.showNowPlaying -> nowPlayingFocus.requestFocus()
                    else -> initialFocus.requestFocus()
                }
            }
        }
    }

    // 等首帧把侧栏/标签组合出来再请求焦点,否则 LazyColumn 的 item 还没注册,
    // 焦点会落到顶栏搜索框,电视上一启动就弹输入法。
    // 覆盖层打开/关闭时也要把焦点交还给仍在显示的层。
    LaunchedEffect(state.queueOpen, state.showNowPlaying, state.showShortcuts) {
        if (state.queueOpen || state.showShortcuts) return@LaunchedEffect
        delay(160)
        runCatching {
            if (state.showNowPlaying) nowPlayingFocus.requestFocus()
            else initialFocus.requestFocus()
        }
    }

    // 系统 BACK / 遥控返回键：优先关闭最上层覆盖层。
    // 只靠 onKeyEvent 在 Pico 上不稳定（焦点不在 Compose 时收不到）。
    BackHandler(
        enabled = inAppKeyboard.open || state.queueOpen || state.showShortcuts ||
            state.showNowPlaying || state.isSearching
    ) {
        when {
            inAppKeyboard.open -> {
                inAppKeyboard.close()
                restoreFocus(nowPlaying = false)
            }
            state.showShortcuts -> {
                dismissInput()
                vm.closeShortcuts()
                restoreFocus(nowPlaying = false)
            }
            state.queueOpen -> {
                val keepNowPlaying = state.showNowPlaying
                dismissInput()
                vm.closeQueue()
                restoreFocus(keepNowPlaying)
            }
            state.showNowPlaying -> {
                dismissInput()
                vm.closeNowPlaying()
                restoreFocus(nowPlaying = false)
            }
            state.isSearching -> {
                dismissInput()
                vm.clearSearch()
                restoreFocus(nowPlaying = false)
            }
        }
    }

    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }
    LaunchedEffect(state.current?.id, state.isPlaying, state.decoding) {
        while (isActive) {
            positionMs = vm.playbackPositionMs
            durationMs = vm.playbackDurationMs
            delay(400)
        }
    }

    CompositionLocalProvider(LocalInAppKeyboard provides inAppKeyboard) {
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(OrzColors.Bg)
            .systemBarsPadding()
            .imePadding()
            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                // 应用内键盘打开时，字母键不能再触发播放快捷键。
                if (inAppKeyboard.open && event.key != Key.Escape && event.key != Key.Back) {
                    return@onKeyEvent false
                }
                when (event.key) {
                    Key.Spacebar -> { vm.togglePlay(); true }
                    Key.M -> { vm.toggleMute(); true }
                    Key.N, Key.MediaNext -> { vm.playNext(); true }
                    Key.P, Key.MediaPrevious -> { vm.playPrevious(); true }
                    Key.L -> {
                        vm.closeNowPlaying()
                        vm.closeQueue()
                        vm.locateCurrentSong()
                        true
                    }
                    Key.Q -> { if (state.queueOpen) vm.closeQueue() else vm.openQueue(); true }
                    Key.Slash -> { runCatching { searchFocus.requestFocus() }; true }
                    Key.MediaPlayPause -> { vm.togglePlay(); true }
                    Key.Escape, Key.Back -> when {
                        inAppKeyboard.open -> {
                            inAppKeyboard.close()
                            restoreFocus(false)
                            true
                        }
                        state.showShortcuts -> { dismissInput(); vm.closeShortcuts(); restoreFocus(false); true }
                        state.queueOpen -> {
                            val keepNowPlaying = state.showNowPlaying
                            dismissInput()
                            vm.closeQueue()
                            restoreFocus(keepNowPlaying)
                            true
                        }
                        state.showNowPlaying -> { dismissInput(); vm.closeNowPlaying(); restoreFocus(false); true }
                        state.isSearching -> { dismissInput(); vm.clearSearch(); restoreFocus(false); true }
                        else -> false
                    }
                    else -> false
                }
            }
    ) {
        val wide = maxWidth >= 760.dp

        if (wide) {
            Row(modifier = Modifier.fillMaxSize()) {
                Sidebar(
                    state = state,
                    onTab = vm::selectTab,
                    onFormat = { format ->
                        vm.selectTab(Tab.Library)
                        vm.selectFormat(format)
                    },
                    onShortcuts = vm::toggleShortcuts,
                    initialFocus = initialFocus
                )
                Column(modifier = Modifier.weight(1f).fillMaxHeight()) {
                    TopBar(
                        state = state,
                        wide = true,
                        searchFocus = searchFocus,
                        onSearch = vm::search,
                        onQueue = openQueue,
                        onNowPlaying = openNowPlaying,
                        onShortcuts = openShortcuts
                    )
                    StatusArea(state, vm)
                    Box(modifier = Modifier.weight(1f)) {
                        ContentArea(state, vm, wide = true)
                    }
                    PlayerDock(
                        state, vm, positionMs, durationMs, visualizerLevels,
                        onQueue = openQueue,
                        onNowPlaying = openNowPlaying
                    )
                }
            }
        } else {
            Column(modifier = Modifier.fillMaxSize()) {
                TopBar(
                    state = state,
                    wide = false,
                    searchFocus = searchFocus,
                    onSearch = vm::search,
                    onQueue = openQueue,
                    onNowPlaying = openNowPlaying,
                    onShortcuts = openShortcuts
                )
                CompactTabs(state.tab, vm::selectTab, initialFocus)
                StatusArea(state, vm)
                Box(modifier = Modifier.weight(1f)) {
                    ContentArea(state, vm, wide = false)
                }
                PlayerDock(
                    state, vm, positionMs, durationMs, visualizerLevels,
                    onQueue = openQueue,
                    onNowPlaying = openNowPlaying
                )
            }
        }

        val current = state.current
        if (state.showNowPlaying && current != null) {
            NowPlayingScreen(
                song = current,
                isPlaying = state.isPlaying,
                decoding = state.decoding,
                notice = state.notice,
                positionMs = positionMs,
                durationMs = durationMs,
                volume = state.volume,
                levels = visualizerLevels,
                queueCount = state.queue.size,
                serverUrl = state.serverUrl,
                onBack = {
                    dismissInput()
                    vm.closeNowPlaying()
                },
                onToggle = vm::togglePlay,
                onPrevious = vm::playPrevious,
                onNext = vm::playNext,
                onSeek = vm::seekTo,
                onSeekBy = vm::seekBy,
                onVolume = vm::setVolume,
                onMute = vm::toggleMute,
                onQueue = openQueue,
                focusRequester = nowPlayingFocus,
                onLocate = {
                    dismissInput()
                    vm.closeNowPlaying()
                    vm.locateCurrentSong()
                }
            )
        }

        if (state.queueOpen) {
            QueueDrawer(
                queue = state.queue,
                currentId = state.current?.id,
                playlists = state.playlists,
                onClose = {
                    dismissInput()
                    vm.closeQueue()
                },
                onPlay = { song -> vm.play(song, state.queue) },
                onRemove = vm::removeFromQueue,
                onSavePlaylist = vm::saveQueueAsPlaylist,
                onLoadPlaylist = vm::loadPlaylistIntoQueue,
                onDeletePlaylist = vm::deletePlaylist
            )
        }

        if (state.showShortcuts) {
            ShortcutsDialog(onClose = {
                dismissInput()
                vm.closeShortcuts()
            })
        }

        if (inAppKeyboard.open) {
            InAppKeyboardDialog(
                value = inAppKeyboard.value,
                onValueChange = inAppKeyboard::update,
                onDone = { inAppKeyboard.close() }
            )
        }
    }
    }

    // Pico VRSHELL 抢走焦点后，用户点回 App 时窗口焦点会回来，但 Compose
    // 内部焦点不会自动恢复；补一次 FocusRequester。
    LaunchedEffect(Unit) {
        WindowFocusEvents.events.collect {
            delay(120)
            runCatching {
                when {
                    inAppKeyboard.open || latestState.queueOpen || latestState.showShortcuts -> Unit
                    latestState.showNowPlaying -> nowPlayingFocus.requestFocus()
                    else -> initialFocus.requestFocus()
                }
            }
        }
    }

    // 应用内键盘关闭后把焦点还给原来的输入卡片。
    LaunchedEffect(inAppKeyboard.open) {
        if (!inAppKeyboard.open) {
            delay(80)
            runCatching { inAppKeyboard.returnFocus?.requestFocus() }
        }
    }
}

@Composable
private fun Sidebar(
    state: UiState,
    onTab: (Tab) -> Unit,
    onFormat: (String?) -> Unit,
    onShortcuts: () -> Unit,
    initialFocus: FocusRequester
) {
    val groups = remember(state.formats) { FormatCatalog.groups(state.formats) }
    LazyColumn(
        modifier = Modifier
            .width(220.dp)
            .fillMaxHeight()
            .background(OrzColors.Surface)
            .padding(horizontal = 10.dp),
        contentPadding = PaddingValues(vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        item {
            Row(
                modifier = Modifier.padding(horizontal = 6.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(9.dp)
            ) {
                BrandMark()
                Column {
                    Text("OrzMusic", color = OrzColors.Text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Text("CHIP AUDIO", color = OrzColors.MutedDim, fontSize = 7.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        item { SectionLabel("浏览", Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) }
        item {
            NavItem(
                label = "全部曲目",
                selected = state.tab == Tab.Library && state.selectedFormat == null,
                onClick = { onFormat(null) },
                modifier = Modifier.focusRequester(initialFocus),
                trailing = state.stats?.totalSongs?.toString()
            )
        }
        items(listOf(Tab.Artists, Tab.Playlists, Tab.Settings), key = { it.name }) { tab ->
            NavItem(
                label = tab.label,
                selected = state.tab == tab,
                onClick = { onTab(tab) }
            )
        }

        if (groups.isNotEmpty()) {
            item { SectionLabel("格式", Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) }
        }
        groups.forEach { group ->
            item(key = "g-${group.id}") {
                Text(
                    text = group.label.uppercase(),
                    modifier = Modifier.padding(start = 10.dp, top = 8.dp, bottom = 3.dp),
                    color = OrzColors.MutedDim,
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            items(group.items, key = { "f-${it.id}" }) { meta ->
                FormatNavItem(
                    meta = meta,
                    selected = state.tab == Tab.Library && state.selectedFormat == meta.id,
                    onClick = { onFormat(meta.id) }
                )
            }
        }
        item {
            Spacer(Modifier.height(6.dp))
            NavItem(
                label = "快捷键",
                selected = false,
                onClick = onShortcuts,
                trailing = "?"
            )
        }
    }
}

@Composable
private fun TopBar(
    state: UiState,
    wide: Boolean,
    searchFocus: FocusRequester,
    onSearch: (String) -> Unit,
    onQueue: () -> Unit,
    onNowPlaying: () -> Unit,
    onShortcuts: () -> Unit
) {
    val title = when {
        state.isSearching -> "搜索结果"
        state.tab == Tab.Library -> state.activeFormatLabel
        else -> state.tab.label
    }
    val eyebrow = when (state.tab) {
        Tab.Library -> "音乐资料库"
        Tab.Artists -> "浏览艺术家"
        Tab.Playlists -> "我的歌单"
        Tab.Settings -> "偏好设置"
    }

    if (wide) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Column(modifier = Modifier.widthIn(min = 150.dp)) {
                Text(eyebrow, color = OrzColors.Mint, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                Text(title, color = OrzColors.Text, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
            SearchField(
                value = state.searchQuery,
                placeholder = "搜索曲目或艺术家",
                onValueChange = onSearch,
                focusRequester = searchFocus,
                modifier = Modifier.weight(1f).widthIn(max = 520.dp)
            )
            if (state.current != null) {
                Button(colors = orzButtonColors(), onClick = onNowPlaying) { Text("正在播放") }
            }
            Button(colors = orzButtonColors(), onClick = onQueue) { Text("队列 ${state.queue.size}") }
            Button(colors = orzButtonColors(), onClick = onShortcuts) { Text("?") }
        }
    } else {
        Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                BrandMark()
                Spacer(Modifier.width(8.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text("OrzMusic", color = OrzColors.Text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Text(eyebrow, color = OrzColors.MutedDim, fontSize = 8.sp)
                }
                if (state.current != null) {
                    Button(colors = orzButtonColors(), onClick = onNowPlaying) { Text("♪") }
                }
                Spacer(Modifier.width(6.dp))
                Button(colors = orzButtonColors(), onClick = onQueue) { Text("队列 ${state.queue.size}") }
            }
            Spacer(Modifier.height(7.dp))
            SearchField(
                value = state.searchQuery,
                placeholder = "搜索曲目或艺术家",
                onValueChange = onSearch,
                focusRequester = searchFocus
            )
        }
    }
}

@Composable
private fun CompactTabs(selected: Tab, onSelect: (Tab) -> Unit, initialFocus: FocusRequester) {
    LazyRow(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        items(Tab.entries, key = { it.name }) { tab ->
            Card(
                onClick = { onSelect(tab) },
                modifier = if (tab == Tab.entries.first()) Modifier.focusRequester(initialFocus) else Modifier,
                colors = orzCardColors()
            ) {
                Text(
                    text = tab.label,
                    modifier = Modifier
                        .background(if (selected == tab) OrzColors.MintSoft else OrzColors.SurfaceHigh, RoundedCornerShape(10.dp))
                        .padding(horizontal = 13.dp, vertical = 7.dp),
                    color = if (selected == tab) OrzColors.Mint else OrzColors.Muted,
                    fontSize = 12.sp,
                    fontWeight = if (selected == tab) FontWeight.Bold else FontWeight.Normal
                )
            }
        }
    }
}

@Composable
private fun StatusArea(state: UiState, vm: AppViewModel) {
    state.error?.let { message ->
        StatusBanner(
            text = message,
            accent = OrzColors.Danger,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)
        ) {
            Button(colors = orzButtonColors(), onClick = vm::clearError) { Text("关闭") }
        }
    }
    state.notice?.let { message ->
        StatusBanner(
            text = message,
            accent = OrzColors.Mint,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)
        ) {
            Button(colors = orzButtonColors(), onClick = vm::clearNotice) { Text("关闭") }
        }
    }
}

@Composable
private fun PlayerDock(
    state: UiState,
    vm: AppViewModel,
    positionMs: Long,
    durationMs: Long,
    levels: FloatArray,
    onQueue: () -> Unit,
    onNowPlaying: () -> Unit
) {
    val song = state.current
    val fraction = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(OrzColors.Surface)
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        if (song != null) {
            VisualizerBars(
                levels = levels,
                active = state.isPlaying,
                modifier = Modifier.fillMaxWidth().height(30.dp)
            )
            SeekBar(
                fraction = fraction,
                onSeek = { value -> if (durationMs > 0) vm.seekTo((value * durationMs).toLong()) },
                onSeekBy = vm::seekBy,
                modifier = Modifier.fillMaxWidth()
            )
        } else {
            Spacer(Modifier.height(4.dp))
        }

        BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
            val compact = maxWidth < 620.dp
            if (compact) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        NowPlayingMini(song, state, onOpen = onNowPlaying, modifier = Modifier.weight(1f))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Transport(state, vm, time = "${formatTime(positionMs)} / ${formatTime(durationMs)}")
                        Spacer(Modifier.weight(1f))
                        // 窄屏隐藏滑条（和 Web 在窄屏隐藏音量一致），静音仍可用
                        Text(
                            text = if (state.volume <= 0f) "🔇" else "🔊",
                            modifier = Modifier.clickable { vm.toggleMute() }.padding(6.dp),
                            fontSize = 14.sp
                        )
                    }
                }
            } else {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    NowPlayingMini(song, state, onOpen = onNowPlaying, modifier = Modifier.weight(1.2f))
                    Transport(state, vm, time = "${formatTime(positionMs)} / ${formatTime(durationMs)}")
                    Spacer(Modifier.weight(0.3f))
                    VolumeControl(state.volume, vm::setVolume, vm::toggleMute)
                }
            }
        }
    }
}

@Composable
private fun NowPlayingMini(
    song: com.jokerhub.orzmusic.core.model.Song?,
    state: UiState,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (song == null) {
        Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
            BrandBadge("—", size = 34.dp)
            Column(modifier = Modifier.padding(start = 9.dp)) {
                Text("选择一首曲目开始播放", color = OrzColors.Muted, fontSize = 12.sp)
                Text("支持原生 · 服务端 · 直接播放", color = OrzColors.MutedDim, fontSize = 9.sp)
            }
        }
        return
    }
    Card(onClick = onOpen, modifier = modifier, colors = orzCardColors()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            BrandBadge(song.fileFormat, size = 34.dp)
            Column(modifier = Modifier.padding(start = 9.dp).weight(1f, fill = false)) {
                Text(
                    text = song.title,
                    color = OrzColors.Text,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = "${song.artistName} · ${song.fileFormat.uppercase()}" +
                        if (state.decoding) " · 解码中…" else "",
                    color = OrzColors.Muted,
                    fontSize = 9.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun Transport(state: UiState, vm: AppViewModel, time: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Button(colors = orzButtonColors(), onClick = vm::playPrevious) { Text("|◀") }
        Button(colors = orzButtonColors(), onClick = vm::togglePlay) { Text(if (state.isPlaying) "II" else "▶") }
        Button(colors = orzButtonColors(), onClick = vm::playNext) { Text("▶|") }
        Text(time, color = OrzColors.Muted, fontSize = 9.sp)
    }
}

@Composable
private fun VolumeControl(volume: Float, onChange: (Float) -> Unit, onMute: () -> Unit) {
    Row(
        modifier = Modifier.widthIn(max = 180.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = if (volume <= 0f) "🔇" else "🔊",
            modifier = Modifier.clickable { onMute() }.padding(4.dp),
            fontSize = 13.sp
        )
        VolumeSlider(volume = volume, onChange = onChange, modifier = Modifier.width(86.dp))
        Text("${(volume * 100).toInt()}%", color = OrzColors.MutedDim, fontSize = 9.sp)
    }
}

@Composable
private fun ContentArea(state: UiState, vm: AppViewModel, wide: Boolean) {
    when (state.tab) {
        Tab.Library -> LibraryContent(
            songs = state.visibleSongs,
            formats = state.formats,
            selectedFormat = state.selectedFormat,
            totalSongs = state.songTotal.takeIf { it > 0 } ?: state.stats?.totalSongs ?: 0,
            totalArtists = state.stats?.totalArtists ?: 0,
            loading = state.loading,
            isSearching = state.isSearching,
            searchQuery = state.searchQuery,
            currentId = state.current?.id,
            isPlaying = state.isPlaying,
            locatedSongId = state.locatedSongId,
            onFormat = vm::selectFormat,
            onSong = vm::play,
            onLoadMore = vm::loadMoreSongs,
            onClearSearch = vm::clearSearch,
            modifier = Modifier.fillMaxSize()
        )

        Tab.Artists -> {
            if (wide) {
                Row(modifier = Modifier.fillMaxSize()) {
                    Box(modifier = Modifier.width(320.dp).fillMaxHeight()) {
                        ArtistsList(
                            artists = state.artists,
                            loading = state.loading,
                            selectedArtistId = state.detailId,
                            onArtist = vm::openArtist
                        )
                    }
                    Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                        if (state.detailTitle != null) {
                            SongListPane(
                                title = state.detailTitle ?: "",
                                subtitle = state.detailSubtitle,
                                songs = state.detailSongs,
                                loading = state.loading,
                                currentId = state.current?.id,
                                isPlaying = state.isPlaying,
                                onBack = vm::closeDetail,
                                onSong = vm::play
                            )
                        } else {
                            EmptyPane("选择一位艺术家", Modifier.fillMaxSize())
                        }
                    }
                }
            } else if (state.detailTitle != null) {
                SongListPane(
                    title = state.detailTitle ?: "",
                    subtitle = state.detailSubtitle,
                    songs = state.detailSongs,
                    loading = state.loading,
                    currentId = state.current?.id,
                    isPlaying = state.isPlaying,
                    onBack = vm::closeDetail,
                    onSong = vm::play
                )
            } else {
                ArtistsList(
                    artists = state.artists,
                    loading = state.loading,
                    selectedArtistId = null,
                    onArtist = vm::openArtist
                )
            }
        }

        Tab.Playlists -> {
            if (wide) {
                Row(modifier = Modifier.fillMaxSize()) {
                    Box(modifier = Modifier.width(320.dp).fillMaxHeight()) {
                        PlaylistsList(
                            playlists = state.playlists,
                            loading = state.loading,
                            selectedPlaylistId = state.detailId,
                            onPlaylist = vm::openPlaylist
                        )
                    }
                    Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                        if (state.detailTitle != null) {
                            SongListPane(
                                title = state.detailTitle ?: "",
                                subtitle = state.detailSubtitle,
                                songs = state.detailSongs,
                                loading = state.loading,
                                currentId = state.current?.id,
                                isPlaying = state.isPlaying,
                                onBack = vm::closeDetail,
                                onSong = vm::play
                            )
                        } else {
                            EmptyPane("选择一个歌单", Modifier.fillMaxSize())
                        }
                    }
                }
            } else if (state.detailTitle != null) {
                SongListPane(
                    title = state.detailTitle ?: "",
                    subtitle = state.detailSubtitle,
                    songs = state.detailSongs,
                    loading = state.loading,
                    currentId = state.current?.id,
                    isPlaying = state.isPlaying,
                    onBack = vm::closeDetail,
                    onSong = vm::play
                )
            } else {
                PlaylistsList(
                    playlists = state.playlists,
                    loading = state.loading,
                    selectedPlaylistId = null,
                    onPlaylist = vm::openPlaylist
                )
            }
        }

        Tab.Settings -> SettingsContent(
            serverUrl = state.serverUrl,
            notice = state.notice,
            version = com.jokerhub.orzmusic.android.BuildConfig.VERSION_NAME,
            onSave = vm::updateServerUrl,
            onCheck = vm::checkServer,
            onShortcuts = vm::toggleShortcuts,
            modifier = Modifier.fillMaxSize()
        )
    }
}
