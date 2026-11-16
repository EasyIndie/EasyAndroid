package com.jokerhub.orzmusic.android.ui

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.Button
import androidx.tv.material3.Card
import androidx.tv.material3.Text
import com.jokerhub.orzmusic.android.ui.screens.ArtistsList
import com.jokerhub.orzmusic.android.ui.screens.LibraryContent
import com.jokerhub.orzmusic.android.ui.screens.NowPlayingScreen
import com.jokerhub.orzmusic.android.ui.screens.PlaylistsList
import com.jokerhub.orzmusic.android.ui.screens.SearchContent
import com.jokerhub.orzmusic.android.ui.screens.SettingsContent
import com.jokerhub.orzmusic.android.ui.screens.SongListPane
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

/**
 * 应用根节点 —— 手机 / 平板 / TV / VR 共用同一套 Compose。
 *
 * 自适应判据只有一条:**可用宽度**。
 *   · < 760dp:顶部标签 + 单栏(手机竖屏、小平板)
 *   · ≥ 760dp:左侧导航栏 + 主内容(平板横屏、TV、Pico 2D 面板)
 *   · 艺术家/歌单在宽屏下再拆成「列表 + 详情」两栏
 *
 * 所有可点元素都用 tv-material3 的 [Card]:它在 TV 上有焦点态,D-pad 能走;
 * 在触屏上就是普通点击。VR 里 Pico 的 2D 面板同样按宽屏处理。
 */
@Composable
fun AppRoot(vm: AppViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val initialFocus = remember { FocusRequester() }

    // TV / VR 启动时焦点必须落在「曲库」,否则第一次按 OK 可能选到别的 tab。
    LaunchedEffect(Unit) { runCatching { initialFocus.requestFocus() } }

    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }
    LaunchedEffect(state.current?.id, state.isPlaying) {
        while (isActive) {
            positionMs = vm.playbackPositionMs
            durationMs = vm.playbackDurationMs
            delay(500)
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(OrzColors.Bg)
            .systemBarsPadding()
            .imePadding()
    ) {
        val wide = maxWidth >= 760.dp

        if (wide) {
            Row(modifier = Modifier.fillMaxSize()) {
                NavRail(state.tab, vm::selectTab, initialFocus)
                Column(modifier = Modifier.weight(1f).fillMaxHeight()) {
                    TopBar(state, wide = true)
                    ErrorBanner(state.error, vm::clearError)
                    Box(modifier = Modifier.weight(1f)) {
                        ContentArea(state, vm, wide = true)
                    }
                    MiniPlayer(state, vm)
                }
            }
        } else {
            Column(modifier = Modifier.fillMaxSize()) {
                TopBar(state, wide = false)
                CompactTabs(state.tab, vm::selectTab, initialFocus)
                ErrorBanner(state.error, vm::clearError)
                Box(modifier = Modifier.weight(1f)) {
                    ContentArea(state, vm, wide = false)
                }
                MiniPlayer(state, vm)
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
                serverUrl = state.serverUrl,
                onBack = vm::closeNowPlaying,
                onToggle = vm::togglePlay,
                onPrevious = vm::playPrevious,
                onNext = vm::playNext,
                onSeek = vm::seekTo
            )
        }
    }
}

@Composable
private fun BrandMark() {
    Row(
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        listOf(10, 18, 26, 14, 22).forEach { h ->
            Box(
                modifier = Modifier
                    .width(3.dp)
                    .height(h.dp)
                    .background(OrzColors.Mint, RoundedCornerShape(2.dp))
            )
        }
    }
}

