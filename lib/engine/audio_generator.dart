/// 音频波形生成器
///
/// 纯Dart数学计算，生成各种波形的音频采样数据。
/// 不依赖任何音频插件，只负责数学计算。
///
/// 生成的采样数据会被音频服务（SpatialAudioService）输出到扬声器/耳机。
///
/// 支持的波形类型：
///   0=正弦波（纯净的嗡嗡声）
///   1=方波（电子蜂鸣声，类似硬币掉落）
///   2=三角波（柔和的提示音）
///   3=噪点声（类似雨声，更自然）
///
/// 包络处理：
///   攻击（Attack）：声音从0渐变到最大
///   释放（Release）：声音从最大渐变到0
///   使声音更自然，避免突然的咔嗒声
library;

import 'dart:math';
import 'dart:typed_data';

/// 音频波形生成器
///
/// 维护波形的相位状态，可以连续生成采样数据。
/// 每次调用 generateSamples() 生成一段PCM数据。
class AudioGenerator {
  /// 采样率（Hz）
  final int sampleRate;

  /// 波形类型（0=正弦, 1=方波, 2=三角, 3=噪点）
  int soundType;

  /// 当前相位（弧度）
  /// 相位随着每个采样点递增，实现连续波形
  double _phase = 0.0;

  /// 随机数生成器（用于噪点声）
  final Random _random = Random();

  /// 包络状态
  /// 0=静音, 1=攻击中, 2=持续, 3=释放中
  int _envelopeState = 0;

  /// 当前包络值（0.0-1.0）
  double _envelopeValue = 0.0;

  /// 构造函数
  ///
  /// [sampleRate] 采样率（如22050或44100）
  /// [soundType] 波形类型
  AudioGenerator({
    required this.sampleRate,
    this.soundType = 1,
  });

  /// 相位增量计算
  ///
  /// 每个采样点相位增加的量。
  /// 一个完整周期 = 2π弧度
  /// 频率f表示每秒f个周期
  /// 每个采样点的相位增量 = 2π * f / sampleRate
  ///
  /// [frequency] 当前频率（Hz）
  double _getPhaseIncrement(double frequency) {
    return 2.0 * pi * frequency / sampleRate;
  }

  /// 生成单个采样点的波形值
  ///
  /// [frequency] 当前频率（Hz）
  /// 返回-1.0到1.0之间的波形值
  double _generateSample(double frequency) {
    final phaseInc = _getPhaseIncrement(frequency);
    double value;

    switch (soundType) {
      case 0: // 正弦波
        value = sin(_phase);
        break;

      case 1: // 方波
        value = sin(_phase) >= 0 ? 1.0 : -1.0;
        break;

      case 2: // 三角波
        // 使用arcsin(sin(x)) * 2/π 得到三角波
        value = (2.0 / pi) * asin(sin(_phase));
        break;

      case 3: // 噪点声
        value = _random.nextDouble() * 2.0 - 1.0;
        break;

      default:
        value = sin(_phase);
    }

    // 推进相位
    _phase += phaseInc;
    // 保持相位在0到2π之间，避免数值溢出
    if (_phase >= 2.0 * pi) {
      _phase -= 2.0 * pi;
    }

    return value;
  }

  /// 开始攻击（声音渐入）
  ///
  /// 将包络状态设为攻击模式，声音从0渐变到最大。
  void startAttack() {
    _envelopeState = 1;
  }

  /// 开始释放（声音渐出）
  ///
  /// 将包络状态设为释放模式，声音从当前值渐变到0。
  void startRelease() {
    _envelopeState = 3;
  }

