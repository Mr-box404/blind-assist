/// 主界面
///
/// APP的核心交互页面，整合所有功能：
///   1. 摄像头实时预览
///   2. 深度图可视化（热力图）
///   3. 扫描线显示
///   4. 开始/停止扫描控制
///   5. 导航到设置界面
///
/// 布局结构：
///   ┌─────────────────────────┐
///   │      状态栏             │
///   ├──────────┬──────────────┤
///   │ 摄像头   │   深度图     │
///   │ 预览     │  (热力图)    │
///   │          │   扫描线     │
///   ├──────────┴──────────────┤
///   │      控制按钮区          │
///   └─────────────────────────┘
library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../engine/scan_engine.dart';
import '../models/depth_data.dart';
import '../services/camera_service.dart';
import '../services/depth_estimation_service.dart';
import '../services/settings_service.dart';
import '../services/spatial_audio_service.dart';
import '../widgets/depth_view_widget.dart';

/// 主界面组件
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// 主界面状态
class _HomeScreenState extends State<HomeScreen> {
  // ==================== 服务实例 ====================

  /// 摄像头服务
  final CameraService _cameraService = CameraService.instance;

  /// 深度估计服务
  final DepthEstimationService _depthService = DepthEstimationService.instance;

  /// 空间音频服务
  final SpatialAudioService _audioService = SpatialAudioService.instance;

  /// 设置服务
  final SettingsService _settings = SettingsService.instance;

  /// 扫描引擎
  final ScanEngine _scanEngine = ScanEngine();

  // ==================== 状态变量 ====================

  /// 是否正在初始化
  bool _isInitializing = false;

  /// 系统是否就绪（摄像头+模型+音频全部初始化完成）
  bool _isReady = false;

  /// 是否正在扫描
  bool _isScanning = false;

  /// 状态消息
  String _statusMessage = '点击"开始"按钮启动系统';

  /// 当前深度图（用于UI可视化）
  DepthFrame? _currentDepthFrame;

  /// 当前扫描位置（0.0-1.0）
  double _scanPosition = 0.0;

  // ==================== 生命周期 ====================

  @override
  void initState() {
    super.initState();
    _setupScanEngineCallbacks();
  }

  @override
  void dispose() {
    _stopScanning();
    _scanEngine.dispose();
    _depthService.dispose();
    _cameraService.dispose();
    _audioService.dispose();
    super.dispose();
  }

  /// 设置扫描引擎的回调函数
  ///
  /// 扫描引擎通过回调输出：
  ///   1. 音频参数 → 更新空间音频服务
  ///   2. 扫描位置 → 更新UI显示
  void _setupScanEngineCallbacks() {
    _scanEngine.onMultiAudio = (sources) {
      // 收到8个声源的音频参数，更新音频服务
      _audioService.updateMultiSourceAudio(sources);
    };

    _scanEngine.onScanPosition = (position) {
      // 收到扫描位置更新，刷新UI
      if (mounted) {
        setState(() {
          _scanPosition = position;
        });
      }
    };
  }

  // ==================== 初始化系统 ====================

  /// 初始化所有服务
  ///
  /// 执行步骤：
  ///   1. 初始化摄像头
  ///   2. 加载AI深度估计模型
  ///   3. 初始化音频引擎
  ///   4. 启动摄像头图像流
  ///   5. 标记系统就绪
  Future<void> _initializeSystem() async {
    setState(() {
      _isInitializing = true;
      _statusMessage = '正在初始化摄像头...';
    });

    // 步骤1：初始化摄像头
    final cameraOk = await _cameraService.initialize();
    if (!cameraOk) {
      setState(() {
        _isInitializing = false;
        _statusMessage = '摄像头初始化失败，请检查权限';
      });
      return;
    }

    // 步骤2：加载AI模型
    setState(() {
      _statusMessage = '正在加载AI深度估计模型...';
    });
    final modelOk = await _depthService.loadModel();
    if (!modelOk) {
      setState(() {
        _isInitializing = false;
        _statusMessage = 'AI模型加载失败，请确保模型文件已放置';
      });
      return;
    }

    // 步骤3：初始化音频引擎
    setState(() {
      _statusMessage = '正在初始化音频引擎...';
    });
    final audioOk = await _audioService.initialize();
    if (!audioOk) {
      setState(() {
        _isInitializing = false;
        _statusMessage = '音频引擎初始化失败';
      });
      return;
    }

    // 步骤4：启动摄像头图像流
    setState(() {
      _statusMessage = '正在启动图像流...';
    });
    final streamOk = await _cameraService.startImageStream(_onCameraFrame);
    if (!streamOk) {
      setState(() {
        _isInitializing = false;
        _statusMessage = '图像流启动失败';
      });
      return;
    }

    // 步骤5：系统就绪
    setState(() {
      _isInitializing = false;
      _isReady = true;
      _statusMessage = '系统就绪，点击"开始扫描"启动声音导航';
    });

    // 如果设置中允许自动开始扫描
    if (_settings.autoStartScanning) {
      _startScanning();
    }
  }

