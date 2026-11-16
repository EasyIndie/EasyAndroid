package com.jokerhub.orzmusic.android.ui

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.jokerhub.orzmusic.android.data.ApiFactory
import com.jokerhub.orzmusic.core.model.Artist
import com.jokerhub.orzmusic.android.data.DEFAULT_SERVER_URL
import com.jokerhub.orzmusic.core.model.FormatCount
import com.jokerhub.orzmusic.android.data.MusicRepository
import com.jokerhub.orzmusic.core.model.Playlist
import com.jokerhub.orzmusic.core.model.Song
import com.jokerhub.orzmusic.core.model.Stats
import com.jokerhub.orzmusic.core.playback.AudioSource
import com.jokerhub.orzmusic.core.playback.DecoderManifest
import com.jokerhub.orzmusic.core.playback.PlaybackPolicy
import com.jokerhub.orzmusic.core.playback.PlaybackQueue
import com.jokerhub.orzmusic.core.playback.PlaybackRoute
import com.jokerhub.orzmusic.android.player.MediaCache
import com.jokerhub.orzmusic.android.player.PlaybackController
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class Tab(val label: String) {
    Library("曲库"),
    Artists("艺术家"),
    Playlists("歌单"),
    Search("搜索"),
    Settings("设置")
}

data class UiState(
    val tab: Tab = Tab.Library,

    // 服务器
    val serverUrl: String = DEFAULT_SERVER_URL,

    // 曲库
    val stats: Stats? = null,
    val formats: List<FormatCount> = emptyList(),
    val selectedFormat: String? = null,
    val songs: List<Song> = emptyList(),
    val songPage: Int = 1,
    val songTotal: Int = 0,

    // 艺术家 / 歌单
    val artists: List<Artist> = emptyList(),
    val playlists: List<Playlist> = emptyList(),
    val detailTitle: String? = null,
    val detailSubtitle: String? = null,
    val detailSongs: List<Song> = emptyList(),

    // 搜索
    val searchQuery: String = "",
    val searchResults: List<Song> = emptyList(),

    // 播放
    val current: Song? = null,
    val queue: List<Song> = emptyList(),
    val isPlaying: Boolean = false,
    val decoding: Boolean = false,
    val showNowPlaying: Boolean = false,

    // 通用
    val loading: Boolean = false,
    val error: String? = null,
    val notice: String? = null
)

