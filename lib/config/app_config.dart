/// 全局配置文件
///
/// 定义APP所有可调参数的默认值。这些参数都可以在设置界面中修改，
/// 不需要改动代码。参数设计理念是让盲人用户能根据自身听觉习惯自定义。
///
/// 核心原理：摄像头画面 → AI深度估计 → 深度图 → 扫描线 → 立体声
/// 类似蝙蝠回声定位：近的物体声音大且尖锐（像硬币落地声），远的物体声音小且低沉
class AppConfig {
  // ==================== 摄像头参数 ====================

  /// 摄像头分辨率预设索引
  /// 0=低(240p), 1=中(480p), 2=高(720p)
  /// 分辨率越低处理越快但精度越低，盲人导航建议中等
  static const int cameraResolutionIndex = 1;

  /// 是否使用前置摄像头（false=后置摄像头，用于导航）
  static const bool useFrontCamera = false;

  // ==================== 深度估计参数 ====================

  /// 深度估计模型的输入尺寸（MiDaS small使用256x256）
  static const int modelInputSize = 256;

  /// 深度估计模型的文件名（放在 assets/models/ 目录下）
  static const String modelFileName = 'midas_small.tflite';

  /// 深度图缩放比例（用于减少计算量，1.0=原始尺寸，0.5=半尺寸）
  static const double depthMapScale = 0.5;

  /// 每秒处理帧数（处理频率）
  /// 5-10帧足够导航用，太高会卡顿，太低反应慢
  static const int processingFps = 8;

  // ==================== 扫描线参数 ====================

  /// 扫描模式
  /// 0=从左到右水平扫描（类似雷达扫描）
  /// 1=从上到下垂直扫描
  /// 2=从中心向外扩散扫描
  static const int scanMode = 0;

  /// 扫描一周的时间（秒）
  /// 3秒扫一圈意味着每3秒扫描线从左移到右
  /// 盲人可以在这个周期内听到整个场景
  static const double scanPeriodSeconds = 3.0;

  /// 扫描线宽度（占图像宽度的比例，0.05=5%）
  /// 扫描线越窄，定位越精确但声音越断续
  static const double scanLineWidth = 0.05;

  // ==================== 音频映射参数 ====================

  /// 音频采样率（Hz）
  /// 44100=CD音质，22050=够用且省性能
  static const int sampleRate = 22050;

  /// 最近距离对应的频率（Hz）
  /// 近处物体发出高音（像硬币掉落的清脆声）
  static const double minDistanceFrequency = 2000.0;

  /// 最远距离对应的频率（Hz）
  /// 远处物体发出低音（低沉的嗡嗡声）
  static const double maxDistanceFrequency = 200.0;

  /// 最近距离（米）- 小于此距离的物体按最近处理
  static const double minDistanceMeters = 0.5;

  /// 最远距离（米）- 超过此距离的物体不发声
  static const double maxDistanceMeters = 5.0;

  /// 最大音量（0.0-1.0）
  /// 近处物体的最大音量，建议不要太大保护听力
  static const double maxVolume = 0.7;

  /// 最小音量（0.0-1.0）
  /// 远处物体的最小可听音量
  static const double minVolume = 0.05;

  /// 立体声分离强度（0.0-1.0）
  /// 控制左右声道的分离程度，1.0=全分离（左物体只在左耳响）
  static const double stereoSeparation = 0.8;

  // ==================== 声音特征参数 ====================

  /// 声音类型
  /// 0=正弦波（纯净的嗡嗡声）
  /// 1=方波（电子蜂鸣声，类似硬币）
  /// 2=三角波（柔和的提示音）
  /// 3=噪点声（类似雨声，更自然）
  static const int soundType = 1;

  /// 是否启用包络（声音的渐入渐出）
  /// 开启后声音更自然，关闭后更敏锐
  static const bool enableEnvelope = true;

  /// 包络攻击时间（秒）- 声音从0到最大的时间
  static const double attackTime = 0.01;

  /// 包络释放时间（秒）- 声音从最大到0的时间
  static const double releaseTime = 0.08;

  // ==================== 检测过滤参数 ====================

  /// 最小物体面积占比（占画面比例）
  /// 小于此面积的物体不发声，避免噪点干扰
  static const double minObjectAreaRatio = 0.005;

  /// 深度变化阈值
  /// 相邻像素深度差超过此值认为是物体边界
  static const double depthEdgeThreshold = 0.15;

  // ==================== UI参数 ====================

  /// 是否显示摄像头预览画面
  /// 盲人不需要画面，关闭可省电；视力辅助者可开启
  static const bool showCameraPreview = true;

  /// 是否显示深度图可视化
  static const bool showDepthMap = true;

  /// 是否显示扫描线位置
  static const bool showScanLine = true;

  /// 是否在启动时自动开始扫描
  static const bool autoStartScanning = false;

  /// 构造函数私有化，防止实例化
  AppConfig._();
}
