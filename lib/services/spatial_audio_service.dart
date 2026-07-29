/// 空间音频服务（8声源连续音频流模式）
///
/// 维持一个持续播放的8声源立体声音频流。
/// 每个声源对应画面中的一个水平区域（从左到右8等分），
/// 拥有独立的频率、音量和声道平衡。
///
/// 所有8个声源同时播放，混合成立体声输出。
/// 这样盲人可以同时听到所有方位的物体声音：
///   - 左侧区域的物体 → 左耳听到
///   - 右侧区域的物体 → 右耳听到
///   - 近处物体 → 高音+大声
///   - 远处物体 → 低音+小声
///
/// 类似听立体声音乐，闭上眼睛能清晰感知各声源的位置和方向。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/depth_to_audio_mapper.dart';

/// 空间音频服务（单例模式）
///
/// 8声源连续音频流版本。启动时在原生层创建一个持久化 AudioTrack，
/// 支持8个独立声源同时播放。
class SpatialAudioService {
  // ==================== 单例实现 ====================

  /// 单例实例
  static final SpatialAudioService instance = SpatialAudioService._();

  /// 私有构造函数
  SpatialAudioService._();

  // ==================== 状态 ====================

  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 是否正在播放
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// 更新计数器（仅用于调试）
  int _updateCount = 0;

  // ==================== 平台通道 ====================

  /// 平台通道（用于调用原生音频 API）
  static const platform = MethodChannel('blind_assist/audio');

  // ==================== 初始化 ====================

  /// 初始化音频引擎
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = true;
    debugPrint('音频引擎初始化成功（8声源模式）');
    return true;
  }

  /// 开始播放
  ///
  /// 启动原生层的8声源持久化音频流。
  Future<bool> start() async {
    if (!_isInitialized || _isPlaying) return false;

    try {
      await platform.invokeMethod('startContinuousAudio');
      _isPlaying = true;
      _updateCount = 0;
      debugPrint('8声源音频流已启动');
      return true;
    } catch (e) {
      debugPrint('启动音频流失败: $e');
      return false;
    }
  }

  /// 停止播放
  Future<void> stop() async {
    _isPlaying = false;

    try {
      await platform.invokeMethod('stopAudio');
    } catch (_) {}

    debugPrint('音频流已停止（共更新 $_updateCount 次）');
  }

  /// 更新多声源音频参数
  ///
  /// 将8个声源的参数发送到原生层。
  /// 原生 AudioTrack 会将所有声源混合播放。
  ///
  /// 每个声源的参数：
  ///   - frequency: 频率，由物体距离决定（近=高音，远=低音）
  ///   - volume: 音量，由物体距离决定（近=大声，远=小声）
  ///   - pan: 声道平衡，由区域位置决定（左=0.0, 中=0.5, 右=1.0）
  ///
  /// [sources] 8个声源的音频参数列表
  void updateMultiSourceAudio(List<AudioParams> sources) {
    if (!_isPlaying) return;

    try {
      _updateCount++;

      // 将 AudioParams 列表转换为 Map 列表发送到原生层
      final sourceList = sources
          .map((s) => <String, double>{
                'frequency': s.frequency,
                'volume': s.volume,
                'pan': s.pan,
              })
          .toList();

      platform.invokeMethod('updateMultiSourceAudio', {
        'sources': sourceList,
      }).catchError((_) {});
    } catch (_) {
      // 静默处理
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await stop();
    _isInitialized = false;
  }
}
