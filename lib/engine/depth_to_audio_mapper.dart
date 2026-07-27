/// 深度到音频映射器
///
/// 将深度图中的物体信息映射为音频参数（频率、音量、声道平衡）。
///
/// 核心映射关系：
///   - 深度（距离） → 频率：近=高音（像硬币掉落），远=低音（嗡嗡声）
///   - 深度（距离） → 音量：近=大声，远=小声
///   - 水平位置 → 左右声道平衡：左=左耳响，右=右耳响
///   - 垂直位置 → 音色微调：上方物体音调略高，下方略低
///
/// 这种映射让盲人用户能通过听觉感知：
///   1. 方位：声音在左耳还是右耳（水平位置）
///   2. 距离：声音的音调和音量（近=高音大声）
///   3. 形状：扫描线扫过物体时的声音变化轮廓
library;

import 'dart:math' as math;

import '../models/depth_data.dart';
import '../services/settings_service.dart';

/// 音频参数
///
/// 一个物体对应的音频参数，用于驱动AudioGenerator生成声音。
class AudioParams {
  /// 频率（Hz）- 决定音调高低
  final double frequency;

  /// 音量（0.0-1.0）- 决定声音大小
  final double volume;

  /// 左右声道平衡（0.0=全左, 0.5=居中, 1.0=全右）
  final double pan;

  /// 构造函数
  AudioParams({
    required this.frequency,
    required this.volume,
    required this.pan,
  });
}

/// 深度到音频映射器
///
/// 根据用户设置的参数，将深度数据映射为音频参数。
/// 所有映射规则都使用SettingsService中的用户配置，可随时调整。
class DepthToAudioMapper {
  /// 将检测到的物体映射为音频参数
  ///
  /// [obj] 检测到的物体
  /// 返回对应的音频参数（频率、音量、声道平衡）
  static AudioParams mapObjectToAudio(DetectedObject obj) {
    final settings = SettingsService.instance;

    // 1. 深度 → 频率
    // depth=0.0（最近）→ 最高频率（清脆的硬币声）
    // depth=1.0（最远）→ 最低频率（低沉的嗡嗡声）
    final frequency = _mapDepthToFrequency(obj.depth);

    // 2. 深度 → 音量
    // depth=0.0（最近）→ 最大音量
    // depth=1.0（最远）→ 最小音量
    final volume = _mapDepthToVolume(obj.depth);

    // 3. 水平位置 → 左右声道平衡
    // horizontalPosition=0.0（最左）→ pan=0.0（全左耳）
    // horizontalPosition=0.5（中间）→ pan=0.5（居中）
    // horizontalPosition=1.0（最右）→ pan=1.0（全右耳）
    final pan = obj.horizontalPosition;

    // 4. 垂直位置 → 音调微调
    // 上方物体音调略高，下方物体音调略低
    // 这让用户能区分物体是在头部上方还是下方
    final verticalAdjustment = (0.5 - obj.verticalCenter) * 0.2; // ±10%调整
    final adjustedFrequency = frequency * (1.0 + verticalAdjustment);

    return AudioParams(
      frequency: adjustedFrequency,
      volume: volume,
      pan: pan,
    );
  }

  /// 深度值映射为频率
  ///
  /// 深度0.0（最近）→ 最高频率（minDistanceFrequency，默认2000Hz）
  /// 深度1.0（最远）→ 最低频率（maxDistanceFrequency，默认200Hz）
  ///
  /// 使用指数映射而非线性映射，因为人耳对频率的感知是对数的，
  /// 指数映射能让近处和远处的频率差异更明显。
  ///
  /// [depth] 深度值（0.0=最近, 1.0=最远）
  static double _mapDepthToFrequency(double depth) {
    final settings = SettingsService.instance;
    final d = depth.clamp(0.0, 1.0);

    // 指数映射：f = fMin * (fMax/fMin)^(1-d)
    // 当d=0时，f=fMax（最近=最高音）
    // 当d=1时，f=fMin（最远=最低音）
    final fMax = settings.minDistanceFrequency; // 最近的频率
    final fMin = settings.maxDistanceFrequency; // 最远的频率
    final ratio = fMax / fMin;
    return fMin * math.pow(ratio, 1.0 - d).toDouble();
  }

  /// 深度值映射为音量
  ///
  /// 深度0.0（最近）→ 最大音量
  /// 深度1.0（最远）→ 最小音量
  ///
  /// 超过最大距离阈值的物体音量降为0（不发声）
  ///
  /// [depth] 深度值（0.0=最近, 1.0=最远）
  static double _mapDepthToVolume(double depth) {
    final settings = SettingsService.instance;
    final d = depth.clamp(0.0, 1.0);

    // 线性映射：最近=maxVolume, 最远=minVolume
    return settings.maxVolume - d * (settings.maxVolume - settings.minVolume);
  }
}
