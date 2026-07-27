/// 扫描线引擎
///
/// 核心协调器，负责：
///   1. 维护扫描线的当前位置（0.0=最左, 1.0=最右）
///   2. 按设定的扫描周期移动扫描位置
///   3. 从深度图中提取扫描位置的物体信息
///   4. 将物体信息映射为音频参数
///
/// 扫描原理（类似雷达扫描）：
///   扫描线从画面左侧扫到右侧，周期循环。
///   当扫描线经过障碍物时，对应的立体声会响起。
///   盲人通过声音的左右耳差异和音调变化，
///   感知障碍物的方位、距离和形状。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/depth_data.dart';
import '../services/settings_service.dart';
import 'depth_to_audio_mapper.dart';

/// 扫描引擎
///
/// 协调深度图扫描和音频参数生成。
/// 使用方法：
///   1. 调用 start() 开始扫描
///   2. 每帧调用 updateWithDepthFrame() 传入新的深度图
///   3. 引擎会通过回调输出音频参数
///   4. 调用 stop() 停止扫描
/// 音频参数回调类型
/// 当扫描到物体时调用，传入音频参数；无物体时传入null
typedef AudioParamsCallback = void Function(AudioParams? params);

/// 扫描位置回调类型
/// 每次扫描位置更新时调用，传入当前位置（0.0-1.0）
typedef ScanPositionCallback = void Function(double position);

class ScanEngine {

  // ==================== 状态 ====================

  /// 当前扫描位置（0.0=最左, 1.0=最右）
  double _scanPosition = 0.0;

  /// 获取当前扫描位置
  double get scanPosition => _scanPosition;

  /// 扫描是否正在运行
  bool _isRunning = false;

  /// 是否正在运行
  bool get isRunning => _isRunning;

  /// 最新的深度图
  DepthFrame? _currentDepthFrame;

  // ==================== 回调 ====================

  /// 音频参数回调
  AudioParamsCallback? onAudioParams;

  /// 扫描位置回调（用于UI更新扫描线位置）
  ScanPositionCallback? onScanPosition;

  // ==================== 定时器 ====================

  /// 扫描位置更新定时器
  Timer? _scanTimer;

  /// 扫描更新间隔（毫秒）
  /// 每隔此时间更新一次扫描位置和音频参数
  static const int _updateIntervalMs = 20; // 50fps更新

  /// 构造函数
  ScanEngine();

  /// 开始扫描
  ///
  /// 启动定时器，开始周期性更新扫描位置和音频参数。
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _scanPosition = 0.0;

    // 启动定时器，每20ms更新一次
    _scanTimer = Timer.periodic(
      const Duration(milliseconds: _updateIntervalMs),
      (_) => _tick(),
    );

