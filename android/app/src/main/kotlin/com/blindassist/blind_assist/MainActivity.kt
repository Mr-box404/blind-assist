// android/app/src/main/kotlin/com/blindassist/blind_assist/MainActivity.kt
// Flutter 应用入口 Activity + 原生音频引擎
//
// 音频引擎使用 Android AudioTrack API 生成并播放立体声，
// 通过 MethodChannel 接收来自 Dart 层的音频参数（频率、音量、声道平衡）。
// 这实现了盲人辅助导航核心功能：将深度图扫描结果映射为双耳立体声。

package com.blindassist.blind_assist

import android.media.AudioAttributes
import android.media.AudioFormat
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
/// 继承自 FlutterActivity，注册了名为 "blind_assist/audio" 的 MethodChannel，
/// 用于接收来自 Dart 层的音频播放指令。
/// 使用 Android 原生 AudioTrack API 实时生成 PCM 音频数据，
/// 支持频率、音量和立体声平衡控制。
class MainActivity : FlutterActivity() {
    companion object {
        /// MethodChannel 名称，需与 Dart 层保持一致
        private const val CHANNEL = "blind_assist/audio"
    }

    /// 当前音频轨道实例
    private var audioTrack: AudioTrack? = null

    /// 播放状态标志
    @Volatile
    private var isPlaying = false

    /// 音频播放线程
    private var playThread: Thread? = null

    /// 配置 Flutter 引擎
    ///
    /// 注册 MethodChannel 处理器，处理来自 Dart 层的音频指令：
    ///   - playBeep(frequency, volume, pan): 播放指定参数的短促提示音
    ///   - stopAudio(): 停止当前播放
    ///
    /// [flutterEngine] Flutter 引擎实例
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playBeep" -> {
                    // 解析音频参数
                    val frequency = (call.argument<Number>("frequency")?.toInt()) ?: 440
                    val volume = (call.argument<Number>("volume")?.toDouble()
                        ?: 0.5).coerceIn(0.0, 1.0)
                    val pan = (call.argument<Number>("pan")?.toDouble()
                        ?: 0.5).coerceIn(0.0, 1.0)

                    // 在后台线程播放音频
                    playBeep(frequency, volume.toFloat(), pan.toFloat())
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

    /// 播放提示音（支持立体声平衡）
    ///
    /// 使用 AudioTrack 在后台线程生成并播放正弦波 PCM 音频。
    /// 支持以下参数控制：
    ///   - frequency: 频率（Hz），控制音调高低
    ///   - volume: 音量（0.0-1.0），控制响度
    ///   - pan: 立体声平衡（0.0=全左, 0.5=居中, 1.0=全右）
    ///
    /// 播放时长约 180ms，带有淡入淡出包络使声音更自然。
    ///
    /// [frequency] 频率（Hz）
    /// [volume] 音量（0.0-1.0）
    /// [pan] 立体声平衡（0.0-1.0）
    @Suppress("DEPRECATION")
    private fun playBeep(frequency: Int, volume: Float, pan: Float) {
        // 停止前一个提示音
        stopAudio()
        isPlaying = true

        // 音频参数
        val sampleRate = 22050       // 采样率 22.05kHz
        val durationMs = 180          // 播放时长 180ms
        val totalSamples = sampleRate * durationMs / 1000

        // 计算立体声增益（等功率 panning 曲线）
        // pan=0.0 → 左声道全开，右声道静音
        // pan=0.5 → 左右均衡
        // pan=1.0 → 左声道静音，右声道全开
        val angle = pan * PI.toFloat() / 2f
        val leftGain = cos(angle) * volume
        val rightGain = sin(angle) * volume

        playThread = Thread {
            try {
                // 获取最小缓冲区大小
                val minBufferSize = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_STEREO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                val bufferSize = minBufferSize.coerceAtLeast(2048)

                // 创建 AudioTrack 实例
                // API 26+ 使用 Builder，否则使用传统构造函数
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
                    // 兼容 API 21-25 的传统构造函数
                    AudioTrack(
                        AudioTrack.STREAM_MUSIC,
                        sampleRate,
                        AudioFormat.CHANNEL_OUT_STEREO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        bufferSize,
                        AudioTrack.MODE_STREAM
                    )
                }

                // 开始播放
                audioTrack?.play()

                val chunkSize = 1024
                var samplesGenerated = 0
                var phase = 0.0
                val phaseIncrement = 2.0 * PI * frequency / sampleRate

                // 淡入淡出包络参数
                val attackSamples = (sampleRate * 0.02).toInt()   // 20ms 淡入
                val releaseSamples = (sampleRate * 0.02).toInt()  // 20ms 淡出

                // 生成并写入 PCM 数据块
                while (isPlaying && samplesGenerated < totalSamples) {
                    val remaining = totalSamples - samplesGenerated
                    val currentChunk = minOf(chunkSize, remaining)
                    val stereoBuffer = ShortArray(currentChunk * 2)

                    for (i in 0 until currentChunk) {
                        val globalIndex = samplesGenerated + i

                        // 计算包络值（淡入淡出避免咔嗒声）
                        val envelope = when {
                            globalIndex < attackSamples -> {
                                globalIndex.toFloat() / attackSamples
                            }
                            globalIndex >= totalSamples - releaseSamples -> {
                                (totalSamples - globalIndex).toFloat() / releaseSamples
                            }
                            else -> 1.0f
                        }

                        // 生成正弦波采样值
                        val rawSample = (sin(phase) * Short.MAX_VALUE * envelope).toInt()
                        val sampleValue = rawSample.coerceIn(
                            Short.MIN_VALUE.toInt(),
                            Short.MAX_VALUE.toInt()
                        ).toShort()

                        // 写入左右声道（应用立体声平衡）
                        stereoBuffer[i * 2] = (sampleValue * leftGain).toInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort()
                        stereoBuffer[i * 2 + 1] = (sampleValue * rightGain).toInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort()

                        // 推进相位
                        phase += phaseIncrement
                        if (phase >= 2.0 * PI) phase -= 2.0 * PI
                    }

                    // 将 PCM 数据写入 AudioTrack
                    audioTrack?.write(stereoBuffer, 0, stereoBuffer.size)
                    samplesGenerated += currentChunk
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                // 清理资源
                cleanup()
            }
        }
        playThread?.start()
    }

    /// 停止音频播放
    ///
    /// 设置停止标志并等待播放线程结束。
    /// 线程结束时会自动释放 AudioTrack 资源。
    private fun stopAudio() {
        isPlaying = false
        playThread?.join(100)
        cleanup()
    }

    /// 释放 AudioTrack 资源
    ///
    /// 停止播放并释放底层音频资源。
    /// 被 stopAudio() 和播放线程的 finally 块调用。
    private fun cleanup() {
        try {
            audioTrack?.stop()
        } catch (_: Exception) {}
        try {
            audioTrack?.release()
        } catch (_: Exception) {}
        audioTrack = null
    }

    /// Activity 销毁时释放资源
    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }
}
