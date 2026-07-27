/// 摄像头服务
///
/// 管理手机摄像头的初始化、预览和图像流采集。
/// 核心职责：
///   1. 选择并打开后置摄像头
///   2. 启动实时图像流（CameraImage）
///   3. 将YUV420格式的图像数据转为可处理的格式
///   4. 按设定的帧率控制图像采集频率
///
/// 图像流回调中获取的CameraImage会传递给深度估计服务处理。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'settings_service.dart';

/// 摄像头服务（单例模式）
///
/// 使用方法：
///   1. 调用 initialize() 初始化摄像头
///   2. 调用 startImageStream() 开始采集
///   3. 通过 onFrame 回调接收图像数据
///   4. 使用完毕调用 dispose() 释放资源
/// 图像帧回调函数类型
/// 参数为转换后的灰度图像数据
typedef FrameCallback = void Function(CameraFrame frame);

class CameraService {
  // ==================== 单例实现 ====================

  /// 单例实例
  static final CameraService instance = CameraService._();

  /// 私有构造函数
  CameraService._();

  // ==================== 摄像头控制器 ====================

  /// Camera插件控制器，管理摄像头预览和图像流
  CameraController? _controller;

  /// 获取摄像头控制器（用于UI预览）
  CameraController? get controller => _controller;

  /// 是否已初始化
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  // ==================== 图像流回调 ====================

  /// 当前注册的帧回调
  FrameCallback? _onFrame;

  // ==================== 帧率控制 ====================

  /// 上一帧处理的时间戳（用于帧率控制）
  int _lastFrameTime = 0;

  /// 帧率控制间隔（毫秒），根据设置的FPS计算
  int _frameIntervalMs = 125; // 默认8fps → 125ms

  // ==================== 初始化方法 ====================

  /// 初始化摄像头
  ///
  /// 执行步骤：
  ///   1. 获取所有可用摄像头
  ///   2. 根据设置选择前置或后置摄像头
  ///   3. 创建CameraController并初始化
  ///   4. 设置分辨率
  ///
  /// 返回true表示初始化成功，false表示失败
  Future<bool> initialize() async {
    try {
      // 获取所有可用摄像头列表
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('未找到可用摄像头');
        return false;
      }

      // 根据设置选择摄像头
      final useFront = SettingsService.instance.useFrontCamera;
      CameraDescription? selectedCamera;

      for (final camera in cameras) {
        if (useFront && camera.lensDirection == CameraLensDirection.front) {
          selectedCamera = camera;
          break;
        }
        if (!useFront && camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      // 如果没找到指定方向的摄像头，使用第一个
      selectedCamera ??= cameras.first;

      // 根据设置确定分辨率
      final resolutionPreset = _getResolutionPreset(
        SettingsService.instance.cameraResolutionIndex,
      );

      // 创建摄像头控制器
      _controller = CameraController(
        selectedCamera,
        resolutionPreset,
        enableAudio: false, // 不需要录制音频
        imageFormatGroup: ImageFormatGroup.yuv420, // YUV420格式
      );

      // 初始化控制器
      await _controller!.initialize();

      // 更新帧率控制间隔
      _updateFrameInterval();

      debugPrint('摄像头初始化成功: ${selectedCamera.name}');
      return true;
    } catch (e) {
      debugPrint('摄像头初始化失败: $e');
      return false;
    }
  }

  /// 根据分辨率索引获取ResolutionPreset
  ///
  /// [index] 0=低, 1=中, 2=高
  ResolutionPreset _getResolutionPreset(int index) {
    switch (index) {
      case 0:
        return ResolutionPreset.low; // 240p
      case 1:
        return ResolutionPreset.medium; // 480p
      case 2:
        return ResolutionPreset.high; // 720p
      default:
        return ResolutionPreset.medium;
    }
  }

  /// 更新帧率控制间隔
  ///
  /// 根据用户设置的FPS计算两帧之间的最小时间间隔
  void _updateFrameInterval() {
    final fps = SettingsService.instance.processingFps;
    _frameIntervalMs = (1000 / fps).round();
  }

  // ==================== 图像流控制 ====================

  /// 开始图像流采集
  ///
  /// [onFrame] 每收到一帧图像时的回调函数
  /// 回调中收到的CameraFrame已转换为灰度数据，可直接用于深度估计
  Future<bool> startImageStream(FrameCallback onFrame) async {
    if (_controller == null || !isInitialized) {
      debugPrint('摄像头未初始化，无法开始图像流');
      return false;
    }

    _onFrame = onFrame;
    _updateFrameInterval();

    try {
      await _controller!.startImageStream(_handleCameraImage);
      debugPrint('图像流已启动');
      return true;
    } catch (e) {
      debugPrint('启动图像流失败: $e');
      return false;
    }
  }

  /// 停止图像流采集
  Future<void> stopImageStream() async {
    if (_controller == null) return;

    try {
      await _controller!.stopImageStream();
      debugPrint('图像流已停止');
    } catch (e) {
      debugPrint('停止图像流失败: $e');
    }

    _onFrame = null;
  }

  /// 摄像头图像回调处理
  ///
  /// 这是Camera插件每帧调用的回调。我们在这里：
  ///   1. 进行帧率控制（丢弃太近的帧）
  ///   2. 将YUV420图像转换为灰度数据
  ///   3. 调用用户注册的回调函数
  ///
  /// [image] Camera插件传来的原始图像数据
  void _handleCameraImage(CameraImage image) {
    // 帧率控制：检查距上一帧的时间间隔
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameTime < _frameIntervalMs) {
      return; // 距上一帧太近，丢弃此帧
    }
    _lastFrameTime = now;

    // 将YUV420转换为灰度图像
    final frame = _convertYuvToGrayscale(image);
    if (frame == null) return;

    // 调用用户注册的回调
    _onFrame?.call(frame);
  }

