/// 设置持久化服务
///
/// 管理所有用户可调参数的存储和读取。
/// 用户在设置界面修改的参数会自动保存到本地（SharedPreferences），
/// 下次启动时自动恢复。
///
/// 设计理念：用户是编程新手，所有参数通过UI调节，不需要改代码。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// 用户设置服务（单例模式）
///
/// 继承ChangeNotifier，当设置变化时通知UI更新。
/// 使用方法：
///   1. 启动时调用 SettingsService.instance.load()
///   2. 读取参数：SettingsService.instance.scanPeriod
///   3. 修改参数：SettingsService.instance.setScanPeriod(4.0)
///   4. UI监听变化：SettingsService.instance.addListener(() {...})
class SettingsService extends ChangeNotifier {
  // ==================== 单例实现 ====================

  /// 单例实例
  static final SettingsService instance = SettingsService._();

  /// 私有构造函数
  SettingsService._();

  // ==================== SharedPreferences 实例 ====================

  /// SharedPreferences实例，用于读写本地存储
  SharedPreferences? _prefs;

  // ==================== 运行时参数缓存 ====================
  // 这些值在load()后从本地读取，在set方法中自动保存

  /// 摄像头分辨率索引
  int _cameraResolutionIndex = AppConfig.cameraResolutionIndex;

  /// 是否使用前置摄像头
  bool _useFrontCamera = AppConfig.useFrontCamera;

  /// 深度图缩放比例
  double _depthMapScale = AppConfig.depthMapScale;

  /// 每秒处理帧数
  int _processingFps = AppConfig.processingFps;

  /// 扫描模式
  int _scanMode = AppConfig.scanMode;

  /// 扫描周期（秒）
  double _scanPeriodSeconds = AppConfig.scanPeriodSeconds;

  /// 扫描线宽度
  double _scanLineWidth = AppConfig.scanLineWidth;

  /// 采样率
  int _sampleRate = AppConfig.sampleRate;

  /// 最近距离频率
  double _minDistanceFrequency = AppConfig.minDistanceFrequency;

  /// 最远距离频率
  double _maxDistanceFrequency = AppConfig.maxDistanceFrequency;

  /// 最近距离（米）
  double _minDistanceMeters = AppConfig.minDistanceMeters;

  /// 最远距离（米）
  double _maxDistanceMeters = AppConfig.maxDistanceMeters;

  /// 最大音量
  double _maxVolume = AppConfig.maxVolume;

  /// 最小音量
  double _minVolume = AppConfig.minVolume;

  /// 立体声分离强度
  double _stereoSeparation = AppConfig.stereoSeparation;

  /// 声音类型
  int _soundType = AppConfig.soundType;

  /// 是否启用包络
  bool _enableEnvelope = AppConfig.enableEnvelope;

  /// 攻击时间
  double _attackTime = AppConfig.attackTime;

  /// 释放时间
  double _releaseTime = AppConfig.releaseTime;

  /// 最小物体面积占比
  double _minObjectAreaRatio = AppConfig.minObjectAreaRatio;

  /// 深度边界阈值
  double _depthEdgeThreshold = AppConfig.depthEdgeThreshold;

  /// 是否显示摄像头预览
  bool _showCameraPreview = AppConfig.showCameraPreview;

  /// 是否显示深度图
  bool _showDepthMap = AppConfig.showDepthMap;

  /// 是否显示扫描线
  bool _showScanLine = AppConfig.showScanLine;

  /// 是否自动开始扫描
  bool _autoStartScanning = AppConfig.autoStartScanning;

  // ==================== Getter 方法 ====================
  // 每个参数都有对应的getter，返回当前值

  int get cameraResolutionIndex => _cameraResolutionIndex;
  bool get useFrontCamera => _useFrontCamera;
  double get depthMapScale => _depthMapScale;
  int get processingFps => _processingFps;
  int get scanMode => _scanMode;
  double get scanPeriodSeconds => _scanPeriodSeconds;
  double get scanLineWidth => _scanLineWidth;
  int get sampleRate => _sampleRate;
  double get minDistanceFrequency => _minDistanceFrequency;
  double get maxDistanceFrequency => _maxDistanceFrequency;
  double get minDistanceMeters => _minDistanceMeters;
  double get maxDistanceMeters => _maxDistanceMeters;
  double get maxVolume => _maxVolume;
  double get minVolume => _minVolume;
  double get stereoSeparation => _stereoSeparation;
  int get soundType => _soundType;
  bool get enableEnvelope => _enableEnvelope;
  double get attackTime => _attackTime;
  double get releaseTime => _releaseTime;
  double get minObjectAreaRatio => _minObjectAreaRatio;
  double get depthEdgeThreshold => _depthEdgeThreshold;
  bool get showCameraPreview => _showCameraPreview;
  bool get showDepthMap => _showDepthMap;
  bool get showScanLine => _showScanLine;
  bool get autoStartScanning => _autoStartScanning;

