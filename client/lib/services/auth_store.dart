import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  static const _tokenKey = 'clip_token';
  static const _userKey = 'clip_username';
  static const _baseKey = 'clip_base_url';
  static const defaultBase = 'http://127.0.0.1:8099';

  final _secure = const FlutterSecureStorage();

  Future<String> getBaseUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_baseKey) ?? defaultBase;
  }

  Future<void> setBaseUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_baseKey, url.replaceAll(RegExp(r'/+$'), ''));
  }

  Future<String?> getToken() => _secure.read(key: _tokenKey);
  Future<String?> getUsername() => _secure.read(key: _userKey);

  Future<void> saveSession({required String token, required String username}) async {
    await _secure.write(key: _tokenKey, value: token);
    await _secure.write(key: _userKey, value: username);
  }

  Future<void> clearSession() async {
    await _secure.delete(key: _tokenKey);
    await _secure.delete(key: _userKey);
  }
}
