import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// iOS：把服务器地址 + 令牌写入 App Group 容器（分享扩展直接上传用），并读取扩展日志。
/// App Group 不可用时（免费 Apple ID / 重签 / 未带 entitlement）所有方法安全返回「不可用」。
/// SharedPreferences 键：分享扩展默认有效期（秒）
const kShareExpiryKey = 'share_ext_expiry';

class ShareConfig {
  static const _ch = MethodChannel('clipboard/share_config');
  static bool get supported => !kIsWeb && Platform.isIOS;

  /// 返回 App Group 是否可用
  static Future<bool> sync(String? base, String? token) async {
    if (!supported) return false;
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('sync', {'base': base ?? '', 'token': token ?? ''});
      try {
        final sp = await SharedPreferences.getInstance();
        await _ch.invokeMapMethod<String, dynamic>('setExpiry', {'expires_in': sp.getInt(kShareExpiryKey) ?? 0});
      } catch (_) {}
      return r?['group'] == true;
    } catch (e) {
      debugPrint('ShareConfig.sync failed: $e');
      return false;
    }
  }

  /// 分享扩展上传时的默认有效期（秒；0 = 永不过期）
  static Future<bool> setExpiry(int seconds) async {
    if (!supported) return false;
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('setExpiry', {'expires_in': seconds});
      return r?['written'] == true;
    } catch (_) {
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
