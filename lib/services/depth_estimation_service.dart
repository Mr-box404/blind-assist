/// 深度估计服务
///
/// 使用TensorFlow Lite加载MiDaS深度估计模型，
/// 将摄像头采集的灰度图像转换为深度图。
///
/// 核心流程：
///   1. 加载TFLite模型（assets/models/midas_small.tflite）
///   2. 将摄像头灰度图缩放到256x256
///   3. 转为float32并归一化到0-1，复制为RGB三通道
///   4. 运行AI推理，得到深度图
///   5. 归一化深度值（0.0=最近, 1.0=最远）
///
/// MiDaS模型输出的深度值：值越大=越近
/// 我们归一化后统一为：0.0=最近, 1.0=最远
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../config/app_config.dart';
import '../models/depth_data.dart';
import 'camera_service.dart';

/// 深度估计服务（单例模式）
class DepthEstimationService {
  // ==================== 单例实现 ====================

  /// 单例实例
  static final DepthEstimationService instance = DepthEstimationService._();

  /// 私有构造函数
  DepthEstimationService._();

  // ==================== 模型相关 ====================

  /// TFLite解释器，用于运行AI推理
  Interpreter? _interpreter;

  /// 模型输入尺寸（MiDaS small = 256）
  int _inputSize = AppConfig.modelInputSize;

  /// 模型是否已加载
  bool get isModelLoaded => _interpreter != null;

  // ==================== 模型加载 ====================

  /// 加载深度估计模型
  ///
  /// 从assets目录加载TFLite模型文件。
  /// 模型文件路径：assets/models/midas_small.tflite
  ///
  /// 返回true表示加载成功
  Future<bool> loadModel() async {
    try {
      // 从assets加载模型文件
      _interpreter = await Interpreter.fromAsset(
        'models/${AppConfig.modelFileName}',
      );

      // 获取模型输入张量的形状，确定输入尺寸
      // MiDaS输入形状: [1, 256, 256, 3] → 取第1维作为尺寸
      final inputShape = _interpreter!.getInputTensor(0).shape;
      if (inputShape.length >= 2) {
        _inputSize = inputShape[1];
      }

      debugPrint('深度估计模型加载成功，输入尺寸: $_inputSize x $_inputSize');
      return true;
    } catch (e) {
      debugPrint('模型加载失败: $e');
      debugPrint('请确保模型文件 ${AppConfig.modelFileName} 已放在 assets/models/ 目录下');
      return false;
    }
  }

  // ==================== 深度估计 ====================