  // ==================== 从本地加载设置 ====================

  /// 从SharedPreferences加载所有保存的设置
  ///
  /// 如果某个参数没有保存过，则使用AppConfig中的默认值。
  /// 此方法应在main()中调用，确保UI启动前设置已就绪。
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    // 逐个读取参数，如果没有则保持默认值
    _cameraResolutionIndex =
        _prefs?.getInt('cameraResolutionIndex') ?? _cameraResolutionIndex;
    _useFrontCamera =
        _prefs?.getBool('useFrontCamera') ?? _useFrontCamera;
    _depthMapScale =
        _prefs?.getDouble('depthMapScale') ?? _depthMapScale;
    _processingFps =
        _prefs?.getInt('processingFps') ?? _processingFps;
    _scanMode = _prefs?.getInt('scanMode') ?? _scanMode;
    _scanPeriodSeconds =
        _prefs?.getDouble('scanPeriodSeconds') ?? _scanPeriodSeconds;
    _scanLineWidth =
        _prefs?.getDouble('scanLineWidth') ?? _scanLineWidth;
    _sampleRate = _prefs?.getInt('sampleRate') ?? _sampleRate;
    _minDistanceFrequency =
        _prefs?.getDouble('minDistanceFrequency') ?? _minDistanceFrequency;
    _maxDistanceFrequency =
        _prefs?.getDouble('maxDistanceFrequency') ?? _maxDistanceFrequency;
    _minDistanceMeters =
        _prefs?.getDouble('minDistanceMeters') ?? _minDistanceMeters;
    _maxDistanceMeters =
        _prefs?.getDouble('maxDistanceMeters') ?? _maxDistanceMeters;
    _maxVolume = _prefs?.getDouble('maxVolume') ?? _maxVolume;
    _minVolume = _prefs?.getDouble('minVolume') ?? _minVolume;
    _stereoSeparation =
        _prefs?.getDouble('stereoSeparation') ?? _stereoSeparation;
    _soundType = _prefs?.getInt('soundType') ?? _soundType;
    _enableEnvelope =
        _prefs?.getBool('enableEnvelope') ?? _enableEnvelope;
    _attackTime = _prefs?.getDouble('attackTime') ?? _attackTime;
    _releaseTime = _prefs?.getDouble('releaseTime') ?? _releaseTime;
    _minObjectAreaRatio =
        _prefs?.getDouble('minObjectAreaRatio') ?? _minObjectAreaRatio;
    _depthEdgeThreshold =
        _prefs?.getDouble('depthEdgeThreshold') ?? _depthEdgeThreshold;
    _showCameraPreview =
        _prefs?.getBool('showCameraPreview') ?? _showCameraPreview;
    _showDepthMap = _prefs?.getBool('showDepthMap') ?? _showDepthMap;
    _showScanLine = _prefs?.getBool('showScanLine') ?? _showScanLine;
    _autoStartScanning =
        _prefs?.getBool('autoStartScanning') ?? _autoStartScanning;

