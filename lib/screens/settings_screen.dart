/// 设置界面
///
/// 提供所有参数的可视化调节界面。
/// 用户不需要修改代码，所有参数都可以通过此界面调整。
///
/// 参数分组：
///   1. 摄像头设置 - 分辨率、前后置
///   2. 深度估计设置 - 处理帧率、缩放比例
///   3. 扫描线设置 - 扫描模式、周期、线宽
///   4. 音频映射设置 - 频率范围、音量、距离范围、立体声分离
///   5. 声音特征设置 - 波形类型、包络参数
///   6. 检测过滤设置 - 最小物体面积、深度阈值
///   7. 界面显示设置 - 预览/深度图/扫描线显示开关
library;

import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// 设置界面组件
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// 设置界面状态
class _SettingsScreenState extends State<SettingsScreen> {
  /// 设置服务实例
  final SettingsService _settings = SettingsService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('参数设置'),
        actions: [
          // 恢复默认按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '恢复默认',
            onPressed: _showResetDialog,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildCameraSection(),
              const SizedBox(height: 16),
              _buildDepthSection(),
              const SizedBox(height: 16),
              _buildScanSection(),
              const SizedBox(height: 16),
              _buildAudioMappingSection(),
              const SizedBox(height: 16),
              _buildSoundFeatureSection(),
              const SizedBox(height: 16),
              _buildFilterSection(),
              const SizedBox(height: 16),
              _buildDisplaySection(),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  // ==================== 分组构建方法 ====================

  /// 构建设置分组卡片
  ///
  /// [title] 分组标题
  /// [icon] 分组图标
  /// [children] 分组内的设置项
  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  /// 摄像头设置分组
  Widget _buildCameraSection() {
    return _buildSection(
      title: '摄像头设置',
      icon: Icons.camera_alt,
      children: [
        // 分辨率选择
        _buildDropdownSetting<int>(
          title: '摄像头分辨率',
          subtitle: '分辨率越低处理越快，建议中等',
          value: _settings.cameraResolutionIndex,
          items: const [
            DropdownMenuItem(value: 0, child: Text('低 (240p) - 最快')),
            DropdownMenuItem(value: 1, child: Text('中 (480p) - 推荐')),
            DropdownMenuItem(value: 2, child: Text('高 (720p) - 最清晰')),
          ],
          onChanged: _settings.setCameraResolutionIndex,
        ),
        const Divider(),
        // 前/后置摄像头
        _buildSwitchSetting(
          title: '使用前置摄像头',
          subtitle: '关闭=后置摄像头（导航用）',
          value: _settings.useFrontCamera,
          onChanged: _settings.setUseFrontCamera,
        ),
      ],
    );
  }

  /// 深度估计设置分组
  Widget _buildDepthSection() {
    return _buildSection(
      title: '深度估计设置',
      icon: Icons.center_focus_strong,
      children: [
        // 处理帧率
        _buildSliderSetting(
          title: '处理帧率',
          subtitle: '每秒处理多少帧画面（帧率越高反应越快，但更耗电）',
          value: _settings.processingFps.toDouble(),
          min: 2,
          max: 15,
          divisions: 13,
          unit: ' FPS',
          onChanged: (v) => _settings.setProcessingFps(v.round()),
        ),
        const Divider(),
        // 深度图缩放比例
        _buildSliderSetting(
          title: '深度图缩放比例',
          subtitle: '降低可提升处理速度',
          value: _settings.depthMapScale,
          min: 0.25,
          max: 1.0,
          divisions: 3,
          unit: '',
          formatValue: (v) => v.toStringAsFixed(2),
          onChanged: _settings.setDepthMapScale,
        ),
      ],
    );
  }

  /// 扫描线设置分组
  Widget _buildScanSection() {
    return _buildSection(
      title: '扫描线设置',
      icon: Icons.radar,
      children: [
        // 扫描模式
        _buildDropdownSetting<int>(
          title: '扫描模式',
          subtitle: '扫描线的移动方向',
          value: _settings.scanMode,
          items: const [
            DropdownMenuItem(value: 0, child: Text('从左到右（推荐）')),
            DropdownMenuItem(value: 1, child: Text('从上到下')),
            DropdownMenuItem(value: 2, child: Text('从中心扩散')),
          ],
          onChanged: _settings.setScanMode,
        ),
        const Divider(),
        // 扫描周期
        _buildSliderSetting(
          title: '扫描周期',
          subtitle: '扫描线从左到右所需时间（秒越短节奏越快）',
          value: _settings.scanPeriodSeconds,
          min: 1.0,
          max: 8.0,
          divisions: 14,
          unit: ' 秒',
          onChanged: _settings.setScanPeriodSeconds,
        ),
        const Divider(),
        // 扫描线宽度
        _buildSliderSetting(
          title: '扫描线宽度',
          subtitle: '扫描线越窄定位越精确，但声音越断续',
          value: _settings.scanLineWidth,
          min: 0.01,
          max: 0.20,
          divisions: 19,
          unit: '',
          formatValue: (v) => '${(v * 100).toStringAsFixed(0)}%',
          onChanged: _settings.setScanLineWidth,
        ),
      ],
    );
  }

  /// 音频映射设置分组
  Widget _buildAudioMappingSection() {
    return _buildSection(
      title: '音频映射设置',
      icon: Icons.graphic_eq,
      children: [
        // 最近距离频率
        _buildSliderSetting(
          title: '近处物体频率',
          subtitle: '近处障碍物发出的声音频率（越高越尖锐）',
          value: _settings.minDistanceFrequency,
          min: 500,
          max: 4000,
          divisions: 35,
          unit: ' Hz',
          onChanged: _settings.setMinDistanceFrequency,
        ),
        const Divider(),
        // 最远距离频率
        _buildSliderSetting(
          title: '远处物体频率',
          subtitle: '远处物体发出的声音频率（越低越低沉）',
          value: _settings.maxDistanceFrequency,
          min: 100,
          max: 1000,
          divisions: 18,
          unit: ' Hz',
          onChanged: _settings.setMaxDistanceFrequency,
        ),
        const Divider(),
        // 最大音量
        _buildSliderSetting(
          title: '最大音量',
          subtitle: '近处物体的音量（建议不超过0.8保护听力）',
          value: _settings.maxVolume,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          unit: '',
          formatValue: (v) => '${(v * 100).toStringAsFixed(0)}%',
          onChanged: _settings.setMaxVolume,
        ),
        const Divider(),
        // 最小音量
        _buildSliderSetting(
          title: '最小音量',
          subtitle: '远处物体的最小可听音量',
          value: _settings.minVolume,
          min: 0.0,
          max: 0.3,
          divisions: 12,
          unit: '',
          formatValue: (v) => '${(v * 100).toStringAsFixed(0)}%',
          onChanged: _settings.setMinVolume,
        ),
        const Divider(),
        // 立体声分离强度
        _buildSliderSetting(
          title: '立体声分离强度',
          subtitle: '控制左右声道分离程度（越大方位感越强）',
          value: _settings.stereoSeparation,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          unit: '',
          formatValue: (v) => '${(v * 100).toStringAsFixed(0)}%',
          onChanged: _settings.setStereoSeparation,
        ),
      ],
    );
  }

  /// 声音特征设置分组
  Widget _buildSoundFeatureSection() {
    return _buildSection(
      title: '声音特征设置',
      icon: Icons.music_note,
      children: [
        // 声音类型
        _buildDropdownSetting<int>(
          title: '声音类型',
          subtitle: '不同波形产生不同的音色',
          value: _settings.soundType,
          items: const [
            DropdownMenuItem(value: 0, child: Text('正弦波 - 纯净嗡嗡声')),
            DropdownMenuItem(value: 1, child: Text('方波 - 电子蜂鸣（推荐）')),
            DropdownMenuItem(value: 2, child: Text('三角波 - 柔和提示音')),
            DropdownMenuItem(value: 3, child: Text('噪点声 - 类似雨声')),
          ],
          onChanged: _settings.setSoundType,
        ),
        const Divider(),
        // 启用包络
        _buildSwitchSetting(
          title: '启用包络',
          subtitle: '声音渐入渐出，更自然（关闭则更敏锐）',
          value: _settings.enableEnvelope,
          onChanged: _settings.setEnableEnvelope,
        ),
        if (_settings.enableEnvelope) ...[
          const Divider(),
          // 攻击时间
          _buildSliderSetting(
            title: '攻击时间',
            subtitle: '声音从静音到最大的时间',
            value: _settings.attackTime,
            min: 0.001,
            max: 0.05,
            divisions: 49,
            unit: ' 秒',
            formatValue: (v) => '${(v * 1000).toStringAsFixed(1)}ms',
            onChanged: _settings.setAttackTime,
          ),
          const Divider(),
          // 释放时间
          _buildSliderSetting(
            title: '释放时间',
            subtitle: '声音从最大到静音的时间',
            value: _settings.releaseTime,
            min: 0.01,
            max: 0.3,
            divisions: 29,
            unit: ' 秒',
            formatValue: (v) => '${(v * 1000).toStringAsFixed(0)}ms',
            onChanged: _settings.setReleaseTime,
          ),
        ],
      ],
    );
  }

  /// 检测过滤设置分组
  Widget _buildFilterSection() {
    return _buildSection(
      title: '检测过滤设置',
      icon: Icons.filter_alt,
      children: [
        // 最小物体面积
        _buildSliderSetting(
          title: '最小物体面积',
          subtitle: '小于此面积的物体不发声（避免噪点干扰）',
          value: _settings.minObjectAreaRatio,
          min: 0.001,
          max: 0.05,
          divisions: 49,
          unit: '',
          formatValue: (v) => '${(v * 100).toStringAsFixed(1)}%',
          onChanged: _settings.setMinObjectAreaRatio,
        ),
        const Divider(),
        // 深度边界阈值
        _buildSliderSetting(
          title: '深度边界阈值',
          subtitle: '相邻像素深度差超过此值认为是物体边界',
          value: _settings.depthEdgeThreshold,
          min: 0.05,
          max: 0.5,
          divisions: 45,
          unit: '',
          onChanged: _settings.setDepthEdgeThreshold,
        ),
      ],
    );
  }

  /// 界面显示设置分组
  Widget _buildDisplaySection() {
    return _buildSection(
      title: '界面显示设置',
      icon: Icons.visibility,
      children: [
        _buildSwitchSetting(
          title: '显示摄像头预览',
          subtitle: '关闭可省电（盲人用户可关闭）',
          value: _settings.showCameraPreview,
          onChanged: _settings.setShowCameraPreview,
        ),
        const Divider(),
        _buildSwitchSetting(
          title: '显示深度图',
          subtitle: '显示AI分析的距离热力图',
          value: _settings.showDepthMap,
          onChanged: _settings.setShowDepthMap,
        ),
        const Divider(),
        _buildSwitchSetting(
          title: '显示扫描线',
          subtitle: '在深度图上显示扫描线位置',
          value: _settings.showScanLine,
          onChanged: _settings.setShowScanLine,
        ),
        const Divider(),
        _buildSwitchSetting(
          title: '自动开始扫描',
          subtitle: '系统就绪后自动开始声音导航',
          value: _settings.autoStartScanning,
          onChanged: _settings.setAutoStartScanning,
        ),
      ],
    );
  }

  // ==================== 通用设置项构建方法 ====================

  /// 构建滑块设置项
  ///
  /// 用于数值范围调节。
  ///
  /// [title] 设置项标题
  /// [subtitle] 说明文字
  /// [value] 当前值
  /// [min] 最小值
  /// [max] 最大值
  /// [divisions] 分段数
  /// [unit] 单位文字
  /// [formatValue] 自定义格式化函数
  /// [onChanged] 值变化回调
  Widget _buildSliderSetting({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    String Function(double)? formatValue,
    required ValueChanged<double> onChanged,
  }) {
    final displayValue = formatValue != null
        ? formatValue(value)
        : '${value.toStringAsFixed(2)}$unit';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
              Text(
                displayValue,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// 构建开关设置项
  ///
  /// 用于布尔值切换。
  ///
  /// [title] 设置项标题
  /// [subtitle] 说明文字
  /// [value] 当前值
  /// [onChanged] 值变化回调
  Widget _buildSwitchSetting({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// 构建下拉菜单设置项
  ///
  /// 用于枚举值选择。
  ///
  /// [title] 设置项标题
  /// [subtitle] 说明文字
  /// [value] 当前值
  /// [items] 选项列表
  /// [onChanged] 值变化回调
  Widget _buildDropdownSetting<T>({
    required String title,
    required String subtitle,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          DropdownButton<T>(
            value: value,
            items: items,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  // ==================== 恢复默认确认对话框 ====================

  /// 显示恢复默认确认对话框
  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('恢复默认设置'),
          content: const Text('确定要将所有参数恢复为默认值吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                _settings.resetToDefaults();
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}


