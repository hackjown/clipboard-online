import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS：把服务器地址 + 令牌写入 App Group 容器（分享扩展直接上传用），并读取扩展日志。
/// App Group 不可用时（免费 Apple ID / 重签 / 未带 entitlement）所有方法安全返回「不可用」。
class ShareConfig {
  static const _ch = MethodChannel('clipboard/share_config');
  static bool get supported => !kIsWeb && Platform.isIOS;

  /// 返回 App Group 是否可用
  static Future<bool> sync(String? base, String? token) async {
    if (!supported) return false;
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('sync', {'base': base ?? '', 'token': token ?? ''});
      return r?['group'] == true;
    } catch (e) {
      debugPrint('ShareConfig.sync failed: $e');
      return false;
    }
  }

  static Future<bool> groupAvailable() async {
    if (!supported) return false;
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('status');
      return r?['group'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> readLog() async {
    if (!supported) return '';
    try {
      return (await _ch.invokeMethod<String>('readLog')) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> clearLog() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('clearLog');
    } catch (_) {}
  }
}