  /// 更新包络值
  ///
  /// [attackTime] 攻击时间（秒）
  /// [releaseTime] 释放时间（秒）
  /// 返回当前包络值（0.0-1.0）
  double _updateEnvelope(double attackTime, double releaseTime) {
    // 每个采样点的包络变化量
    final attackRate = attackTime > 0
        ? 1.0 / (sampleRate * attackTime)
        : 1.0;
    final releaseRate = releaseTime > 0
        ? 1.0 / (sampleRate * releaseTime)
        : 1.0;

    switch (_envelopeState) {
      case 1: // 攻击中：从0到1
        _envelopeValue += attackRate;
        if (_envelopeValue >= 1.0) {
          _envelopeValue = 1.0;
          _envelopeState = 2; // 切换到持续状态
        }
        break;

      case 2: // 持续：保持最大值
        _envelopeValue = 1.0;
        break;

      case 3: // 释放中：从当前值到0
        _envelopeValue -= releaseRate;
        if (_envelopeValue <= 0.0) {
          _envelopeValue = 0.0;
          _envelopeState = 0; // 切换到静音状态
        }
        break;

      default: // 静音
        _envelopeValue = 0.0;
    }

    return _envelopeValue;
  }

  /// 生成立体声采样数据
  ///
  /// 生成一段PCM采样数据，包含左右两个声道。
  /// 应用包络和立体声平衡。
  ///
  /// [sampleCount] 要生成的采样点数
  /// [frequency] 波形频率（Hz）
  /// [volume] 音量（0.0-1.0）
  /// [pan] 立体声平衡（0.0=全左, 0.5=居中, 1.0=全右）
  /// [enableEnvelope] 是否启用包络
  /// [attackTime] 攻击时间（秒）
  /// [releaseTime] 释放时间（秒）
  /// [stereoSeparation] 立体声分离强度（0.0-1.0）
  ///
  /// 返回Float32List，长度为 sampleCount * 2（交错存储左右声道）
  Float32List generateStereoSamples({
    required int sampleCount,
    required double frequency,
    required double volume,
    required double pan,
    required bool enableEnvelope,
    required double attackTime,
    required double releaseTime,
    required double stereoSeparation,
  }) {
    final buffer = Float32List(sampleCount * 2);

    // 计算左右声道的音量系数（等功率panning）
    // pan=0 → 全左, pan=0.5 → 居中, pan=1 → 全右
    // 使用余弦/正弦曲线实现等功率平移
    final angle = pan * pi / 2.0;
    double leftGain = cos(angle);
    double rightGain = sin(angle);

    // 应用立体声分离强度
    // separation=1.0 → 完全分离
    // separation=0.0 → 左右相同
    final sep = stereoSeparation.clamp(0.0, 1.0);
    leftGain = leftGain * sep + 0.5 * (1.0 - sep);
    rightGain = rightGain * sep + 0.5 * (1.0 - sep);

    for (int i = 0; i < sampleCount; i++) {
      // 生成基础波形采样
      final sample = _generateSample(frequency);

      // 更新包络
      final envelope = enableEnvelope
          ? _updateEnvelope(attackTime, releaseTime)
          : 1.0;

      // 计算最终采样值 = 波形 × 音量 × 包络
      final finalSample = sample * volume * envelope;

      // 写入左右声道（交错存储）
      buffer[i * 2] = (finalSample * leftGain).clamp(-1.0, 1.0); // 左声道
      buffer[i * 2 + 1] = (finalSample * rightGain).clamp(-1.0, 1.0); // 右声道
    }

    return buffer;
  }

  /// 静音生成
  ///
  /// 当没有检测到物体时，生成静音数据。
  /// 仍然推进包络状态（进入释放），使声音自然消失。
  ///
  /// [sampleCount] 采样点数
  /// [enableEnvelope] 是否启用包络
  /// [releaseTime] 释放时间（秒）
  Float32List generateSilence({
    required int sampleCount,
    required bool enableEnvelope,
    required double releaseTime,
  }) {
    final buffer = Float32List(sampleCount * 2);

    if (enableEnvelope && _envelopeState != 0) {
      // 如果启用了包络且声音未完全消失，进入释放状态
      if (_envelopeState != 3) startRelease();

      for (int i = 0; i < sampleCount; i++) {
        final envelope = _updateEnvelope(0.0, releaseTime);
        buffer[i * 2] = 0.0;
        buffer[i * 2 + 1] = 0.0;
      }
    }

    return buffer;
  }

  /// 重置生成器状态
  ///
  /// 清除相位和包络状态，用于重新开始一段新的声音。
  void reset() {
    _phase = 0.0;
    _envelopeState = 0;
    _envelopeValue = 0.0;
  }
}
