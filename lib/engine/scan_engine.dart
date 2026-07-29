/// 扫描线引擎（8声源模式）
///
/// 核心设计：将画面分为8个水平区域（从左到右），
/// 每个区域独立分析最近物体，生成独立的声源参数。
/// 8个声源同时播放，每个声源的声道平衡(pan)固定在其区域位置。
///
/// 与旧版单声源扫描的区别：
///   - 旧版：扫描线从左扫到右，每次只播放一个声音 → 杂乱、无法分辨方位
///   - 新版：8个区域同时分析、同时播放 → 像立体声音乐一样清晰感知位置
///
/// 音频更新频率为10Hz（每100ms更新一次），避免参数变化过快导致杂乱。
/// 扫描线仍然在UI上显示（50fps），但音频独立于扫描线位置。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/depth_data.dart';
import '../services/settings_service.dart';
import 'depth_to_audio_mapper.dart';

/// 多声源音频回调类型
///
/// 每次音频更新时调用，传入8个声源的参数列表。
/// 空列表表示静音（无深度数据或扫描停止）。
typedef MultiAudioCallback = void Function(List<AudioParams> sources);

/// 扫描位置回调类型
typedef ScanPositionCallback = void Function(double position);

/// 扫描引擎
///
/// 协调深度图分析和多声源音频参数生成。
class ScanEngine {
  // ==================== 配置 ====================

  /// 空间声源数量（将画面分为8个水平区域）
  static const int _numBands = 8;

  // ==================== 状态 ====================

  /// 当前扫描位置（0.0=最左, 1.0=最右，仅用于UI显示）
  double _scanPosition = 0.0;
  double get scanPosition => _scanPosition;

  /// 是否正在运行
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// 最新的深度图
  DepthFrame? _currentDepthFrame;

  // ==================== 回调 ====================

  /// 多声源音频回调
  MultiAudioCallback? onMultiAudio;

  /// 扫描位置回调（用于UI更新扫描线位置）
  ScanPositionCallback? onScanPosition;

  // ==================== 定时器 ====================

  /// 扫描位置更新定时器
  Timer? _scanTimer;

  /// 视觉更新间隔（毫秒）- 50fps，扫描线平滑移动
  static const int _updateIntervalMs = 20;

  /// 音频更新间隔（tick数）- 每5个tick更新一次音频 = 100ms
  /// 10Hz的音频更新频率既保证了实时性，又避免了参数变化过快导致杂乱
  static const int _audioUpdateInterval = 5;

  /// 音频更新计数器
  int _audioUpdateCounter = 0;

  /// 构造函数
  ScanEngine();

  /// 开始扫描
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _scanPosition = 0.0;
    _audioUpdateCounter = 0;

    _scanTimer = Timer.periodic(
      const Duration(milliseconds: _updateIntervalMs),
      (_) => _tick(),
    );

    debugPrint('扫描引擎已启动（8声源模式）');
  }

  /// 停止扫描
  void stop() {
    _isRunning = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanPosition = 0.0;

    // 发送空列表表示静音
    onMultiAudio?.call([]);
    onScanPosition?.call(0.0);

    debugPrint('扫描引擎已停止');
  }

  /// 更新深度图
  ///
  /// [frame] 新的深度图
  void updateWithDepthFrame(DepthFrame frame) {
    _currentDepthFrame = frame;
  }

  /// 定时器回调
  ///
  /// 每次执行：
  ///   1. 推进扫描位置（50fps，用于UI显示）
  ///   2. 每5次执行一次音频更新（10Hz，分析8个区域）
  void _tick() {
    if (!_isRunning) return;

    final settings = SettingsService.instance;

    // 步骤1：推进扫描位置（每次tick都执行，保证UI平滑）
    final progress = _updateIntervalMs / 1000.0 / settings.scanPeriodSeconds;
    _scanPosition += progress;
    if (_scanPosition >= 1.0) {
      _scanPosition = _scanPosition % 1.0;
    }
    onScanPosition?.call(_scanPosition);

    // 步骤2：每5个tick更新一次音频参数（100ms间隔）
    _audioUpdateCounter++;
    if (_audioUpdateCounter < _audioUpdateInterval) return;
    _audioUpdateCounter = 0;

    // 检查深度数据是否可用
    if (_currentDepthFrame == null) {
      onMultiAudio?.call([]);
      return;
    }

    // 步骤3：分析8个区域，生成8个声源参数
    final sources = <AudioParams>[];
    for (int i = 0; i < _numBands; i++) {
      final obj = _extractBandObject(_currentDepthFrame!, i);
      final params = DepthToAudioMapper.mapObjectToAudio(obj);

      // 强制设置pan为区域中心位置，确保清晰的立体声分离
      // 区域0中心=0.0625（偏左），区域7中心=0.9375（偏右）
      sources.add(AudioParams(
        frequency: params.frequency,
        volume: params.volume,
        pan: (i + 0.5) / _numBands,
      ));
    }

    // 步骤4：通过回调输出8个声源参数
    onMultiAudio?.call(sources);
  }

  /// 提取指定区域的最近物体信息
  ///
  /// 将画面宽度分为_numBands个区域，每个区域覆盖一定范围的列。
  /// 在该区域内逐像素扫描，找到最近的物体（最小深度值）。
  ///
  /// 简化版：只找最小深度，不做面积计算，提高性能。
  /// 8个区域 × 单次遍历 = 快速 enough for 10Hz 更新。
  ///
  /// [frame] 深度图
  /// [bandIndex] 区域索引（0到_numBands-1，0=最左，7=最右）
  DetectedObject _extractBandObject(DepthFrame frame, int bandIndex) {
    // 计算区域列范围
    final bandWidth = frame.width ~/ _numBands;
    final startCol = bandIndex * bandWidth;
    final endCol = bandIndex == _numBands - 1
        ? frame.width // 最后一个区域包含剩余的列
        : (bandIndex + 1) * bandWidth;

    // 在该区域内寻找最近物体
    double minDepth = 1.0;
    int minRow = frame.height ~/ 2;

    for (int col = startCol; col < endCol; col++) {
      for (int row = 0; row < frame.height; row++) {
        final depth = frame.getDepth(col, row);
        if (depth < minDepth) {
          minDepth = depth;
          minRow = row;
        }
      }
    }

    // 区域中心位置（用于声道平衡）
    final bandCenter = (bandIndex + 0.5) / _numBands;

    return DetectedObject(
      depth: minDepth,
      horizontalPosition: bandCenter,
      verticalCenter: minRow / frame.height,
      areaRatio: 1.0,
    );
  }

  /// 释放资源
  void dispose() {
    stop();
  }
}
