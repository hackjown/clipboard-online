import 'dart:convert';
import 'dart:io';

import 'package:clipboard_client/app_info.dart';
import 'package:clipboard_client/services/api.dart';
import 'package:clipboard_client/services/auth_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('kClientVersion 与 pubspec 一致', () {
    final v = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1);
    expect(kClientVersion, v);
  });

  test('ApiException 文案：裸 Not Found → 服务器版本过旧', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ClipApi(AuthStore());
    api.serverVersion = '0.1.5';
    final r = http.Response(jsonEncode({'ok': false, 'error': 'Not Found', 'detail': 'Not Found'}), 404);
    // _json 是私有的，用公开的 putBark/testBark 走一遍（用 MockClient 注入）
    await http.runWithClient(() async {
      try {
        await api.testBark('https://api.day.app/KEY');
        fail('should throw');
      } on ApiException catch (e) {
        expect(e.message, contains('服务器版本过旧'));
        expect(e.message, contains('0.1.5'));
      }
    }, () => MockClient((_) async => r));
  });

  test('自己的 404 文案保持不变', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ClipApi(AuthStore());
    final r = http.Response.bytes(utf8.encode(jsonEncode({'ok': false, 'error': '条目不存在或已过期'})), 404);
    await http.runWithClient(() async {
      try {
        await api.editText('abc', 'x');
        fail('should throw');
      } on ApiException catch (e) {
        expect(e.message, '条目不存在或已过期');
      }
    }, () => MockClient((_) async => r));
  });

  test('editText 发送 PATCH + JSON', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ClipApi(AuthStore());
    late http.Request seen;
    await http.runWithClient(() async {
      await api.editText('u1', '新内容');
    }, () => MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'ok': true}), 200);
        }));
    expect(seen.method, 'PATCH');
    expect(seen.url.path, '/api/items/u1');
    expect(jsonDecode(utf8.decode(seen.bodyBytes))['content'], '新内容');
  });
}
