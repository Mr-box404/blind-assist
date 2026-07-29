// android/app/src/main/kotlin/com/blindassist/blind_assist/MainActivity.kt
// Flutter 应用入口 + 脉冲敲击式8声源立体声音频引擎
//
// 核心改进：用脉冲敲击声代替连续嗡嗡声。
//
// 人耳定位原理：
//   1. 瞬变起始（attack）→ 大脑通过声音起始的时间差定位
//   2. 丰富谐波 → 多频率成分提供频谱定位线索
//   3. 宽带噪声 → 像真实敲击声，最容易定位
//   4. 节奏模式 → 脉冲间隔传递距离信息（近=急促, 远=缓慢）
//
// 每个脉冲 = 基频正弦波 + 2次/3次谐波 + 白噪声 × 快速衰减包络
// 脉冲时长约 50ms，脉冲间隔由距离决定（0.15s~0.8s）
// 8个声源各自独立脉冲，互不干扰，像8个方位各自敲击

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
import kotlin.math.exp
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/// Flutter 主 Activity
///
/// 注册名为 "blind_assist/audio" 的 MethodChannel。
/// 使用脉冲敲击式音频引擎，8个声源各自独立发出短促敲击声。
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "blind_assist/audio"
        private const val NUM_SOURCES = 8
        private const val SAMPLE_RATE = 22050
    }

    private var audioTrack: AudioTrack? = null

    @Volatile
    private var isPlaying = false

    private var playThread: Thread? = null

    /// 声源参数快照（由 Flutter 端更新）
    private class SourceSnapshot {
        val frequencies = DoubleArray(NUM_SOURCES) { 220.0 }
        val volumes = DoubleArray(NUM_SOURCES) { 0.0 }
        val pans = DoubleArray(NUM_SOURCES) { 0.5 }
    }

    @Volatile
    private var snapshot = SourceSnapshot()

    /// 单个声源的运行时状态
    ///
    /// 管理脉冲生成：何时开始脉冲、脉冲持续时间、衰减包络。
    private class VoiceState(seed: Long) {
        /// 基频（Hz）
        var frequency = 220.0

        /// 音量（0.0-1.0）
        var volume = 0.0

        /// 声道平衡（0.0=全左, 0.5=居中, 1.0=全右）
        var pan = 0.5

        /// 距下次脉冲的剩余样本数
        var samplesUntilNextPulse: Int = 0

        /// 当前脉冲剩余样本数（0=不在脉冲中）
        var pulseSamplesRemaining: Int = 0

        /// 正弦波相位
        var phase: Double = 0.0

        /// 随机数生成器（用于噪声成分）
        private val random = Random(seed)

        /// 脉冲持续时间（样本数）= 50ms
        companion object {
            const val PULSE_DURATION = 1102  // 50ms × 22050Hz
            const val ATTACK_SAMPLES = 88    // 4ms attack
        }

        /// 计算脉冲间隔（样本数）
        ///
        /// 近物体（高频）→ 短间隔（0.15s）→ 急促敲击
        /// 远物体（低频）→ 长间隔（0.8s）→ 缓慢敲击
        private fun pulseIntervalSamples(): Int {
            // 频率范围 200-2000Hz → 归一化 0(远)-1(近)
            val normalized = ((frequency - 200.0) / 1800.0).coerceIn(0.0, 1.0)
            // 间隔 0.8s 到 0.15s
            val intervalSec = 0.8 - normalized * 0.65
            return (intervalSec * SAMPLE_RATE).toInt()
        }

        /// 更新参数
        fun updateParams(freq: Double, vol: Double, p: Double) {
            frequency = freq.coerceIn(20.0, 5000.0)
            volume = vol.coerceIn(0.0, 1.0)
            pan = p.coerceIn(0.0, 1.0)
        }

        /// 生成下一个采样值
        ///
        /// 如果不在脉冲中且等待时间已到，开始新脉冲。
        /// 脉冲期间生成：基频 + 2次谐波 + 3次谐波 + 白噪声，乘以衰减包络。
        ///
        /// 返回单个采样值（-1.0 到 1.0）
        fun nextSample(): Double {
            if (volume < 0.001) {
                pulseSamplesRemaining = 0
                return 0.0
            }

            // 检查是否需要开始新脉冲
            if (pulseSamplesRemaining <= 0) {
                if (samplesUntilNextPulse <= 0) {
                    // 开始新脉冲
                    pulseSamplesRemaining = PULSE_DURATION
                    phase = 0.0
                } else {
                    samplesUntilNextPulse--
                    return 0.0
                }
            }

            // 计算脉冲年龄（从脉冲开始算起的样本数）
            val pulseAge = PULSE_DURATION - pulseSamplesRemaining

            // 计算包络（快速 attack + 指数 decay）
            val envelope: Double = if (pulseAge < ATTACK_SAMPLES) {
                // Attack 阶段：线性上升
                pulseAge.toDouble() / ATTACK_SAMPLES
            } else {
                // Decay 阶段：指数衰减
                val decayProgress = (pulseAge - ATTACK_SAMPLES).toDouble() /
                    (PULSE_DURATION - ATTACK_SAMPLES)
                exp(-decayProgress * 6.0)
            }

            // 生成音频样本
            // 基频（60%）+ 2次谐波（25%）+ 3次谐波（10%）+ 白噪声（5%）
            val base = sin(phase) * 0.60
            val h2 = sin(phase * 2.0) * 0.25
            val h3 = sin(phase * 3.0) * 0.10
            val noise = (random.nextDouble() * 2.0 - 1.0) * 0.05
            val sample = base + h2 + h3 + noise

            // 推进相位
            phase += 2.0 * PI * frequency / SAMPLE_RATE
            if (phase >= 2.0 * PI) phase -= 2.0 * PI

            pulseSamplesRemaining--

            // 脉冲结束时，设置下次脉冲的等待时间
            if (pulseSamplesRemaining <= 0) {
                samplesUntilNextPulse = pulseIntervalSamples()
            }

            return sample * envelope * volume
        }

        /// 重置状态
        fun reset(seedOffset: Int) {
            samplesUntilNextPulse = seedOffset * 500 + 200
            pulseSamplesRemaining = 0
            phase = 0.0
        }
    }

    /// 8个声源的状态（每个有独立的随机种子避免同步）
    private val voices = Array(NUM_SOURCES) { i -> VoiceState(seed = 42L + i * 1000L) }

    /// 配置 Flutter 引擎
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startContinuousAudio" -> {
                    startContinuousAudio()
                    result.success(null)
                }
                "updateMultiSourceAudio" -> {
                    val sources = call.argument<List<*>>("sources")
                    if (sources != null) {
                        val newSnap = SourceSnapshot()
                        // 复制当前值
                        for (i in 0 until NUM_SOURCES) {
                            newSnap.frequencies[i] = snapshot.frequencies[i]
                            newSnap.volumes[i] = snapshot.volumes[i]
                            newSnap.pans[i] = snapshot.pans[i]
                        }
                        // 更新新值
                        for (i in sources.indices) {
                            if (i < NUM_SOURCES) {
                                val src = sources[i] as? Map<*, *>
                                if (src != null) {
                                    newSnap.frequencies[i] = (src["frequency"] as? Number)?.toDouble() ?: 220.0
                                    newSnap.volumes[i] = (src["volume"] as? Number)?.toDouble() ?: 0.0
                                    newSnap.pans[i] = (src["pan"] as? Number)?.toDouble() ?: 0.5
                                }
                            }
                        }
                        snapshot = newSnap

                        // 同步到声源状态
                        for (i in 0 until NUM_SOURCES) {
                            voices[i].updateParams(
                                newSnap.frequencies[i],
                                newSnap.volumes[i],
                                newSnap.pans[i]
                            )
                        }
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

    /// 启动脉冲式音频流
    @Suppress("DEPRECATION")
    private fun startContinuousAudio() {
        if (isPlaying) return
        isPlaying = true

        // 重置所有声源（给每个声源不同的初始偏移，避免同步脉冲）
        for (i in 0 until NUM_SOURCES) {
            voices[i].reset(i)
        }

        playThread = Thread {
            try {
                val minBufferSize = AudioTrack.getMinBufferSize(
                    SAMPLE_RATE,
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
                                .setSampleRate(SAMPLE_RATE)
                                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                                .build()
                        )
                        .setBufferSizeInBytes(bufferSize)
                        .setTransferMode(AudioTrack.MODE_STREAM)
                        .build()
                } else {
                    AudioTrack(
                        AudioManager.STREAM_MUSIC,
                        SAMPLE_RATE,
                        AudioFormat.CHANNEL_OUT_STEREO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        bufferSize,
                        AudioTrack.MODE_STREAM
                    )
                }

                audioTrack?.play()

                val chunkSize = 1024
                // 归一化因子：防止多声源同时脉冲时削波
                val normFactor = 1.0 / sqrt(NUM_SOURCES.toDouble())

                while (isPlaying) {
                    val stereoBuffer = ShortArray(chunkSize * 2)

                    for (i in 0 until chunkSize) {
                        var leftSum = 0.0
                        var rightSum = 0.0

                        // 混合8个声源
                        for (s in 0 until NUM_SOURCES) {
                            val sample = voices[s].nextSample()
                            if (abs(sample) > 0.0001) {
                                // 等功率声道平衡
                                val angle = voices[s].pan * PI / 2.0
                                leftSum += sample * cos(angle)
                                rightSum += sample * sin(angle)
                            }
                        }

                        // 归一化 + 限幅
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

    private fun stopAudio() {
        isPlaying = false
        playThread?.join(300)
        cleanup()
    }

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
