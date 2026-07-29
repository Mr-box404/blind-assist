// android/app/src/main/kotlin/com/blindassist/blind_assist/MainActivity.kt
// Flutter 应用入口 + 8声源立体声音频引擎
//
// 核心设计：维持一个持久化的 AudioTrack，同时混合8个独立声源。
// 每个声源有独立的频率、音量和声道平衡(pan)。
// 8个声源对应画面的8个水平区域，从左到右排列。
// 所有声源同时播放，混合成立体声输出。
//
// 这样盲人可以同时听到所有方位的声音：
//   - 左耳听到左侧区域的物体
//   - 右耳听到右侧区域的物体
//   - 音调反映距离（近=高音，远=低音）
//   - 音量反映 proximity（近=大声，远=小声）
// 类似听立体声音乐，闭上眼睛能清晰感知各声源的位置。

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
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/// Flutter 主 Activity
///
/// 注册名为 "blind_assist/audio" 的 MethodChannel。
/// 使用 Android 原生 AudioTrack API 维持一个8声源持久化音频流。
class MainActivity : FlutterActivity() {
    companion object {
        /// MethodChannel 名称
        private const val CHANNEL = "blind_assist/audio"

        /// 声源数量（对应画面的8个水平区域）
        private const val NUM_SOURCES = 8
    }

    /// 持久化音频轨道实例
    private var audioTrack: AudioTrack? = null

    /// 播放状态标志
    @Volatile
    private var isPlaying = false

    /// 音频播放线程
    private var playThread: Thread? = null

    /// 声源参数快照（线程安全）
    ///
    /// 使用快照模式：Flutter 线程更新参数时创建新快照，
    /// 音频线程每个数据块读取一次快照，确保参数一致性。
    private class SourceSnapshot {
        /// 各声源频率（Hz）
        val frequencies = DoubleArray(NUM_SOURCES) { 220.0 }

        /// 各声源音量（0.0-1.0）
        val volumes = DoubleArray(NUM_SOURCES) { 0.0 }

        /// 各声源声道平衡（0.0=全左, 0.5=居中, 1.0=全右）
        val pans = DoubleArray(NUM_SOURCES) { 0.5 }
    }

    /// 当前声源参数快照（volatile 保证可见性）
    @Volatile
    private var snapshot = SourceSnapshot()

    /// 配置 Flutter 引擎
    ///
    /// 注册 MethodChannel 处理器：
    ///   - startContinuousAudio: 启动8声源音频流
    ///   - updateMultiSourceAudio(sources): 更新所有声源参数
    ///   - stopAudio: 停止音频流
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startContinuousAudio" -> {
                    startContinuousAudio()
                    result.success(null)
                }
                "updateMultiSourceAudio" -> {
                    // 接收来自 Flutter 的多声源参数更新
                    val sources = call.argument<List<*>>("sources")
                    if (sources != null) {
                        // 创建新快照（复制当前值作为基础）
                        val newSnap = SourceSnapshot()
                        for (i in 0 until NUM_SOURCES) {
                            newSnap.frequencies[i] = snapshot.frequencies[i]
                            newSnap.volumes[i] = snapshot.volumes[i]
                            newSnap.pans[i] = snapshot.pans[i]
                        }

                        // 用新参数更新
                        for (i in sources.indices) {
                            if (i < NUM_SOURCES) {
                                val src = sources[i] as? Map<*, *>
                                if (src != null) {
                                    newSnap.frequencies[i] = (src["frequency"] as? Number)?.toDouble()
                                        ?: 220.0
                                    newSnap.volumes[i] = (src["volume"] as? Number)?.toDouble()
                                        ?: 0.0
                                    newSnap.pans[i] = (src["pan"] as? Number)?.toDouble()
                                        ?: 0.5
                                }
                            }
                        }

                        // 原子性切换快照
                        snapshot = newSnap
                    }
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

    /// 启动8声源持续音频流
    ///
    /// 创建一个持久化 AudioTrack 和后台线程。
    /// 线程不断循环，每个数据块：
    ///   1. 读取当前声源参数快照
    ///   2. 为每个样本混合8个声源的正弦波
    ///   3. 应用各声源独立的声道平衡
    ///   4. 使用限幅器防止削波
    ///   5. 写入 AudioTrack
    @Suppress("DEPRECATION")
    private fun startContinuousAudio() {
        if (isPlaying) return
        isPlaying = true

        val sampleRate = 22050

        playThread = Thread {
            try {
                val minBufferSize = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_STEREO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                val bufferSize = minBufferSize.coerceAtLeast(4096)

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

                val chunkSize = 1024
                // 每个声源的相位（独立维护以确保连续性）
                val phases = DoubleArray(NUM_SOURCES) { 0.0 }
                // 归一化因子：除以 sqrt(N) 防止多声源叠加时削波
                val normFactor = 1.0 / sqrt(NUM_SOURCES.toDouble())

                // 持续生成混合 PCM 数据
                while (isPlaying) {
                    // 每个数据块读取一次快照（确保参数一致性）
                    val snap = snapshot
                    val stereoBuffer = ShortArray(chunkSize * 2)

                    for (i in 0 until chunkSize) {
                        var leftSum = 0.0
                        var rightSum = 0.0

                        // 混合所有8个声源
                        for (s in 0 until NUM_SOURCES) {
                            val vol = snap.volumes[s]
                            if (vol > 0.001) {
                                // 生成正弦波采样
                                val sample = sin(phases[s]) * vol

                                // 等功率声道平衡
                                val angle = snap.pans[s] * PI / 2.0
                                leftSum += sample * cos(angle)
                                rightSum += sample * sin(angle)

                                // 推进相位
                                phases[s] += 2.0 * PI * snap.frequencies[s] / sampleRate
                                if (phases[s] >= 2.0 * PI) phases[s] -= 2.0 * PI
                            }
                        }

                        // 归一化 + 限幅（防止削波）
                        var left = leftSum * normFactor
                        var right = rightSum * normFactor
                        val maxAbs = maxOf(abs(left), abs(right))
                        if (maxAbs > 0.99) {
                            val scale = 0.99 / maxAbs
                            left *= scale
                            right *= scale
                        }

                        // 转换为 16-bit PCM
                        stereoBuffer[i * 2] = (left * Short.MAX_VALUE).toInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort()
                        stereoBuffer[i * 2 + 1] = (right * Short.MAX_VALUE).toInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort()
                    }

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

    /// Activity 销毁时释放资源
    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }
}
