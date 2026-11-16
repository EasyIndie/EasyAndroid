package com.jokerhub.orzmusic.android.player

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.jokerhub.orzmusic.core.playback.AudioSource
import com.jokerhub.orzmusic.core.playback.OrzAudioPlayer
import java.io.File

/**
 * [OrzAudioPlayer] 的 Android 实现 —— Media3 / ExoPlayer。
 *
 * 能放:
 *   · `directFile`:mp3 / ogg / flac / m4a / aac / PCM WAV
 *   · `serverDecode`:服务端已经转成 PCM WAV
 *   · `wasmDecode` 经 OrzAudioCore 解出来的本地 WAV
 *
 * 不负责:队列、策略、下载、解码。那些在 core(PlaybackQueue/PlaybackPolicy)
 * 和应用层(MediaCache/NativeDecoder)里。
 */
class PlaybackController(context: Context) : OrzAudioPlayer {

    private val player: ExoPlayer = ExoPlayer.Builder(context).build()

    override var onPlayingChanged: ((Boolean) -> Unit)? = null
    override var onEnded: (() -> Unit)? = null
    override var onError: ((String) -> Unit)? = null

    init {
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                onPlayingChanged?.invoke(isPlaying)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) onEnded?.invoke()
            }

            override fun onPlayerError(error: PlaybackException) {
                onError?.invoke(error.errorCodeName + ": " + (error.message ?: "播放失败"))
            }
        })
    }

    override val isPlaying: Boolean get() = player.isPlaying
    override val positionMs: Long get() = player.currentPosition.coerceAtLeast(0L)
    override val durationMs: Long get() = player.duration.coerceAtLeast(0L)

    override fun play(source: AudioSource) {
        val url = when (source) {
            is AudioSource.Remote -> source.url
            is AudioSource.Local -> Uri.fromFile(File(source.path)).toString()
        }
        playUri(url)
    }

    private fun playUri(url: String) {
        player.stop()
        player.clearMediaItems()
        player.setMediaItem(MediaItem.fromUri(url))
        player.prepare()
        player.playWhenReady = true
    }

    override fun toggle() {
        if (player.isPlaying) player.pause() else player.play()
    }

    override fun pause() = player.pause()

    override fun stop() {
        player.stop()
        player.clearMediaItems()
    }

    override fun seekTo(positionMs: Long) {
        player.seekTo(positionMs)
    }

    override fun release() {
        player.release()
    }
}
