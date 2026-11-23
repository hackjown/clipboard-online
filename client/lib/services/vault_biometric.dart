import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 密码保险箱本地生物识别（Face ID / Touch ID / 指纹）认证与主密码安全存储服务
class VaultBiometric {
  VaultBiometric._();
  static final VaultBiometric instance = VaultBiometric._();

  static const _prefEnabledKey = 'vault_biometric_enabled';
  static const _securePwKey = 'vault_biometric_master_password';

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  /// 检查设备是否支持本地生物识别（Face ID / 触控 ID / 指纹识别）
  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return isSupported || canCheck;
    } catch (e) {
      debugPrint('VaultBiometric.isSupported error: $e');
      return false;
    }
  }

  /// 获取当前设备主要生物识别类型的文案（如 "Face ID"、"触控 ID"、"指纹识别"）
  Future<String> biometricLabel() async {
    if (kIsWeb) return '生物识别';
    try {
      final bios = await _auth.getAvailableBiometrics();
      if (Platform.isIOS || Platform.isMacOS) {
        if (bios.contains(BiometricType.face)) return 'Face ID';
        if (bios.contains(BiometricType.fingerprint)) return '触控 ID';
        return 'Face ID';
      }
      if (bios.contains(BiometricType.fingerprint)) return '指纹识别';
      if (bios.contains(BiometricType.face)) return '人脸识别';
    } catch (_) {}
    return 'Face ID / 生物识别';
  }

  /// 检查用户是否已开启生物识别解锁且本地存有主密码
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefEnabledKey) ?? false;
    if (!enabled) return false;
    final pw = await getSavedPassword();
    return pw != null && pw.isNotEmpty;
  }

  /// 调起系统生物识别认证弹窗
  Future<bool> authenticate({String? reason}) async {
    if (kIsWeb) return false;
    try {
      final label = await biometricLabel();
      return await _auth.authenticate(
        localizedReason: reason ?? '使用 $label 解锁密码保险箱',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('VaultBiometric.authenticate PlatformException: $e');
      return false;
    } catch (e) {
      debugPrint('VaultBiometric.authenticate error: $e');
      return false;
    }
  }

  /// 读取已保存在 Keychain / 安全存储区中的主密码
  Future<String?> getSavedPassword() async {
    try {
      return await _secure.read(key: _securePwKey);
    } catch (e) {
      debugPrint('VaultBiometric.getSavedPassword error: $e');
      return null;
    }
  }

  /// 保存主密码并激活生物识别解锁
  Future<void> enableWithPassword(String masterPassword) async {
    final prefs = await SharedPreferences.getInstance();
    await _secure.write(key: _securePwKey, value: masterPassword);
    await prefs.setBool(_prefEnabledKey, true);
  }

  /// 关闭生物识别解锁并清除存储的主密码
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, false);
    try {
      await _secure.delete(key: _securePwKey);
    } catch (e) {
      debugPrint('VaultBiometric.disable error: $e');
    }
  }
}
