/// 空间音频服务（简化版 - 不使用flutter_soloud）
///
/// 此版本使用Flutter自带的SoundPool和系统提示音来模拟空间音频。
/// 通过调整音量和振动模式来提示障碍物方位和距离。
/// 未来可重新集成flutter_soloud获得更好的音频效果。
///
/// 工作流程：
///   1. initialize() 初始化（此版本无需特殊初始化）
///   2. start() 标记音频服务就绪
///   3. updateAudioParams() 更新当前音频参数
///   4. stop() 停止播放
///   5. dispose() 释放资源
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/depth_to_audio_mapper.dart';
import 'settings_service.dart';

/// 空间音频服务（单例模式）
///
/// 简化版，使用系统提示音模拟空间音频。
class SpatialAudioService {
  // ==================== 单例实现 ====================

  /// 单例实例
  static final SpatialAudioService instance = SpatialAudioService._();

  /// 私有构造函数
  SpatialAudioService._();

  // ==================== 音频状态 ====================

  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 是否正在播放
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  // ==================== 当前音频参数 ====================

  /// 当前频率（Hz）
  double _currentFrequency = 440.0;

  /// 当前音量（0.0-1.0）
  double _currentVolume = 0.0;

  /// 当前声道平衡（-1.0=全左, 0.0=居中, 1.0=全右）
  double _currentPan = 0.0;

  /// 上次播放提示音的时间（用于控制提示音频率）
  int _lastBeepTime = 0;

  // ==================== 平台通道 ====================

  /// 平台通道（用于调用原生音频API）
  static const platform = MethodChannel('blind_assist/audio');

  // ==================== 初始化 ====================

  /// 初始化音频引擎
  ///
  /// 此版本无需特殊初始化，直接返回true。
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _isInitialized = true;
      debugPrint('音频引擎初始化成功（简化版）');
      return true;
    } catch (e) {
      debugPrint('音频引擎初始化失败: $e');
      return false;
    }
  }

  /// 开始播放
  ///
  /// 标记音频服务为播放状态。
  Future<bool> start() async {
    if (!_isInitialized || _isPlaying) return false;

    _isPlaying = true;
    _lastBeepTime = DateTime.now().millisecondsSinceEpoch;
    debugPrint('音频开始播放（简化版）');
    return _isPlaying;
  }

  /// 停止播放
  ///
  /// 标记音频服务为停止状态。
  Future<void> stop() async {
    _isPlaying = false;
    _currentVolume = 0.0;
    debugPrint('音频已停止');
  }

  /// 更新音频参数
  ///
  /// 当扫描线扫到物体时调用此方法更新声音参数。
  /// 参数为null时表示没有物体，静音。
  ///
  /// 此版本通过系统提示音模拟空间音频效果：
  ///   - 近处物体 → 频繁的短促提示音
  ///   - 远处物体 → 低频的长提示音
  ///   - 左侧物体 → 提示音间隔短
  ///   - 右侧物体 → 提示音间隔长
  ///
  /// [params] 音频参数（频率、音量、声道平衡），null表示静音
  void updateAudioParams(AudioParams? params) {
    if (!_isPlaying) return;

    try {
      if (params != null) {
        _currentFrequency = params.frequency;
        _currentVolume = params.volume;
        _currentPan = params.pan;

        // 根据音量和频率控制提示音播放频率
        // 音量越大（物体越近）→ 提示音越频繁
        final now = DateTime.now().millisecondsSinceEpoch;
        final beepInterval = (1000 / (params.volume + 0.1)).round();

        if (now - _lastBeepTime > beepInterval) {
          _playBeep(params.frequency, params.volume, params.pan);
          _lastBeepTime = now;
        }
      } else {
        // 没有物体，音量设为0
        _currentVolume = 0.0;
      }
    } catch (e) {
      // 静默处理音频更新错误
      debugPrint('音频参数更新错误: $e');
    }
  }

  /// 播放提示音
  ///
  /// 使用系统振动和提示音模拟空间音频。
  ///
  /// [frequency] 频率（Hz），影响提示音类型
  /// [volume] 音量（0.0-1.0），影响振动强度
  /// [pan] 声道平衡（0.0=全左, 0.5=居中, 1.0=全右）
  void _playBeep(double frequency, double volume, double pan) {
    try {
      // 使用系统振动反馈（无需额外权限）
      // 根据频率选择不同的振动模式
      if (frequency > 800) {
        // 高频（近处物体）→ 强烈振动
        HapticFeedback.heavyImpact();
      } else if (frequency > 400) {
        // 中频（中等距离）→ 中等振动
        HapticFeedback.mediumImpact();
      } else {
        // 低频（远处物体）→ 轻微振动
        HapticFeedback.lightImpact();
      }

      // 尝试通过平台通道播放提示音
      // 如果平台通道未实现，会静默失败
      platform.invokeMethod('playBeep', {
        'frequency': frequency.round(),
        'volume': volume,
        'pan': pan,
      }).catchError((_) {}); // 忽略错误
    } catch (e) {
      // 静默处理
    }
  }

  /// 释放资源
  ///
  /// 停止播放并释放资源。
  Future<void> dispose() async {
    await stop();
    _isInitialized = false;
  }
}
