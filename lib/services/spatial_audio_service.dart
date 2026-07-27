/// 空间音频服务
///
/// 负责音频引擎的初始化和实时音频参数控制。
/// 使用 flutter_soloud 振荡器生成连续的音调，
/// 并通过实时更新频率、音量和声道平衡来实现空间音频效果。
///
/// 工作流程：
///   1. initialize() 初始化音频引擎
///   2. start() 开始播放振荡器声音
///   3. updateAudioParams() 实时更新频率、音量、声道平衡
///   4. stop() 停止播放
///   5. dispose() 释放资源
///
/// 当扫描线扫到物体时，调用 updateAudioParams() 更新声音参数；
/// 没有物体时调用 updateAudioParams(null) 静音。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../engine/depth_to_audio_mapper.dart';
import 'settings_service.dart';

/// 空间音频服务（单例模式）
///
/// 管理flutter_soloud音频引擎和振荡器声音源。
/// 提供实时音频参数控制接口。
class SpatialAudioService {
  // ==================== 单例实现 ====================

  /// 单例实例
  static final SpatialAudioService instance = SpatialAudioService._();

  /// 私有构造函数
  SpatialAudioService._();

  // ==================== 音频引擎 ====================

  /// flutter_soloud 引擎实例
  SoLoud? _soLoud;

  /// 振荡器声音句柄
  SoundHandle? _soundHandle;

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

  // ==================== 初始化 ====================

  /// 初始化音频引擎
  ///
  /// 初始化flutter_soloud引擎，准备振荡器。
  /// 此方法应在APP启动时调用。
  ///
  /// 返回true表示初始化成功
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _soLoud = SoLoud.instance;

      // 启动flutter_soloud引擎
      await _soLoud!.initialize();

      _isInitialized = true;
      debugPrint('音频引擎初始化成功');
      return true;
    } catch (e) {
      debugPrint('音频引擎初始化失败: $e');
      return false;
    }
  }

  /// 开始播放
  ///
  /// 创建振荡器声音源并开始播放。
  /// 初始音量为0（静音），等待扫描引擎更新参数。
  Future<bool> start() async {
    if (!_isInitialized || _isPlaying) return false;

    try {
      final settings = SettingsService.instance;

      // 创建振荡器
      // flutter_soloud支持通过setWaveform创建振荡器声音源
      // 波形类型映射：0=正弦, 1=方波, 2=三角, 3=噪点
      _soundHandle = await _soLoud!.setWaveform(
        _getWaveformType(settings.soundType),
      );

      if (_soundHandle != null) {
        // 设置初始参数
        _soLoud!.setFrequency(_soundHandle!, settings.minDistanceFrequency);
        _soLoud!.setVolume(_soundHandle!, 0.0); // 初始静音
        _soLoud!.setPan(_soundHandle!, 0.0); // 居中

        // 开始播放
        await _soLoud!.play(_soundHandle!);
        _isPlaying = true;
        debugPrint('音频开始播放');
      }

      return _isPlaying;
    } catch (e) {
      debugPrint('音频启动失败: $e');
      return false;
    }
  }

  /// 将用户设置的声音类型索引映射为flutter_soloud波形枚举
  ///
  /// [soundType] 0=正弦, 1=方波, 2=三角, 3=噪点
  WaveForm _getWaveformType(int soundType) {
    switch (soundType) {
      case 0:
        return WaveForm.sin;
      case 1:
        return WaveForm.square;
      case 2:
        return WaveForm.triangle;
      case 3:
        return WaveForm.noise; // 噪点声（如果支持）
      default:
        return WaveForm.sin;
    }
  }

  /// 停止播放
  ///
  /// 停止振荡器声音，但不释放资源。
  Future<void> stop() async {
    if (!_isPlaying) return;

    try {
      if (_soundHandle != null) {
        await _soLoud!.stop(_soundHandle!);
      }
      _isPlaying = false;
      _currentVolume = 0.0;
      debugPrint('音频已停止');
    } catch (e) {
      debugPrint('停止音频失败: $e');
    }
  }

  /// 更新音频参数
  ///
  /// 当扫描线扫到物体时调用此方法更新声音参数。
  /// 参数为null时表示没有物体，音量渐变到0。
  ///
  /// [params] 音频参数（频率、音量、声道平衡），null表示静音
  void updateAudioParams(AudioParams? params) {
    if (!_isPlaying || _soundHandle == null) return;

    try {
      if (params != null) {
        // 更新频率
        if ((params.frequency - _currentFrequency).abs() > 1.0) {
          _soLoud!.setFrequency(_soundHandle!, params.frequency);
          _currentFrequency = params.frequency;
        }

        // 更新音量
        if ((params.volume - _currentVolume).abs() > 0.01) {
          _soLoud!.setVolume(_soundHandle!, params.volume);
          _currentVolume = params.volume;
        }

        // 更新声道平衡
        // flutter_soloud的pan范围是-1.0到1.0
        // 我们的pan范围是0.0到1.0，需要转换
        final pan = (params.pan * 2.0 - 1.0);
        if ((pan - _currentPan).abs() > 0.01) {
          _soLoud!.setPan(_soundHandle!, pan);
          _currentPan = pan;
        }
      } else {
        // 没有物体，音量设为0
        if (_currentVolume > 0.01) {
          _soLoud!.setVolume(_soundHandle!, 0.0);
          _currentVolume = 0.0;
        }
      }
    } catch (e) {
      // 静默处理音频更新错误，避免频繁日志
      debugPrint('音频参数更新错误: $e');
    }
  }

  /// 释放资源
  ///
  /// 停止播放并释放flutter_soloud引擎资源。
  Future<void> dispose() async {
    await stop();

    try {
      if (_soundHandle != null) {
        _soLoud!.disposeWaveform(_soundHandle!);
        _soundHandle = null;
      }
      _soLoud!.deinitialize();
    } catch (e) {
      debugPrint('释放音频资源失败: $e');
    }

    _isInitialized = false;
  }
}
