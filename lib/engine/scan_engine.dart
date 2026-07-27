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
class ScanEngine {
  /// 音频参数回调类型
  /// 当扫描到物体时调用，传入音频参数；无物体时传入null
  typedef AudioParamsCallback = void Function(AudioParams? params);

  /// 扫描位置回调类型
  /// 每次扫描位置更新时调用，传入当前位置（0.0-1.0）
  typedef ScanPositionCallback = void Function(double position);

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

    // 步骤2：从深度图提取物体
    if (_currentDepthFrame == null) {
      onAudioParams?.call(null);
      return;
    }

    final object = _extractObjectAt(_currentDepthFrame!, _scanPosition);

    // 步骤3：映射为音频参数
    if (object != null) {
      final params = DepthToAudioMapper.mapObjectToAudio(object);
      onAudioParams?.call(params);
    } else {
      // 没有检测到物体，静音
      onAudioParams?.call(null);
    }
  }

  /// 从深度图中提取指定扫描位置的物体
  ///
  /// 在扫描线覆盖的列范围内，找到最近的物体。
  ///
  /// [frame] 深度图
  /// [position] 扫描位置（0.0-1.0）
  /// 返回检测到的物体，如果没有则返回null
  DetectedObject? _extractObjectAt(DepthFrame frame, double position) {
    final settings = SettingsService.instance;

    // 计算扫描线覆盖的列范围
    final scanWidth = (frame.width * settings.scanLineWidth).round();
    final centerColumn = (position * frame.width).round();
    final startCol = (centerColumn - scanWidth ~/ 2).clamp(0, frame.width - 1);
    final endCol = (centerColumn + scanWidth ~/ 2).clamp(0, frame.width - 1);

    if (startCol >= endCol) return null;

    // 在扫描线范围内，逐列逐行寻找最近物体
    double minDepth = 1.0; // 最近物体的深度（越小越近）
    int nearestCol = centerColumn;
    int nearestRow = frame.height ~/ 2;
    int objectPixelCount = 0;

    // 收集所有属于最近物体的像素
    final List<(int, int, double)> objectPixels = [];

    for (int col = startCol; col <= endCol; col++) {
      for (int row = 0; row < frame.height; row++) {
        final depth = frame.getDepth(col, row);

        // 只关注足够近的物体（深度小于最大距离阈值）
        // 深度0=近, 1=远，所以用1-depth与距离阈值比较
        final distanceRatio = depth; // 0=近, 1=远

        // 过滤掉太远的物体（超过有效距离范围）
        if (distanceRatio > 0.95) continue; // 忽略极远的背景

        if (depth < minDepth) {
          minDepth = depth;
        }
      }
    }

    // 如果整个区域都很远，不生成声音
    if (minDepth > 0.85) return null;

    // 重新扫描，收集属于最近物体的像素
    // 物体定义为：深度值在最近深度±阈值范围内的连续像素
    final depthThreshold = settings.depthEdgeThreshold;

    for (int col = startCol; col <= endCol; col++) {
      for (int row = 0; row < frame.height; row++) {
        final depth = frame.getDepth(col, row);
        if ((depth - minDepth).abs() < depthThreshold) {
          objectPixels.add((col, row, depth));
          objectPixelCount++;
        }
      }
    }

    // 检查物体面积是否足够大
    final totalPixels = (endCol - startCol + 1) * frame.height;
    final areaRatio = objectPixelCount / totalPixels;
    if (areaRatio < settings.minObjectAreaRatio) {
      return null; // 物体太小，忽略
    }

    // 计算物体的属性
    double sumDepth = 0;
    double sumRow = 0;
    double sumCol = 0;

    for (final (col, row, depth) in objectPixels) {
      sumDepth += depth;
      sumRow += row;
      sumCol += col;
    }

    final avgDepth = sumDepth / objectPixelCount;
    final verticalCenter = (sumRow / objectPixelCount) / frame.height;
    final horizontalCenter = (sumCol / objectPixelCount) / frame.width;

    return DetectedObject(
      depth: avgDepth,
      horizontalPosition: horizontalCenter,
      verticalCenter: verticalCenter,
      areaRatio: areaRatio,
    );
  }

  /// 释放资源
  void dispose() {
    stop();
  }
}
