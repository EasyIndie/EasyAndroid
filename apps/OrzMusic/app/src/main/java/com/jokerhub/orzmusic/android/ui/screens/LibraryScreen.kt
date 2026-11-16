package com.jokerhub.orzmusic.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Button
import androidx.tv.material3.Text
import com.jokerhub.orzmusic.core.model.Song
import com.jokerhub.orzmusic.android.ui.EmptyPane
import com.jokerhub.orzmusic.android.ui.FormatChip
import com.jokerhub.orzmusic.android.ui.OrzColors
import com.jokerhub.orzmusic.android.ui.SongRow

/**
 * 曲库首页 —— 统计 + 格式筛选 + 歌曲分页列表。
 *
 * 刻意做成无状态的:截图测试可以直接喂 [com.jokerhub.orzmusic.android.ui.UiState],
 * 不需要网络、不需要 ViewModel。
 */
@Composable
fun LibraryContent(
    songs: List<Song>,
    formats: List<com.jokerhub.orzmusic.core.model.FormatCount>,
    selectedFormat: String?,
    totalSongs: Int,
    totalArtists: Int,
    loading: Boolean,
    onFormat: (String?) -> Unit,
    onSong: (Song, List<Song>) -> Unit,
    onLoadMore: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxSize()) {
        Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
            Text(
                text = "曲库",
                color = OrzColors.Mint,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "$totalSongs 首 · $totalArtists 位艺术家 · ${formats.size} 种格式",
                color = OrzColors.Muted,
                fontSize = 12.sp
            )
        }

        LazyRow(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                FormatChip(
                    label = "全部",
                    count = totalSongs.takeIf { it > 0 },
                    selected = selectedFormat == null,
                    onClick = { onFormat(null) }
                )
            }
            items(formats, key = { it.format }) { item ->
                FormatChip(
                    label = item.format,
                    count = item.count,
                    selected = selectedFormat == item.format,
                    onClick = { onFormat(item.format) }
                )
            }
        }

        if (loading && songs.isEmpty()) {
            EmptyPane("加载中…", modifier = Modifier.padding(top = 32.dp))
            return@Column
        }
        if (songs.isEmpty()) {
            EmptyPane("这个筛选下还没有曲目", modifier = Modifier.padding(top = 32.dp))
            return@Column
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(top = 10.dp),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(songs, key = { it.id }) { song ->
                SongRow(song = song, onClick = { onSong(song, songs) })
            }
            if (songs.size < totalSongs) {
                item {
                    Button(
                        onClick = onLoadMore,
                        modifier = Modifier.padding(top = 8.dp)
                    ) {
                        Text(if (loading) "加载中…" else "加载更多(${songs.size}/$totalSongs)")
                    }
                }
            }
        }
    }
}