  /// 对一帧摄像头图像进行深度估计
  ///
  /// [cameraFrame] 摄像头采集的灰度图像
  /// 返回深度图（DepthFrame），深度值0.0=最近, 1.0=最远
  /// 如果模型未加载或推理失败，返回null
  Future<DepthFrame?> estimateDepth(CameraFrame cameraFrame) async {
    if (_interpreter == null) {
      debugPrint('模型未加载，无法进行深度估计');
      return null;
    }

    try {
      // 步骤1：将灰度图缩放到模型输入尺寸（256x256）
      final resizedGray = _resizeGrayscale(
        cameraFrame.grayData,
        cameraFrame.width,
        cameraFrame.height,
        _inputSize,
        _inputSize,
      );

      // 步骤2：将灰度数据转为float32并归一化到0-1，复制为RGB三通道
      // 模型输入形状: [1, 256, 256, 3]
      final inputBuffer = _prepareInput(resizedGray);

      // 步骤3：准备输出缓冲区
      // 模型输出形状: [1, 256, 256, 1]
      final outputBuffer = Float32List(1 * _inputSize * _inputSize * 1);

      // 步骤4：运行AI推理
      // input和output需要包装成适合TFLite的格式
      final input = inputBuffer.reshape([1, _inputSize, _inputSize, 3]);
      final output = outputBuffer.reshape([1, _inputSize, _inputSize, 1]);

      _interpreter!.run(input, output);

      // 步骤5：处理输出，归一化深度值到0-1
      final depths = _normalizeDepths(outputBuffer);

      return DepthFrame(
        depths: depths,
        width: _inputSize,
        height: _inputSize,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('深度估计失败: $e');
      return null;
    }
  }

  /// 准备模型输入
  ///
  /// 将灰度数据转为float32数组，归一化到0-1，并复制为RGB三通道。
  ///
  /// [grayData] 缩放后的灰度数据（_inputSize x _inputSize）
  /// 返回扁平化的float32数组，形状为 [1, _inputSize, _inputSize, 3]
  Float32List _prepareInput(Uint8List grayData) {
    final totalPixels = _inputSize * _inputSize;
    final input = Float32List(totalPixels * 3);

    for (int i = 0; i < totalPixels; i++) {
      // 归一化到0-1
      final value = grayData[i] / 255.0;
      // 复制为RGB三通道（灰度图R=G=B）
      input[i * 3] = value; // R通道
      input[i * 3 + 1] = value; // G通道
      input[i * 3 + 2] = value; // B通道
    }

    return input;
  }

  /// 归一化深度值
  ///
  /// MiDaS模型输出的深度值：值越大=越近，值越小=越远
  /// 我们需要统一为：0.0=最近, 1.0=最远
  /// 因此需要反转并归一化。
  ///
  /// [outputBuffer] 模型原始输出
  /// 返回归一化后的深度值列表
  List<double> _normalizeDepths(Float32List outputBuffer) {
    final totalPixels = _inputSize * _inputSize;
    final depths = List<double>.filled(totalPixels, 0.0);

    // 步骤1：找到输出中的最大值和最小值
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;

    for (int i = 0; i < totalPixels; i++) {
      final v = outputBuffer[i];
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }

    // 步骤2：归一化并反转
    // MiDaS输出: 大值=近, 小值=远
    // 我们要: 0.0=近, 1.0=远
    // 所以: normalized = 1.0 - (value - min) / (max - min)
    final range = maxVal - minVal;
    if (range < 0.0001) {
      // 如果所有深度值相同（如纯色画面），全部设为最远
      for (int i = 0; i < totalPixels; i++) {
        depths[i] = 1.0;
      }
    } else {
      for (int i = 0; i < totalPixels; i++) {
        // 归一化到0-1并反转
        final normalized = 1.0 - (outputBuffer[i] - minVal) / range;
        depths[i] = normalized.clamp(0.0, 1.0);
      }
    }

    return depths;
  }

  // ==================== 图像缩放 ====================

  /// 缩放灰度图像（双线性插值）
  ///
  /// 将原始灰度图缩放到目标尺寸。
  /// 使用双线性插值保证缩放质量。
  ///
  /// [srcData] 原始灰度数据
  /// [srcWidth] 原始宽度
  /// [srcHeight] 原始高度
  /// [dstWidth] 目标宽度
  /// [dstHeight] 目标高度
  /// 返回缩放后的灰度数据
  Uint8List _resizeGrayscale(
    Uint8List srcData,
    int srcWidth,
    int srcHeight,
    int dstWidth,
    int dstHeight,
  ) {
    final dstData = Uint8List(dstWidth * dstHeight);

    // 计算缩放比例
    final xRatio = (srcWidth - 1) / dstWidth;
    final yRatio = (srcHeight - 1) / dstHeight;

    for (int dstY = 0; dstY < dstHeight; dstY++) {
      for (int dstX = 0; dstX < dstWidth; dstX++) {
        // 计算源图像中的浮点坐标
        final srcX = dstX * xRatio;
        final srcY = dstY * yRatio;

        // 取整数坐标
        final x0 = srcX.floor();
        final y0 = srcY.floor();
        final x1 = (x0 + 1).clamp(0, srcWidth - 1);
        final y1 = (y0 + 1).clamp(0, srcHeight - 1);

        // 小数部分（插值权重）
        final dx = srcX - x0;
        final dy = srcY - y0;

        // 四个相邻像素的值
        final p00 = srcData[y0 * srcWidth + x0].toDouble();
        final p01 = srcData[y0 * srcWidth + x1].toDouble();
        final p10 = srcData[y1 * srcWidth + x0].toDouble();
        final p11 = srcData[y1 * srcWidth + x1].toDouble();

        // 双线性插值
        final value = p00 * (1 - dx) * (1 - dy) +
            p01 * dx * (1 - dy) +
            p10 * (1 - dx) * dy +
            p11 * dx * dy;

        dstData[dstY * dstWidth + dstX] = value.round().clamp(0, 255);
      }
    }

    return dstData;
  }

  // ==================== 释放资源 ====================

  /// 释放模型资源
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