  /// 将YUV420格式的CameraImage转换为灰度图像
  ///
  /// YUV420格式中，Y通道（第0个plane）就是亮度信息，
  /// 直接提取Y通道即可得到灰度图像。
  ///
  /// [image] Camera插件的原始图像
  /// 返回转换后的CameraFrame，包含灰度数据和尺寸
  CameraFrame? _convertYuvToGrayscale(CameraImage image) {
    try {
      final width = image.width;
      final height = image.height;

      // YUV420的Y通道平面（亮度）
      final yPlane = image.planes[0];
      final yBytes = yPlane.bytes;

      // 创建灰度数据数组
      final grayData = Uint8List(width * height);

      // Y通道的行步长（可能大于width，因为内存对齐）
      final rowStride = yPlane.bytesPerRow;

      // 逐行复制Y通道数据
      for (int row = 0; row < height; row++) {
        final srcOffset = row * rowStride;
        final dstOffset = row * width;
        final rowLength = rowStride >= width ? width : rowStride;
        for (int col = 0; col < rowLength; col++) {
          grayData[dstOffset + col] = yBytes[srcOffset + col];
        }
      }

      return CameraFrame(
        grayData: grayData,
        width: width,
        height: height,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('YUV转灰度失败: $e');
      return null;
    }
  }

  // ==================== 释放资源 ====================

  /// 释放摄像头资源
  ///
  /// 在APP退出或不再使用摄像头时调用
  Future<void> dispose() async {
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }
}

/// 摄像头帧数据
///
/// 包含一帧灰度图像的数据和元信息。
/// 灰度值0=黑色，255=白色。
class CameraFrame {
  /// 灰度数据（每像素1字节，值0-255）
  final Uint8List grayData;

  /// 图像宽度（像素）
  final int width;

  /// 图像高度（像素）
  final int height;

  /// 时间戳（毫秒）
  final int timestamp;

  /// 构造函数
  CameraFrame({
    required this.grayData,
    required this.width,
    required this.height,
    required this.timestamp,
  });

  /// 获取指定坐标的灰度值
  ///
  /// [x] 水平坐标
  /// [y] 垂直坐标
  /// 返回0-255的灰度值
  int getPixel(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return 0;
    return grayData[y * width + x];
  }
}