  /// 摄像头帧回调
  ///
  /// 每收到一帧摄像头图像时调用。
  /// 执行深度估计，更新深度图和扫描引擎。
  ///
  /// [frame] 摄像头采集的灰度图像帧
  void _onCameraFrame(CameraFrame frame) {
    // 异步执行深度估计，避免阻塞图像流
    _depthService.estimateDepth(frame).then((depthFrame) {
      if (depthFrame != null && mounted) {
        setState(() {
          _currentDepthFrame = depthFrame;
        });
        // 更新扫描引擎的深度图
        _scanEngine.updateWithDepthFrame(depthFrame);
      }
    });
  }

  // ==================== 扫描控制 ====================

  /// 开始扫描
  ///
  /// 启动音频播放和扫描引擎。
  Future<void> _startScanning() async {
    if (!_isReady || _isScanning) return;

    // 启动音频播放
    await _audioService.start();

    // 启动扫描引擎
    _scanEngine.start();

    setState(() {
      _isScanning = true;
      _statusMessage = '扫描中...通过耳机感知周围环境';
    });
  }

  /// 停止扫描
  ///
  /// 停止扫描引擎和音频播放。
  Future<void> _stopScanning() async {
    _scanEngine.stop();
    await _audioService.stop();

    if (mounted) {
      setState(() {
        _isScanning = false;
        _statusMessage = _isReady ? '已停止，点击"开始扫描"重新启动' : '系统未就绪';
      });
    }
  }

  // ==================== UI构建 ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('盲人辅助导航'),
        actions: [
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildControlBar(),
    );
  }

  /// 构建主体内容
  Widget _buildBody() {
    return Column(
      children: [
        // 状态栏
        _buildStatusBar(),

        // 预览区域（摄像头 + 深度图）
        Expanded(
          child: _buildPreviewArea(),
        ),
      ],
    );
  }

  /// 构建状态栏
  Widget _buildStatusBar() {
    // 根据状态选择颜色
    Color statusColor;
    if (_isScanning) {
      statusColor = Colors.green;
    } else if (_isReady) {
      statusColor = Colors.blue;
    } else if (_isInitializing) {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.grey;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: statusColor.withOpacity(0.15),
      child: Row(
        children: [
          // 状态指示灯
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // 状态文字
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: statusColor,
                fontSize: 14,
              ),
            ),
          ),
          // 初始化中显示进度指示器
          if (_isInitializing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  /// 构建预览区域
  Widget _buildPreviewArea() {
    final settings = _settings;

    // 如果系统未就绪，显示欢迎页面
    if (!_isReady) {
      return _buildWelcomePage();
    }

    // 根据设置决定显示哪些内容
    final showCamera = settings.showCameraPreview;
    final showDepth = settings.showDepthMap;

    if (!showCamera && !showDepth) {
      return const Center(
        child: Text(
          '预览已关闭\n请在设置中开启',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    // 只显示摄像头
    if (showCamera && !showDepth) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: _buildCameraPreview(),
      );
    }

    // 只显示深度图
    if (!showCamera && showDepth) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: _buildDepthView(),
      );
    }

    // 同时显示摄像头和深度图（左右排列）
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(child: _buildCameraPreview()),
          const SizedBox(width: 8),
          Expanded(child: _buildDepthView()),
        ],
      ),
    );
  }

  /// 构建欢迎页面（系统未就绪时显示）
  Widget _buildWelcomePage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标
            const Icon(
              Icons.hearing,
              size: 80,
              color: Colors.green,
            ),
            const SizedBox(height: 24),
            // 标题
            const Text(
              '盲人辅助导航',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // 说明
            const Text(
              '通过手机摄像头拍摄周围环境，\n'
              'AI分析距离并生成立体声，\n'
              '帮助您通过耳机感知障碍物。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            // 使用说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '使用方法：',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text('1. 佩戴立体声耳机'),
                  Text('2. 手机竖直握持，摄像头朝前'),
                  Text('3. 点击下方"开始"按钮'),
                  Text('4. 通过声音感知周围障碍物'),
                  SizedBox(height: 8),
                  Text(
                    '声音含义：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('• 高音+大声 = 近处障碍物（注意！）'),
                  Text('• 低音+小声 = 远处物体（安全）'),
                  Text('• 左耳响 = 障碍物在左侧'),
                  Text('• 右耳响 = 障碍物在右侧'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建摄像头预览
  Widget _buildCameraPreview() {
    final controller = _cameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('摄像头未就绪'));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CameraPreview(controller),
    );
  }

  /// 构建深度图视图
  Widget _buildDepthView() {
    return Column(
      children: [
        // 深度图标题
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text(
            '深度图（红=近, 蓝=远）',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
        // 深度图
        Expanded(
          child: DepthViewWidget(
            depthFrame: _currentDepthFrame,
            scanPosition: _scanPosition,
            showScanLine: _settings.showScanLine,
          ),
        ),
      ],
    );
  }

  /// 构建底部控制栏
  Widget _buildControlBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 开始/停止按钮
            if (!_isReady)
              ElevatedButton.icon(
                onPressed: _isInitializing ? null : _initializeSystem,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('开始'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              )
            else if (_isScanning)
              ElevatedButton.icon(
                onPressed: _stopScanning,
                icon: const Icon(Icons.stop),
                label: const Text('停止扫描'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _startScanning,
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始扫描'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),

            // 设置按钮
            TextButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/settings');
              },
              icon: const Icon(Icons.tune),
              label: const Text('设置'),
            ),
          ],
        ),
      ),
    );
  }
}
