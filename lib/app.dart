/// 应用根组件
///
/// 定义MaterialApp的配置，包括：
///   - 应用主题（深色主题，减少屏幕对盲人用户的干扰）
///   - 主页路由
///   - 设置页路由
library;

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';

/// 盲人辅助导航APP的根组件
///
/// 继承自StatelessWidget，因为根组件本身不需要管理状态，
/// 状态由各个Service和Page自行管理。
class BlindAssistApp extends StatelessWidget {
  /// 构造函数
  const BlindAssistApp({super.key});

  /// 构建应用界面
  ///
  /// [context] 构建上下文，用于访问主题、媒体查询等
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 应用名称（显示在任务管理器中）
      title: '盲人辅助导航',

      // 使用深色主题（减少屏幕亮度，对弱视用户更友好）
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50), // 绿色主色调（代表安全/导航）
          brightness: Brightness.dark,
        ),
        // 增大按钮和文字，方便操作
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        // 大按钮主题（盲人用户需要大触控区域）
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 56), // 按钮最小尺寸
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
      ),

      // 关闭调试横幅
      debugShowCheckedModeBanner: false,

      // 首页
      home: const HomeScreen(),

      // 路由表
      routes: {
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
