/// 深度图可视化组件
///
/// 将深度图数据以热力图方式可视化显示，并在上面绘制扫描线。
///
/// 颜色映射方案：
///   深度0.0（最近）→ 红色（危险，需要避让）
///   深度0.3 → 橙色（较近，注意）
///   深度0.5 → 黄色（中等距离）
///   深度0.7 → 青色（较远）
///   深度1.0（最远）→ 深蓝/黑色（安全）
///
/// 扫描线：一条垂直的白色亮线，表示当前扫描位置。
///
/// 性能优化：将深度图降采样到固定网格大小（48x48），
/// 在Canvas上绘制色块，避免逐像素绘制带来的性能问题。
library;

import 'package:flutter/material.dart';

import '../models/depth_data.dart';

/// 深度图可视化绘制器
///
/// 继承CustomPainter，负责将深度数据绘制到Canvas上。
/// 使用降采样方式绘制色块，保证渲染性能。
class DepthViewPainter extends CustomPainter {
  /// 深度图数据
  final DepthFrame? depthFrame;

  /// 当前扫描位置（0.0=最左, 1.0=最右）
  final double scanPosition;

  /// 是否显示扫描线
  final bool showScanLine;

  /// 降采样网格大小（画面被分成 grid x grid 个色块）
  static const int _gridSize = 48;

  /// 构造函数
  DepthViewPainter({
    required this.depthFrame,
    required this.scanPosition,
    required this.showScanLine,
  });

  /// 绘制方法
  @override
  void paint(Canvas canvas, Size size) {
    // 背景填充黑色
    final bgPaint = Paint()..color = Colors.black;
    canvas.drawRect(Offset.zero & size, bgPaint);

    if (depthFrame == null) {
      _drawPlaceholder(canvas, size);
      return;
    }

    // 绘制深度图
    _drawDepthMap(canvas, size);

    // 绘制扫描线
    if (showScanLine) {
      _drawScanLine(canvas, size);
    }
  }

  /// 绘制占位提示文字
  void _drawPlaceholder(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '等待深度数据...',
        style: TextStyle(color: Colors.white54, fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  /// 绘制深度图热力图
  ///
  /// 将深度图降采样到 _gridSize x _gridSize 的网格，
  /// 每个网格计算平均深度，绘制对应颜色的色块。
  void _drawDepthMap(Canvas canvas, Size size) {
    final frame = depthFrame!;
    final cellWidth = size.width / _gridSize;
    final cellHeight = size.height / _gridSize;

    final paint = Paint();

    for (int gy = 0; gy < _gridSize; gy++) {
      for (int gx = 0; gx < _gridSize; gx++) {
        // 计算该网格在深度图中的区域
        final srcX0 = (gx * frame.width / _gridSize).floor();
        final srcX1 = ((gx + 1) * frame.width / _gridSize).ceil();
        final srcY0 = (gy * frame.height / _gridSize).floor();
        final srcY1 = ((gy + 1) * frame.height / _gridSize).ceil();

        // 计算该区域的平均深度
        double sumDepth = 0;
        int count = 0;
        for (int y = srcY0; y < srcY1 && y < frame.height; y++) {
          for (int x = srcX0; x < srcX1 && x < frame.width; x++) {
            sumDepth += frame.getDepth(x, y);
            count++;
          }
        }
        final avgDepth = count > 0 ? sumDepth / count : 1.0;

        // 绘制色块
        paint.color = _depthToColor(avgDepth);
        canvas.drawRect(
          Rect.fromLTWH(
            gx * cellWidth,
            gy * cellHeight,
            cellWidth + 0.5, // +0.5 消除网格间隙
            cellHeight + 0.5,
          ),
          paint,
        );
      }
    }
  }

  /// 将深度值映射为颜色
  ///
  /// 使用热力图色彩方案：
  /// 0.0(近)→红色, 0.3→橙色, 0.5→黄色, 0.7→青色, 1.0(远)→深蓝
  ///
  /// [depth] 深度值（0.0=最近, 1.0=最远）
  /// 返回对应的Color
  Color _depthToColor(double depth) {
    final d = depth.clamp(0.0, 1.0);

    if (d < 0.3) {
      // 红色 → 橙色
      final t = d / 0.3;
      return Color.fromRGBO(255, (165 * t).round(), 0, 1.0);
    } else if (d < 0.5) {
      // 橙色 → 黄色
      final t = (d - 0.3) / 0.2;
      return Color.fromRGBO(255, (165 + (255 - 165) * t).round(), 0, 1.0);
    } else if (d < 0.7) {
      // 黄色 → 青色
      final t = (d - 0.5) / 0.2;
      return Color.fromRGBO(
        (255 * (1 - t)).round(),
        255,
        (255 * t).round(),
        1.0,
      );
    } else {
      // 青色 → 深蓝
      final t = (d - 0.7) / 0.3;
      return Color.fromRGBO(
        0,
        (255 * (1 - t * 0.7)).round(),
        (255 * (1 - t * 0.5)).round(),
        1.0,
      );
    }
  }

  /// 绘制扫描线
  void _drawScanLine(Canvas canvas, Size size) {
    final x = scanPosition * size.width;

    // 扫描线光晕效果（宽的半透明线）
    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 8.0;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), glowPaint);

    // 扫描线主体（窄的亮线）
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
  }

  /// 是否需要重绘
  @override
  bool shouldRepaint(covariant DepthViewPainter oldDelegate) {
    return oldDelegate.depthFrame != depthFrame ||
        oldDelegate.scanPosition != scanPosition ||
        oldDelegate.showScanLine != showScanLine;
  }
}

/// 深度图可视化Widget
///
/// 封装CustomPaint，显示深度图和扫描线。
class DepthViewWidget extends StatelessWidget {
  /// 深度图数据
  final DepthFrame? depthFrame;

  /// 当前扫描位置
  final double scanPosition;

  /// 是否显示扫描线
  final bool showScanLine;

  /// 构造函数
  const DepthViewWidget({
    super.key,
    required this.depthFrame,
    required this.scanPosition,
    required this.showScanLine,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        size: Size.infinite,
        painter: DepthViewPainter(
          depthFrame: depthFrame,
          scanPosition: scanPosition,
          showScanLine: showScanLine,
        ),
      ),
    );
  }
}
