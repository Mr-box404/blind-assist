/// 盲人辅助导航APP - 主入口文件
///
/// 功能概述：
///   1. 使用后置摄像头实时拍摄周围环境
///   2. AI深度估计模型（MiDaS）将画面转为深度图
///   3. 扫描线从左到右扫描深度图
///   4. 将每个位置的深度信息映射为立体声
///   5. 盲人通过双耳立体声感知障碍物的方位和距离
///
/// 原理类似蝙蝠回声定位：
///   - 近处物体 → 高音+大声（像硬币掉落的清脆声）
///   - 远处物体 → 低音+小声（低沉的嗡嗡声）
///   - 左侧物体 → 主要在左耳响
///   - 右侧物体 → 主要在右耳响
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app.dart';
import 'services/settings_service.dart';

/// 应用程序入口点
///
/// 在启动时执行以下操作：
///   1. 确保Flutter绑定初始化（用于插件通信）
///   2. 锁定屏幕方向为竖屏（导航时手机竖直握持）
///   3. 加载用户保存的设置
///   4. 请求摄像头权限
///   5. 启动主应用界面
void main() async {
  // 确保Flutter引擎绑定已初始化，这样插件才能在main中使用
  WidgetsFlutterBinding.ensureInitialized();

  // 锁定为竖屏模式（导航时手机竖直握持，摄像头朝前）
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // 加载用户保存的设置参数
  await SettingsService.instance.load();

  // 请求摄像头权限（核心功能依赖）
  await _requestPermissions();

  // 启动Flutter应用
  runApp(const BlindAssistApp());
}

/// 请求应用所需的系统权限
///
/// 需要请求的权限：
///   - 摄像头：用于拍摄周围环境
///   - 麦克风：部分音频方案需要（可选项）
///   - 存储：用于保存AI模型文件和设置
///
/// 如果用户拒绝权限，APP仍会启动但功能受限，
/// 会在界面提示用户授予权限。
Future<void> _requestPermissions() async {
  // 请求摄像头权限
  final cameraStatus = await Permission.camera.request();

  // 请求存储权限（Android 12及以下需要）
  final storageStatus = await Permission.storage.request();

  // 记录权限状态（在界面中会根据状态显示提示）
  // 注意：即使用户拒绝，APP也会启动，用户可以在系统设置中手动授权
  debugPrint('摄像头权限: ${cameraStatus.isGranted ? "已授权" : "未授权"}');
  debugPrint('存储权限: ${storageStatus.isGranted ? "已授权" : "未授权"}');
}