@Composable
private fun NavRail(selected: Tab, onSelect: (Tab) -> Unit, initialFocus: FocusRequester) {
    Column(
        modifier = Modifier
            .width(210.dp)
            .fillMaxHeight()
            .background(OrzColors.Surface)
            .padding(horizontal = 12.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            BrandMark()
            Text(
                text = "OrzMusic",
                color = OrzColors.Warm,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Tab.entries.forEachIndexed { index, tab ->
            NavItem(
                label = tab.label,
                selected = selected == tab,
                onClick = { onSelect(tab) },
                modifier = if (index == 0) Modifier.focusRequester(initialFocus) else Modifier
            )
        }
    }
}

@Composable
private fun CompactTabs(selected: Tab, onSelect: (Tab) -> Unit, initialFocus: FocusRequester) {
    LazyRow(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        itemsIndexed(Tab.entries, key = { _, tab -> tab.name }) { index, tab ->
            Card(
                onClick = { onSelect(tab) },
                modifier = if (index == 0) Modifier.focusRequester(initialFocus) else Modifier
            ) {
                Text(
                    text = tab.label,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                    color = if (selected == tab) OrzColors.Mint else OrzColors.Text,
                    fontSize = 13.sp,
                    fontWeight = if (selected == tab) FontWeight.Bold else FontWeight.Normal
                )
            }
        }
    }
}

@Composable
private fun TopBar(state: UiState, wide: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (!wide) {
            BrandMark()
            Spacer(Modifier.width(10.dp))
            Text(
                text = "OrzMusic",
                color = OrzColors.Warm,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold
            )
        } else {
            Text(
                text = state.tab.label,
                color = OrzColors.Text,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Spacer(Modifier.weight(1f))
        Text(
            text = state.serverUrl
                .removePrefix("https://")
                .removePrefix("http://")
                .trimEnd('/'),
            color = OrzColors.Muted,
            fontSize = 11.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun ErrorBanner(error: String?, onDismiss: () -> Unit) {
    if (error == null) return
    StatusBanner(
        text = error,
        accent = OrzColors.Danger,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Button(onClick = onDismiss) { Text("关闭") }
    }
}

@Composable
private fun MiniPlayer(state: UiState, vm: AppViewModel) {
    val song = state.current ?: return
    Card(
        onClick = vm::openNowPlaying,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            BrandBadge(format = song.fileFormat, size = 36.dp)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = song.title,
                    color = OrzColors.Text,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = "${song.artistName} · ${if (state.decoding) "解码中…" else song.fileFormat.uppercase()}",
                    color = OrzColors.Muted,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Button(onClick = vm::togglePlay) {
                Text(if (state.isPlaying) "暂停" else "播放")
            }
            Button(onClick = vm::playNext) { Text("下一首") }
        }
    }
}

@Composable
private fun ContentArea(state: UiState, vm: AppViewModel, wide: Boolean) {
    when (state.tab) {
        Tab.Library -> LibraryContent(
            songs = state.songs,
            formats = state.formats,
            selectedFormat = state.selectedFormat,
            totalSongs = state.songTotal.takeIf { it > 0 } ?: state.stats?.totalSongs ?: 0,
            totalArtists = state.stats?.totalArtists ?: 0,
            loading = state.loading,
            onFormat = vm::selectFormat,
            onSong = vm::play,
            onLoadMore = vm::loadMoreSongs,
            modifier = Modifier.fillMaxSize()
        )

        Tab.Artists -> {
            if (wide) {
                Row(modifier = Modifier.fillMaxSize()) {
                    Box(modifier = Modifier.width(320.dp).fillMaxHeight()) {
                        ArtistsList(
                            artists = state.artists,
                            loading = state.loading,
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
                                onBack = vm::closeDetail,
                                onSong = vm::play
                            )
                        } else {
                            EmptyPane("选择一位艺术家", Modifier.fillMaxSize())
                        }
                    }
                }
            } else {
                if (state.detailTitle != null) {
                    SongListPane(
                        title = state.detailTitle ?: "",
                        subtitle = state.detailSubtitle,
                        songs = state.detailSongs,
                        loading = state.loading,
                        onBack = vm::closeDetail,
                        onSong = vm::play
                    )
                } else {
                    ArtistsList(
                        artists = state.artists,
                        loading = state.loading,
                        onArtist = vm::openArtist
                    )
                }
            }
        }

        Tab.Playlists -> {
            if (wide) {
                Row(modifier = Modifier.fillMaxSize()) {
                    Box(modifier = Modifier.width(320.dp).fillMaxHeight()) {
                        PlaylistsList(
                            playlists = state.playlists,
                            loading = state.loading,
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
                                onBack = vm::closeDetail,
                                onSong = vm::play
                            )
                        } else {
                            EmptyPane("选择一个歌单", Modifier.fillMaxSize())
                        }
                    }
                }
            } else {
                if (state.detailTitle != null) {
                    SongListPane(
                        title = state.detailTitle ?: "",
                        subtitle = state.detailSubtitle,
                        songs = state.detailSongs,
                        loading = state.loading,
                        onBack = vm::closeDetail,
                        onSong = vm::play
                    )
                } else {
                    PlaylistsList(
                        playlists = state.playlists,
                        loading = state.loading,
                        onPlaylist = vm::openPlaylist
                    )
                }
            }
        }

        Tab.Search -> SearchContent(
            query = state.searchQuery,
            results = state.searchResults,
            loading = state.loading,
            onQuery = vm::search,
            onSong = vm::play,
            modifier = Modifier.fillMaxSize()
        )

        Tab.Settings -> SettingsContent(
            serverUrl = state.serverUrl,
            notice = state.notice,
            version = com.jokerhub.orzmusic.android.BuildConfig.VERSION_NAME,
            onSave = vm::updateServerUrl,
            onCheck = vm::checkServer,
            modifier = Modifier.fillMaxSize()
        )
    }
}