class AppViewModel(app: Application) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val repository = MusicRepository(
        prefs.getString(KEY_SERVER, DEFAULT_SERVER_URL) ?: DEFAULT_SERVER_URL
    )
    private val playback = PlaybackController(app)
    private val mediaCache = MediaCache(app)
    private val playbackQueue = PlaybackQueue()

    private val _state = MutableStateFlow(UiState(serverUrl = repository.baseUrl))
    val state: StateFlow<UiState> = _state.asStateFlow()

    private var searchJob: Job? = null
    private var playJob: Job? = null

    init {
        playback.onPlayingChanged = { playing ->
            _state.update { it.copy(isPlaying = playing) }
        }
        playback.onEnded = { playNext() }
        playback.onError = { message ->
            _state.update { it.copy(isPlaying = false, error = message) }
        }
        reloadHome()
    }

    // ── 曲库 ──────────────────────────────────────────────────────
    private fun reloadHome() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching {
                withContext(Dispatchers.IO) {
                    coroutineScope {
                        val stats = async { repository.stats() }
                        val formats = async { repository.formats() }
                        val page = async {
                            repository.songs(1, PAGE_SIZE, _state.value.selectedFormat)
                        }
                        Triple(stats.await(), formats.await(), page.await())
                    }
                }
            }.onSuccess { (stats, formats, page) ->
                _state.update {
                    it.copy(
                        loading = false,
                        error = null,
                        stats = stats,
                        formats = formats.formats,
                        songs = page.items,
                        songPage = 1,
                        songTotal = page.metadata.total
                    )
                }
            }.onFailure { e ->
                _state.update {
                    it.copy(loading = false, error = "加载失败:${e.message ?: e.javaClass.simpleName}")
                }
            }
        }
    }

    fun selectFormat(format: String?) {
        if (_state.value.selectedFormat == format) return
        _state.update { it.copy(selectedFormat = format, songs = emptyList(), songPage = 1, loading = true) }
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    repository.songs(1, PAGE_SIZE, format)
                }
            }.onSuccess { page ->
                _state.update {
                    it.copy(
                        loading = false,
                        songs = page.items,
                        songPage = 1,
                        songTotal = page.metadata.total
                    )
                }
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = "加载失败:${e.message}") }
            }
        }
    }

    fun loadMoreSongs() {
        val s = _state.value
        if (s.loading || s.songs.size >= s.songTotal) return
        val next = s.songPage + 1
        _state.update { it.copy(loading = true) }
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    repository.songs(next, PAGE_SIZE, s.selectedFormat)
                }
            }.onSuccess { page ->
                _state.update {
                    it.copy(
                        loading = false,
                        songs = it.songs + page.items,
                        songPage = next,
                        songTotal = page.metadata.total
                    )
                }
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = "加载失败:${e.message}") }
            }
        }
    }

    // ── 艺术家 / 歌单 ─────────────────────────────────────────────
    private fun loadArtists() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true) }
            runCatching {
                withContext(Dispatchers.IO) { repository.artists(1, 100) }
            }.onSuccess { page ->
                _state.update { it.copy(loading = false, artists = page.items) }
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = "加载艺术家失败:${e.message}") }
            }
        }
    }

    private fun loadPlaylists() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true) }
            runCatching {
                withContext(Dispatchers.IO) { repository.playlists() }
            }.onSuccess { list ->
                _state.update { it.copy(loading = false, playlists = list) }
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = "加载歌单失败:${e.message}") }
            }
        }
    }

    fun openArtist(artist: Artist) {
        _state.update {
            it.copy(
                detailTitle = artist.name,
                detailSubtitle = "艺术家 · ${artist.songCount} 首",
                detailSongs = emptyList(),
                loading = true
            )
        }
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) { repository.artistSongs(artist.id, 1, 100) }
            }.onSuccess { page ->
                _state.update { it.copy(loading = false, detailSongs = page.items) }
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = "加载失败:${e.message}") }
            }
        }
    }

    fun openPlaylist(playlist: Playlist) {
        _state.update {
            it.copy(
                detailTitle = playlist.name,
                detailSubtitle = playlist.description?.takeIf { d -> d.isNotBlank() }
                    ?: "歌单 · ${playlist.songCount ?: 0} 首",
                detailSongs = emptyList(),
                loading = true
            )
        }
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) { repository.playlist(playlist.id) }
            }.onSuccess { detail ->
                _state.update {
                    it.copy(loading = false, detailSongs = detail.songs.orEmpty())
                }
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = "加载失败:${e.message}") }
            }
        }
    }

    fun closeDetail() {
        _state.update { it.copy(detailTitle = null, detailSubtitle = null, detailSongs = emptyList()) }
    }

    // ── 搜索 ──────────────────────────────────────────────────────
    fun search(query: String) {
        _state.update { it.copy(searchQuery = query) }
        searchJob?.cancel()
        if (query.isBlank()) {
            _state.update { it.copy(searchResults = emptyList(), loading = false) }
            return
        }
        searchJob = viewModelScope.launch {
            delay(300) // 输入防抖
            _state.update { it.copy(loading = true) }
            runCatching {
                withContext(Dispatchers.IO) {
                    repository.search(query, _state.value.selectedFormat)
                }
            }.onSuccess { results ->
                _state.update { it.copy(loading = false, searchResults = results) }
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = "搜索失败:${e.message}") }
            }
        }
    }

    // ── 导航 ──────────────────────────────────────────────────────
    fun selectTab(tab: Tab) {
        _state.update {
            it.copy(
                tab = tab,
                detailTitle = null,
                detailSubtitle = null,
                detailSongs = emptyList(),
                showNowPlaying = false
            )
        }
        when (tab) {
            Tab.Artists -> if (_state.value.artists.isEmpty()) loadArtists()
            Tab.Playlists -> loadPlaylists()
            else -> Unit
        }
    }

    // ── 播放 ──────────────────────────────────────────────────────
    fun play(song: Song, list: List<Song>) {
        playJob?.cancel()
        playbackQueue.setFrom(list, song)
        startSong(song)
    }

    /** 与 Web 端 `OrzAudioPlayer.play(song)` 同层:决定走 direct/server/native。 */
    private fun startSong(song: Song) {
        when (val route = PlaybackPolicy.route(song, repository, DecoderManifest)) {
            is PlaybackRoute.Remote -> {
                playback.play(AudioSource.Remote(route.url))
                _state.update {
                    it.copy(
                        current = song,
                        queue = playbackQueue.items,
                        showNowPlaying = true,
                        decoding = false,
                        error = null,
                        notice = null
                    )
                }
            }

            is PlaybackRoute.Native -> startNative(song, route.rawUrl)
            is PlaybackRoute.Unsupported -> showUnsupported(song, route.format)
        }
    }

    private fun showUnsupported(song: Song, format: String) {
        _state.update {
            it.copy(
                current = song,
                queue = playbackQueue.items,
                isPlaying = false,
                showNowPlaying = true,
                decoding = false,
                error = null,
                notice = "「${format.uppercase()}」没有编进原生解码器" +
                    "(当前支持 ${DecoderManifest.formats.joinToString("/") { it.id }})。" +
                    "可以先在网页播放器里播放。"
            )
        }
    }

    /** wasmDecode 曲目:下载 raw → OrzAudioCore 解成 WAV → 平台播放器播放。 */
    private fun startNative(song: Song, rawUrl: String) {
        _state.update {
            it.copy(
                current = song,
                queue = playbackQueue.items,
                isPlaying = false,
                showNowPlaying = true,
                decoding = true,
                error = null,
                notice = "正在解码 ${song.fileFormat.uppercase()}…"
            )
        }

        playJob = viewModelScope.launch {
            try {
                val wav = mediaCache.wavFor(song, rawUrl)
                if (_state.value.current?.id != song.id) return@launch
                playback.play(AudioSource.Local(wav.absolutePath))
                _state.update { it.copy(decoding = false, notice = null) }
            } catch (c: CancellationException) {
                throw c
            } catch (e: Exception) {
                if (_state.value.current?.id == song.id) {
                    _state.update {
                        it.copy(
                            decoding = false,
                            error = "解码失败:${e.message ?: e.javaClass.simpleName}"
                        )
                    }
                }
            }
        }
    }

    fun togglePlay() {
        val s = _state.value
        if (s.current == null || s.decoding) return
        playback.toggle()
    }

    fun playNext() {
        val next = playbackQueue.next()
        if (next == null) {
            playback.stop()
            _state.update { it.copy(isPlaying = false) }
            return
        }
        startSong(next)
    }

    fun playPrevious() {
        val previous = playbackQueue.previous() ?: return
        startSong(previous)
    }

    fun openNowPlaying() {
        if (_state.value.current != null) _state.update { it.copy(showNowPlaying = true) }
    }

    fun closeNowPlaying() {
        _state.update { it.copy(showNowPlaying = false) }
    }

    fun clearNotice() {
        _state.update { it.copy(notice = null) }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }

    val playbackPositionMs: Long get() = playback.positionMs
    val playbackDurationMs: Long get() = playback.durationMs

    fun seekTo(positionMs: Long) = playback.seekTo(positionMs)

    // ── 设置 ──────────────────────────────────────────────────────
    fun updateServerUrl(raw: String) {
        val normalized = ApiFactory.normalizeBaseUrl(raw)
        repository.updateBaseUrl(normalized)
        prefs.edit().putString(KEY_SERVER, normalized).apply()
        playJob?.cancel()
        playback.stop()
        playbackQueue.clear()
        _state.update {
            it.copy(
                serverUrl = normalized,
                stats = null,
                formats = emptyList(),
                songs = emptyList(),
                songPage = 1,
                songTotal = 0,
                artists = emptyList(),
                playlists = emptyList(),
                detailTitle = null,
                detailSongs = emptyList(),
                current = null,
                queue = emptyList(),
                isPlaying = false,
                decoding = false,
                showNowPlaying = false,
                error = null,
                notice = "已切换到 $normalized"
            )
        }
        reloadHome()
    }

    fun checkServer() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching {
                withContext(Dispatchers.IO) { repository.health() }
            }.onSuccess { health ->
                _state.update {
                    it.copy(
                        loading = false,
                        notice = "服务器 ${health.status} · v${health.version} · " +
                            "DB ${health.database} · CAS ${health.cas}"
                    )
                }
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = "连接失败:${e.message}") }
            }
        }
    }

    override fun onCleared() {
        playJob?.cancel()
        playback.release()
        super.onCleared()
    }

    companion object {
        private const val PREFS = "orzmusic"
        private const val KEY_SERVER = "server_url"
        private const val PAGE_SIZE = 50
    }
}
