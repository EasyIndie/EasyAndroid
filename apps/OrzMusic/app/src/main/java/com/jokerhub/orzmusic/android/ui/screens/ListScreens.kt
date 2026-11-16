package com.jokerhub.orzmusic.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Button
import androidx.tv.material3.Card
import androidx.tv.material3.Text
import com.jokerhub.orzmusic.core.model.Artist
import com.jokerhub.orzmusic.core.model.Playlist
import com.jokerhub.orzmusic.core.model.Song
import com.jokerhub.orzmusic.android.ui.ArtistRow
import com.jokerhub.orzmusic.android.ui.EmptyPane
import com.jokerhub.orzmusic.android.ui.OrzColors
import com.jokerhub.orzmusic.android.ui.SongRow

@Composable
fun ArtistsList(
    artists: List<Artist>,
    loading: Boolean,
    onArtist: (Artist) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxSize()) {
        Text(
            text = "艺术家",
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
            color = OrzColors.Mint,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold
        )
        if (loading && artists.isEmpty()) {
            EmptyPane("加载中…")
            return@Column
        }
        if (artists.isEmpty()) {
            EmptyPane("还没有艺术家")
            return@Column
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(artists, key = { it.id }) { artist ->
                ArtistRow(
                    name = artist.name,
                    subtitle = "${artist.songCount} 首",
                    onClick = { onArtist(artist) }
                )
            }
        }
    }
}

@Composable
fun PlaylistsList(
    playlists: List<Playlist>,
    loading: Boolean,
    onPlaylist: (Playlist) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxSize()) {
        Text(
            text = "歌单",
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
            color = OrzColors.Mint,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold
        )
        if (loading && playlists.isEmpty()) {
            EmptyPane("加载中…")
            return@Column
        }
        if (playlists.isEmpty()) {
            EmptyPane("还没有歌单(可在网页端创建)")
            return@Column
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(playlists, key = { it.id }) { playlist ->
                ArtistRow(
                    name = playlist.name,
                    subtitle = playlist.description?.takeIf { it.isNotBlank() }
                        ?: "歌单 · ${playlist.songCount ?: 0} 首",
                    onClick = { onPlaylist(playlist) }
                )
            }
        }
    }
}

@Composable
fun SongListPane(
    title: String,
    subtitle: String?,
    songs: List<Song>,
    loading: Boolean,
    onBack: () -> Unit,
    onSong: (Song, List<Song>) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Button(onClick = onBack) { Text("返回") }
            Column {
                Text(
                    text = title,
                    color = OrzColors.Text,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = subtitle ?: "${songs.size} 首",
                    color = OrzColors.Muted,
                    fontSize = 12.sp
                )
            }
        }

        if (loading && songs.isEmpty()) {
            EmptyPane("加载中…")
            return@Column
        }
        if (songs.isEmpty()) {
            EmptyPane("这里是空的")
            return@Column
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(songs, key = { it.id }) { song ->
                SongRow(song = song, onClick = { onSong(song, songs) })
            }
        }
    }
}

@Composable
fun SearchContent(
    query: String,
    results: List<Song>,
    loading: Boolean,
    onQuery: (String) -> Unit,
    onSong: (Song, List<Song>) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxSize()) {
        Text(
            text = "搜索",
            modifier = Modifier.padding(horizontal = 20.dp).padding(top = 12.dp),
            color = OrzColors.Mint,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold
        )
        SearchField(
            value = query,
            placeholder = "歌曲名 / 艺术家",
            onValueChange = onQuery,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)
        )
        when {
            loading && results.isEmpty() -> EmptyPane("搜索中…")
            query.isBlank() -> EmptyPane("输入关键词开始搜索")
            results.isEmpty() -> EmptyPane("没有匹配的结果")
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                items(results, key = { it.id }) { song ->
                    SongRow(song = song, onClick = { onSong(song, results) })
                }
            }
        }
    }
}

@Composable
fun SettingsContent(
    serverUrl: String,
    notice: String?,
    version: String,
    onSave: (String) -> Unit,
    onCheck: () -> Unit,
    modifier: Modifier = Modifier
) {
    val draft = androidx.compose.runtime.remember(serverUrl) {
        androidx.compose.runtime.mutableStateOf(serverUrl)
    }
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text(
            text = "设置",
            color = OrzColors.Mint,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = "服务器地址(自建实例填你自己的)" ,
            color = OrzColors.Muted,
            fontSize = 12.sp
        )
        SearchField(
            value = draft.value,
            placeholder = "https://music.jokerhub.cn",
            onValueChange = { draft.value = it }
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(onClick = { onSave(draft.value) }) { Text("保存并重载") }
            Button(onClick = onCheck) { Text("测试连接") }
        }
        notice?.let {
            Text(
                text = it,
                color = OrzColors.Mint,
                fontSize = 12.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(OrzColors.SurfaceHigh, RoundedCornerShape(10.dp))
                    .padding(12.dp)
            )
        }
        Text(
            text = "OrzMusic Android 客户端 v$version · 数据来自 OrzGeeker/OrzMusic 的 HTTP API",
            color = OrzColors.Muted,
            fontSize = 11.sp
        )
    }
}

@Composable
private fun SearchField(
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = true,
        textStyle = TextStyle(color = OrzColors.Text, fontSize = 15.sp),
        cursorBrush = SolidColor(OrzColors.Mint),
        modifier = modifier.fillMaxWidth(),
        decorationBox = { inner ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(OrzColors.SurfaceHigh, RoundedCornerShape(12.dp))
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                androidx.compose.foundation.layout.Box(modifier = Modifier.weight(1f)) {
                    if (value.isBlank()) {
                        Text(placeholder, color = OrzColors.Muted, fontSize = 14.sp)
                    }
                    inner()
                }
            }
        }
    )
}
