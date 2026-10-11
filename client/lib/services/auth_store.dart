import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 会话存储：
/// - iOS / Android：优先 Keychain / Keystore（flutter_secure_storage）；
/// - macOS：未签名/ad-hoc 构建没有 keychain-access-groups 权限（错误 -34018），
///   因此直接使用本地 SharedPreferences；
/// - 任何平台上安全存储抛出异常时，自动回退到 SharedPreferences。
class AuthStore {
  static const _tokenKey = 'clip_token';
  static const _userKey = 'clip_username';
  static const _baseKey = 'clip_base_url';
  // SharedPreferences 回退键（与安全存储键分开）
  static const _tokenFallbackKey = 'clip_token_fallback';
  static const _userFallbackKey = 'clip_username_fallback';
  static const defaultBase = 'http://127.0.0.1:8099';

  final _secure = const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  bool get _useKeychain => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<String> getBaseUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_baseKey) ?? defaultBase;
  }

  Future<void> setBaseUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_baseKey, url.replaceAll(RegExp(r'/+$'), ''));
  }

  Future<String?> getToken() => _read(_tokenKey, _tokenFallbackKey);
  Future<String?> getUsername() => _read(_userKey, _userFallbackKey);

  Future<void> saveSession({required String token, required String username}) async {
    await _write(_tokenKey, _tokenFallbackKey, token);
    await _write(_userKey, _userFallbackKey, username);
  }

  Future<void> clearSession() async {
    await _delete(_tokenKey, _tokenFallbackKey);
    await _delete(_userKey, _userFallbackKey);
  }

  Future<String?> _read(String key, String fallbackKey) async {
    if (_useKeychain) {
      try {
        final v = await _secure.read(key: key);
        if (v != null) return v;
      } catch (e) {
        debugPrint('secure storage read failed, fallback to prefs: $e');
      }
    }
    final p = await SharedPreferences.getInstance();
    return p.getString(fallbackKey);
  }

  Future<void> _write(String key, String fallbackKey, String value) async {
    final p = await SharedPreferences.getInstance();
    if (_useKeychain) {
      try {
        await _secure.write(key: key, value: value);
        await p.remove(fallbackKey);
        return;
      } catch (e) {
        debugPrint('secure storage write failed, fallback to prefs: $e');
      }
    }
    await p.setString(fallbackKey, value);
  }

  Future<void> _delete(String key, String fallbackKey) async {
    if (_useKeychain) {
      try {
        await _secure.delete(key: key);
      } catch (e) {
        debugPrint('secure storage delete failed: $e');
      }
    }
    final p = await SharedPreferences.getInstance();
    await p.remove(fallbackKey);
  }
}
