package com.jokerhub.orzmusic.core.playback

/**
 * 平台播放器抽象。
 *
 * Android:Media3/ExoPlayer(WAV / mp3 / ogg / 服务端 WAV)
 * Apple:AVAudioEngine / AVPlayer
 * Web:`<audio>` / AudioWorklet
 *
 * 播放器**不拥有队列,也不决定策略** —— 那两层在 PlaybackQueue / PlaybackPolicy。
 */
sealed interface AudioSource {
    data class Remote(val url: String) : AudioSource
    data class Local(val path: String) : AudioSource
}

interface OrzAudioPlayer {
    var onPlayingChanged: ((Boolean) -> Unit)?
    var onEnded: (() -> Unit)?
    var onError: ((String) -> Unit)?

    val isPlaying: Boolean
    val positionMs: Long
    val durationMs: Long

    fun play(source: AudioSource)
    fun toggle()
    fun pause()
    fun stop()
    fun seekTo(positionMs: Long)
    fun release()
}
