/// 空间音频服务（连续音频流模式）
///
/// 此版本维持一个持续播放的音频流，扫描线每移动一步（~20ms），
/// 就通过 MethodChannel 更新原生音频参数（频率、音量、声道平衡）。
/// 原生 Android AudioTrack 会实时响应参数变化，实现连续扫描音效。
///
/// 与之前"播放短促提示音"不同，此模式：
///   - 无节流限制：每帧都更新参数
///   - 持续发声：音频流不间断，只改变音色
///   - 无延迟：参数变化即时反映在声音上
///   - 雷达/声呐效果：扫描线位置不同，声音连续变化
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/depth_to_audio_mapper.dart';
import 'settings_service.dart';

/// 空间音频服务（单例模式）
///
/// 连续音频流版本。启动时在原生层创建一个持久化 AudioTrack，
/// 每次 updateAudioParams() 被调用时，通过 MethodChannel 实时更新音频参数。
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
    debugPrint('音频引擎初始化成功（连续流模式）');
    return true;
  }

  /// 开始播放
  ///
  /// 启动原生层的持久化音频流。
  Future<bool> start() async {
    if (!_isInitialized || _isPlaying) return false;

    try {
      // 通知原生层启动持续音频流
      await platform.invokeMethod('startContinuousAudio');
      _isPlaying = true;
      _updateCount = 0;
      debugPrint('连续音频流已启动');
      return true;
    } catch (e) {
      debugPrint('启动连续音频流失败: $e');
      return false;
    }
  }

  /// 停止播放
  ///
  /// 标记音频服务为停止状态，并通知原生层停止音频流。
  Future<void> stop() async {
    _isPlaying = false;

    try {
      await platform.invokeMethod('stopAudio');
    } catch (_) {}

    debugPrint('连续音频流已停止（共更新 $_updateCount 次）');
  }

  /// 更新音频参数
  ///
  /// 当扫描线每移动一步时调用此方法（~20ms 一次）。
  /// 将音频参数实时发送到原生层，原生 AudioTrack 立即响应变化。
  ///
  /// 关键设计：
  ///   - 无节流：每次调用都发送更新
  ///   - 连续发声：即使传入 null（无物体），音量设为 0 但流不中断
  ///   - 参数变化即时反映：频率决定音高，音量决定响度，声道平衡决定左右耳
  ///
  /// [params] 音频参数（频率、音量、声道平衡），null 表示静音
  void updateAudioParams(AudioParams? params) {
    if (!_isPlaying) return;

    try {
      _updateCount++;

      if (params != null) {
        // 有物体：发送完整音频参数
        platform.invokeMethod('updateAudio', {
          'frequency': params.frequency,
          'volume': params.volume,
          'pan': params.pan,
        }).catchError((_) {});
      } else {
        // 无物体：音量设为 0（静音但流不中断）
        platform.invokeMethod('updateAudio', {
          'frequency': 220.0,
          'volume': 0.0,
          'pan': 0.5,
        }).catchError((_) {});
      }
    } catch (e) {
      // 静默处理
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await stop();
    _isInitialized = false;
  }
}
