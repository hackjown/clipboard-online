import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式（跟随系统 / 浅色 / 深色），持久化到本地偏好。
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();
  static const _key = 'theme_mode';

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static ThemeMode parse(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String encode(ThemeMode m) =>
      m == ThemeMode.light ? 'light' : (m == ThemeMode.dark ? 'dark' : 'system');

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      mode.value = parse(sp.getString(_key));
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, encode(m));
    } catch (_) {}
  }
}
