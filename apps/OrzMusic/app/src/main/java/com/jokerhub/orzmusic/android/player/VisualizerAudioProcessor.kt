package com.jokerhub.orzmusic.android.player

import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

/**
 * 在解码器输出 PCM 后、AudioTrack 写入前取一份数据，计算柱状电平。
 *
 * 不申请 RECORD_AUDIO：数据来自本应用自己的播放管线。
 * 只支持 PCM16 / float；其他编码直接透传（不画声场）。
 */
class VisualizerAudioProcessor : BaseAudioProcessor() {

    private var channels = 2
    private var encoding = C.ENCODING_INVALID
    private var sampleBytes = 2
    private var lastPublishMs = 0L
    private var smoothed = FloatArray(VisualizerBus.BAR_COUNT)

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        channels = inputAudioFormat.channelCount.coerceAtLeast(1)
        encoding = inputAudioFormat.encoding
        sampleBytes = when (encoding) {
            C.ENCODING_PCM_16BIT -> 2
            C.ENCODING_PCM_FLOAT -> 4
            else -> 0
        }
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val size = inputBuffer.remaining()
        if (size <= 0) return

        // 先复制一份给分析线程用，再把原 buffer 原样透传给 AudioSink。
        val copy = ByteArray(size)
        inputBuffer.duplicate().get(copy)
        val output = replaceOutputBuffer(size)
        output.put(copy)
        output.flip()

        if (sampleBytes > 0) analyze(copy)
    }

    private fun analyze(bytes: ByteArray) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastPublishMs < 32L) return
        lastPublishMs = now

        val frameSamples = when (encoding) {
            C.ENCODING_PCM_16BIT -> {
                val shorts = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                val frames = shorts.remaining() / channels
                if (frames <= 0) return
                FloatArray(shorts.remaining()) { shorts.get(it) / 32768f }
            }
            C.ENCODING_PCM_FLOAT -> {
                val floats = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
                val frames = floats.remaining() / channels
                if (frames <= 0) return
                FloatArray(floats.remaining()) { floats.get(it) }
            }
            else -> return
        }

        val frames = frameSamples.size / channels
        if (frames <= 0) return
        val bars = VisualizerBus.BAR_COUNT
        val next = FloatArray(bars)
        for (bar in 0 until bars) {
            val startFrame = bar * frames / bars
            val endFrame = ((bar + 1) * frames / bars).coerceAtLeast(startFrame + 1)
            var sum = 0.0
            var count = 0
            var frame = startFrame
            while (frame < endFrame && frame < frames) {
                var channel = 0
                while (channel < channels) {
                    val v = frameSamples[frame * channels + channel]
                    sum += (v * v).toDouble()
                    count++
                    channel++
                }
                frame++
            }
            val rms = if (count > 0) sqrt(sum / count).toFloat() else 0f
            // PCM 的 RMS 通常很小；放大后给 UI，再做一点指数平滑。
            val level = (rms * 4.2f).coerceIn(0f, 1f)
            next[bar] = (smoothed[bar] * 0.55f + level * 0.45f).coerceIn(0f, 1f)
        }
        smoothed = next
        VisualizerBus.publish(next.copyOf())
    }

    override fun onFlush() {
        // 切歌 / seek 时旧电平不要残留太久。
        smoothed = FloatArray(smoothed.size)
        VisualizerBus.reset()
    }

    override fun onReset() {
        smoothed = FloatArray(smoothed.size)
        VisualizerBus.reset()
    }
}