    debugPrint('设置加载完成');
    notifyListeners();
  }

  // ==================== Setter 方法 ====================
  // 每个setter都会自动保存到本地并通知UI更新

  /// 设置摄像头分辨率索引
  void setCameraResolutionIndex(int value) {
    _cameraResolutionIndex = value;
    _prefs?.setInt('cameraResolutionIndex', value);
    notifyListeners();
  }

  /// 设置是否使用前置摄像头
  void setUseFrontCamera(bool value) {
    _useFrontCamera = value;
    _prefs?.setBool('useFrontCamera', value);
    notifyListeners();
  }

  /// 设置深度图缩放比例
  void setDepthMapScale(double value) {
    _depthMapScale = value;
    _prefs?.setDouble('depthMapScale', value);
    notifyListeners();
  }

  /// 设置处理帧率
  void setProcessingFps(int value) {
    _processingFps = value;
    _prefs?.setInt('processingFps', value);
    notifyListeners();
  }

  /// 设置扫描模式
  void setScanMode(int value) {
    _scanMode = value;
    _prefs?.setInt('scanMode', value);
    notifyListeners();
  }

  /// 设置扫描周期
  void setScanPeriodSeconds(double value) {
    _scanPeriodSeconds = value;
    _prefs?.setDouble('scanPeriodSeconds', value);
    notifyListeners();
  }

  /// 设置扫描线宽度
  void setScanLineWidth(double value) {
    _scanLineWidth = value;
    _prefs?.setDouble('scanLineWidth', value);
    notifyListeners();
  }

  /// 设置采样率
  void setSampleRate(int value) {
    _sampleRate = value;
    _prefs?.setInt('sampleRate', value);
    notifyListeners();
  }

  /// 设置最近距离频率
  void setMinDistanceFrequency(double value) {
    _minDistanceFrequency = value;
    _prefs?.setDouble('minDistanceFrequency', value);
    notifyListeners();
  }

  /// 设置最远距离频率
  void setMaxDistanceFrequency(double value) {
    _maxDistanceFrequency = value;
    _prefs?.setDouble('maxDistanceFrequency', value);
    notifyListeners();
  }

  /// 设置最近距离
  void setMinDistanceMeters(double value) {
    _minDistanceMeters = value;
    _prefs?.setDouble('minDistanceMeters', value);
    notifyListeners();
  }

  /// 设置最远距离
  void setMaxDistanceMeters(double value) {
    _maxDistanceMeters = value;
    _prefs?.setDouble('maxDistanceMeters', value);
    notifyListeners();
  }

  /// 设置最大音量
  void setMaxVolume(double value) {
    _maxVolume = value;
    _prefs?.setDouble('maxVolume', value);
    notifyListeners();
  }

  /// 设置最小音量
  void setMinVolume(double value) {
    _minVolume = value;
    _prefs?.setDouble('minVolume', value);
    notifyListeners();
  }

  /// 设置立体声分离强度
  void setStereoSeparation(double value) {
    _stereoSeparation = value;
    _prefs?.setDouble('stereoSeparation', value);
    notifyListeners();
  }

  /// 设置声音类型
  void setSoundType(int value) {
    _soundType = value;
    _prefs?.setInt('soundType', value);
    notifyListeners();
  }

  /// 设置是否启用包络
  void setEnableEnvelope(bool value) {
    _enableEnvelope = value;
    _prefs?.setBool('enableEnvelope', value);
    notifyListeners();
  }

  /// 设置攻击时间
  void setAttackTime(double value) {
    _attackTime = value;
    _prefs?.setDouble('attackTime', value);
    notifyListeners();
  }

  /// 设置释放时间
  void setReleaseTime(double value) {
    _releaseTime = value;
    _prefs?.setDouble('releaseTime', value);
    notifyListeners();
  }

  /// 设置最小物体面积占比
  void setMinObjectAreaRatio(double value) {
    _minObjectAreaRatio = value;
    _prefs?.setDouble('minObjectAreaRatio', value);
    notifyListeners();
  }

  /// 设置深度边界阈值
  void setDepthEdgeThreshold(double value) {
    _depthEdgeThreshold = value;
    _prefs?.setDouble('depthEdgeThreshold', value);
    notifyListeners();
  }

  /// 设置是否显示摄像头预览
  void setShowCameraPreview(bool value) {
    _showCameraPreview = value;
    _prefs?.setBool('showCameraPreview', value);
    notifyListeners();
  }

  /// 设置是否显示深度图
  void setShowDepthMap(bool value) {
    _showDepthMap = value;
    _prefs?.setBool('showDepthMap', value);
    notifyListeners();
  }

  /// 设置是否显示扫描线
  void setShowScanLine(bool value) {
    _showScanLine = value;
    _prefs?.setBool('showScanLine', value);
    notifyListeners();
  }

  /// 设置是否自动开始扫描
  void setAutoStartScanning(bool value) {
    _autoStartScanning = value;
    _prefs?.setBool('autoStartScanning', value);
    notifyListeners();
  }

  /// 重置所有设置为默认值
  ///
  /// 将所有参数恢复到AppConfig中定义的默认值。
  /// 用户可以在设置界面中点击"恢复默认"按钮调用此方法。
  Future<void> resetToDefaults() async {
    _cameraResolutionIndex = AppConfig.cameraResolutionIndex;
    _useFrontCamera = AppConfig.useFrontCamera;
    _depthMapScale = AppConfig.depthMapScale;
    _processingFps = AppConfig.processingFps;
    _scanMode = AppConfig.scanMode;
    _scanPeriodSeconds = AppConfig.scanPeriodSeconds;
    _scanLineWidth = AppConfig.scanLineWidth;
    _sampleRate = AppConfig.sampleRate;
    _minDistanceFrequency = AppConfig.minDistanceFrequency;
    _maxDistanceFrequency = AppConfig.maxDistanceFrequency;
    _minDistanceMeters = AppConfig.minDistanceMeters;
    _maxDistanceMeters = AppConfig.maxDistanceMeters;
    _maxVolume = AppConfig.maxVolume;
    _minVolume = AppConfig.minVolume;
    _stereoSeparation = AppConfig.stereoSeparation;
    _soundType = AppConfig.soundType;
    _enableEnvelope = AppConfig.enableEnvelope;
    _attackTime = AppConfig.attackTime;
    _releaseTime = AppConfig.releaseTime;
    _minObjectAreaRatio = AppConfig.minObjectAreaRatio;
    _depthEdgeThreshold = AppConfig.depthEdgeThreshold;
    _showCameraPreview = AppConfig.showCameraPreview;
    _showDepthMap = AppConfig.showDepthMap;
    _showScanLine = AppConfig.showScanLine;
    _autoStartScanning = AppConfig.autoStartScanning;

    // 清除所有保存的设置
    await _prefs?.clear();
    notifyListeners();
  }
}