    debugPrint('扫描引擎已启动');
  }

  /// 停止扫描
  ///
  /// 停止定时器，重置扫描位置。
  /// 停止时会通知音频参数为null（静音）。
  void stop() {
    _isRunning = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanPosition = 0.0;

    // 通知静音
    onAudioParams?.call(null);
    onScanPosition?.call(0.0);

    debugPrint('扫描引擎已停止');
  }

  /// 更新深度图
  ///
  /// 由外部（主界面）在收到新的摄像头帧并完成深度估计后调用。
  /// 引擎会缓存最新的深度图，供扫描线使用。
  ///
  /// [frame] 新的深度图
  void updateWithDepthFrame(DepthFrame frame) {
    _currentDepthFrame = frame;
  }

  /// 定时器回调 - 每次扫描更新
  ///
  /// 执行步骤：
  ///   1. 推进扫描位置
  ///   2. 从深度图提取当前扫描位置的物体
  ///   3. 映射为音频参数
  ///   4. 通过回调输出
  void _tick() {
    if (!_isRunning) return;

    final settings = SettingsService.instance;

    // 步骤1：推进扫描位置
    // 每次tick推进的距离 = 更新间隔 / 扫描周期
    final progress = _updateIntervalMs / 1000.0 / settings.scanPeriodSeconds;
    _scanPosition += progress;

    // 扫描位置到达最右后，回到最左（循环扫描）
    if (_scanPosition >= 1.0) {
      _scanPosition = _scanPosition % 1.0;
    }

    // 通知UI更新扫描线位置
    onScanPosition?.call(_scanPosition);

    // 步骤2：从深度图提取物体参数
    if (_currentDepthFrame == null) {
      // 没有深度图数据时发送静音
      onAudioParams?.call(null);
      return;
    }

    // _extractObjectAt 始终返回 DetectedObject，确保音频持续
    final object = _extractObjectAt(_currentDepthFrame!, _scanPosition);

    // 步骤3：映射为音频参数并输出
    final params = DepthToAudioMapper.mapObjectToAudio(object);
    onAudioParams?.call(params);
  }

  /// 从深度图中提取指定扫描位置的音频参数对应物
  ///
  /// 与旧版本不同，此方法始终返回一个 DetectedObject（永不返回 null），
  /// 确保音频流持续播放。
  ///
  /// 方法：
  ///   1. 在扫描线覆盖的列范围内扫描所有像素
  ///   2. 计算加权平均深度（近处像素权重更高）
  ///   3. 对于"空旷"区域返回低音量、低频率的环境音
  ///   4. 对于有物体的区域返回对应音效
  ///
  /// [frame] 深度图
  /// [position] 扫描位置（0.0-1.0）
  /// 返回检测到的物体参数（始终非空）
  DetectedObject _extractObjectAt(DepthFrame frame, double position) {
    final settings = SettingsService.instance;

    // 计算扫描线覆盖的列范围
    final scanWidth = (frame.width * settings.scanLineWidth).round();
    final centerColumn = (position * frame.width).round();
    final startCol = (centerColumn - scanWidth ~/ 2).clamp(0, frame.width - 1);
    final endCol = (centerColumn + scanWidth ~/ 2).clamp(0, frame.width - 1);

    if (startCol >= endCol) {
      // 列范围无效，返回环境底音
      return DetectedObject(
        depth: 0.9,
        horizontalPosition: position,
        verticalCenter: 0.5,
        areaRatio: 0.0,
      );
    }

    // === 第一轮：扫描整列，收集深度数据 ===
    double minDepth = 1.0;
    double sumWeightedDepth = 0.0;
    double totalWeight = 0.0;

    for (int col = startCol; col <= endCol; col++) {
      for (int row = 0; row < frame.height; row++) {
        final depth = frame.getDepth(col, row);
        if (depth < minDepth) {
          minDepth = depth;
        }

        // 加权：近处（深度小）权重高，远处（深度大）权重低
        final weight = 1.0 - depth;
        sumWeightedDepth += depth * weight;
        totalWeight += weight;
      }
    }

    final totalPixels = (endCol - startCol + 1) * frame.height;

    // 计算加权平均深度
    final weightedAvgDepth = totalWeight > 0.01
        ? (sumWeightedDepth / totalWeight)
        : 0.9;

    // 计算区域占比：将深度在阈值范围内的像素视为"物体"
    final depthThreshold = settings.depthEdgeThreshold;
    int objectPixelCount = 0;
    double sumDepth = 0.0;
    double sumRow = 0.0;

    for (int col = startCol; col <= endCol; col++) {
      for (int row = 0; row < frame.height; row++) {
        final depth = frame.getDepth(col, row);
        if ((depth - minDepth).abs() < depthThreshold) {
          objectPixelCount++;
          sumDepth += depth;
          sumRow += row;
        }
      }
    }

    final areaRatio = objectPixelCount / totalPixels;
    final avgDepth = objectPixelCount > 0 ? sumDepth / objectPixelCount : 0.9;
    final verticalCenter = objectPixelCount > 0
        ? (sumRow / objectPixelCount) / frame.height
        : 0.5;

    // === 生成音频参数 ===
    // 始终返回一个 DetectedObject，确保持续发声
    // 根据区域占比决定声音是"物体音"还是"环境底音"
    final effectiveDepth = areaRatio > settings.minObjectAreaRatio
        ? avgDepth          // 有物体：使用物体深度
        : weightedAvgDepth; // 空旷区域：使用加权平均深度

    // 空旷区域降低音量（通过将深度映射到更远的距离）
    final outputDepth = areaRatio > settings.minObjectAreaRatio
        ? effectiveDepth
        : effectiveDepth * 0.3 + 0.7; // 混入 70% 的远距离，使音量更小

    return DetectedObject(
      depth: outputDepth.clamp(0.0, 1.0),
      horizontalPosition: (centerColumn / frame.width).clamp(0.0, 1.0),
      verticalCenter: verticalCenter.clamp(0.0, 1.0),
      areaRatio: areaRatio,
    );
  }

  /// 释放资源
  void dispose() {
    stop();
  }
}
