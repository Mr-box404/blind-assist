// android/app/src/main/kotlin/com/blindassist/blind_assist/MainActivity.kt
// Flutter 应用入口 + 连续音频流引擎
//
// 音频引擎使用 Android AudioTrack API 维持一个持续播放的音流，
// 通过 MethodChannel 接收来自 Dart 层的实时参数更新（频率、音量、声道平衡）。
// 扫描线每移动一步（~20ms），Dart 层就会发送新的音频参数，
// 音频线程在下一个 PCM 数据块中立即使用新参数。
// 这实现了类似雷达/声呐的连续扫描音效。

package com.blindassist.blind_assist

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/// Flutter 主 Activity
///
/// 注册名为 "blind_assist/audio" 的 MethodChannel。
/// 使用 Android 原生 AudioTrack API 维持一个持久化音频流，
/// 支持在播放过程中实时更新频率、音量和立体声平衡参数。
class MainActivity : FlutterActivity() {
    companion object {
        /// MethodChannel 名称
        private const val CHANNEL = "blind_assist/audio"
    }

    /// 持久化音频轨道实例
    private var audioTrack: AudioTrack? = null

    /// 播放标志
    @Volatile
    private var isPlaying = false

    /// 音频播放线程（持续运行，不断生成 PCM 数据）
    private var playThread: Thread? = null

    // ==================== 实时音频参数（由 Flutter 端更新） ====================

    /// 当前频率（Hz）
    @Volatile
    private var currentFrequency = 220.0

    /// 当前音量（0.0-1.0）
    @Volatile
    private var currentVolume = 0.0

    /// 当前立体声平衡（0.0=全左, 0.5=居中, 1.0=全右）
    @Volatile
    private var currentPan = 0.5

    /// 配置 Flutter 引擎
    ///
    /// 注册 MethodChannel，处理以下指令：
    ///   - startContinuousAudio: 启动持久化音频流
    ///   - updateAudio(frequency, volume, pan): 实时更新音频参数
    ///   - stopAudio: 停止音频流
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startContinuousAudio" -> {
                    startContinuousAudio()
                    result.success(null)
                }
                "updateAudio" -> {
                    // 实时更新音频参数（由 Flutter 端每 ~20ms 调用一次）
                    currentFrequency = (call.argument<Number>("frequency")?.toDouble()
                        ?: 220.0).coerceIn(20.0, 5000.0)
                    currentVolume = (call.argument<Number>("volume")?.toDouble()
                        ?: 0.0).coerceIn(0.0, 1.0)
                    currentPan = (call.argument<Number>("pan")?.toDouble()
                        ?: 0.5).coerceIn(0.0, 1.0)
                    result.success(null)
                }
                "stopAudio" -> {
                    stopAudio()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// 启动持久化音频流
    ///
    /// 创建一个持续运行的 AudioTrack 和后台线程。
    /// 线程不断循环，每次读取当前音频参数生成一段 PCM 数据并写入 AudioTrack。
    /// 参数由 Flutter 端通过 updateAudio 实时更新。
    ///
    /// 与之前"每次播放一个短促提示音"不同，此模式维持一个不间断的音流，
    /// 参数可以每 20ms 更新一次，实现连续扫描的音效。
    @Suppress("DEPRECATION")
    private fun startContinuousAudio() {
        // 如果已经在播放，无需重复启动
        if (isPlaying) return
        isPlaying = true

        val sampleRate = 22050

        playThread = Thread {
            try {
                // 获取最小缓冲区大小
                val minBufferSize = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_STEREO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                val bufferSize = minBufferSize.coerceAtLeast(4096)

                // 创建 AudioTrack
                audioTrack = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    AudioTrack.Builder()
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                        .setAudioFormat(
                            AudioFormat.Builder()
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .setSampleRate(sampleRate)
                                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                                .build()
                        )
                        .setBufferSizeInBytes(bufferSize)
                        .setTransferMode(AudioTrack.MODE_STREAM)
                        .build()
                } else {
                    AudioTrack(
                        AudioManager.STREAM_MUSIC,
                        sampleRate,
                        AudioFormat.CHANNEL_OUT_STEREO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        bufferSize,
                        AudioTrack.MODE_STREAM
                    )
                }

                audioTrack?.play()

                val chunkSize = 2048  // 每块约 93ms 的 PCM 数据
                var phase = 0.0

                // 持续生成并写入 PCM 数据
                while (isPlaying) {
                    // 读取当前的音频参数（这些参数由 Flutter 端实时更新）
                    val freq = currentFrequency
                    val vol = currentVolume
                    val pan = currentPan

                    // 计算立体声增益
                    val angle = (pan * PI / 2.0).toFloat()
                    val leftGain = cos(angle) * vol
                    val rightGain = sin(angle) * vol

                    // 如果音量为 0，写入静音数据
                    if (vol < 0.001) {
                        val silence = ShortArray(chunkSize * 2)
                        audioTrack?.write(silence, 0, silence.size)
                        phase = 0.0
                        continue
                    }

                    // 生成一个数据块的正弦波 PCM 数据
                    val phaseIncrement = 2.0 * PI * freq / sampleRate
                    val stereoBuffer = ShortArray(chunkSize * 2)

                    for (i in 0 until chunkSize) {
                        val sample = (sin(phase) * Short.MAX_VALUE).toInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort()

                        stereoBuffer[i * 2] = (sample * leftGain).toInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort()
                        stereoBuffer[i * 2 + 1] = (sample * rightGain).toInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort()

                        phase += phaseIncrement
                        if (phase >= 2.0 * PI) phase -= 2.0 * PI
                    }

                    // 写入 AudioTrack
                    audioTrack?.write(stereoBuffer, 0, stereoBuffer.size)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                cleanup()
            }
        }
        playThread?.start()
    }

    /// 停止音频
    private fun stopAudio() {
        isPlaying = false
        playThread?.join(300)
        cleanup()
    }

    /// 释放 AudioTrack 资源
    private fun cleanup() {
        try { audioTrack?.stop() } catch (_: Exception) {}
        try { audioTrack?.release() } catch (_: Exception) {}
        audioTrack = null
    }

    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }
}
