/// 深度数据模型
///
/// 存储AI深度估计的结果，以及扫描线处理时提取的物体信息。
/// 深度值的范围是0.0到1.0：
///   0.0 = 最近（离镜头最近）
///   1.0 = 最远（离镜头最远）
/// 这些值会映射为声音的频率和音量。
library;

/// 单帧深度图数据
///
/// 包含整帧图像的深度信息，以及图像的宽高。
/// 深度数据按一维数组存储，索引 = y * width + x
class DepthFrame {
  /// 深度值数组（0.0=最近, 1.0=最远）
  final List<double> depths;

  /// 图像宽度（像素）
  final int width;

  /// 图像高度（像素）
  final int height;

  /// 此帧的时间戳（毫秒）
  final int timestamp;

  /// 构造函数
  DepthFrame({
    required this.depths,
    required this.width,
    required this.height,
    required this.timestamp,
  });

  /// 获取指定坐标的深度值
  ///
  /// [x] 水平坐标（0到width-1）
  /// [y] 垂直坐标（0到height-1）
  /// 返回深度值（0.0=最近, 1.0=最远）
  double getDepth(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return 1.0;
    return depths[y * width + x];
  }

  /// 获取指定列的平均深度值
  ///
  /// 用于扫描线：当扫描线移动到某一列时，
  /// 计算该列所有像素的平均深度，作为该方向的声音参数。
  ///
  /// [column] 列索引
  /// [rowStart] 起始行（默认0）
  /// [rowEnd] 结束行（默认height）
  double getColumnAverageDepth(int column, {int? rowStart, int? rowEnd}) {
    final start = rowStart ?? 0;
    final end = rowEnd ?? height;
    double sum = 0;
    int count = 0;
    for (int y = start; y < end; y++) {
      sum += getDepth(column, y);
      count++;
    }
    return count > 0 ? sum / count : 1.0;
  }

  /// 获取指定列中最近的物体深度值
  ///
  /// 与平均深度不同，这里找该列中最近的物体（最小深度值），
  /// 这样扫描线经过时能突出最近障碍物的声音。
  ///
  /// [column] 列索引
  double getColumnNearestDepth(int column) {
    double minDepth = 1.0;
    for (int y = 0; y < height; y++) {
      final d = getDepth(column, y);
      if (d < minDepth) minDepth = d;
    }
    return minDepth;
  }
}

/// 扫描线检测结果
///
/// 当扫描线移动到某个位置时，提取该位置所有物体的信息。
/// 每个物体会生成一个独立的声音信号。
class ScanResult {
  /// 扫描位置（0.0=最左, 1.0=最右）
  final double position;

  /// 该位置检测到的物体列表
  final List<DetectedObject> objects;

  /// 时间戳（毫秒）
  final int timestamp;

  /// 构造函数
  ScanResult({
    required this.position,
    required this.objects,
    required this.timestamp,
  });
}

/// 检测到的单个物体
///
/// 一个物体由其在画面中的垂直范围和深度范围定义。
/// 这些信息决定声音的特征：
///   - depth → 频率和音量（近=高音+大声）
///   - verticalCenter → 音色（高低音调差异）
///   - horizontalPosition → 左右声道平衡（立体声定位）
class DetectedObject {
  /// 物体的平均深度值（0.0=最近, 1.0=最远）
  final double depth;

  /// 物体在画面中的水平位置（0.0=最左, 1.0=最右）
  /// 决定左右声道的音量平衡
  final double horizontalPosition;

  /// 物体在画面中的垂直中心位置（0.0=顶部, 1.0=底部）
  /// 顶部物体和底部物体可以有不同的音色特征
  final double verticalCenter;

  /// 物体的相对面积（占画面的比例）
  /// 大物体声音更"厚"，小物体声音更"尖"
  final double areaRatio;

  /// 构造函数
  DetectedObject({
    required this.depth,
    required this.horizontalPosition,
    required this.verticalCenter,
    required this.areaRatio,
  });
}
