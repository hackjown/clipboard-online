import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/item.dart';
import '../models/user.dart';
import 'auth_store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.method, this.url});
  final String message;
  final int? status;
  final String? method;
  final String? url;

  /// 例如 "POST http://host:8100/api/login → HTTP 401"
  String get requestInfo {
    final parts = <String>[];
    if (url != null) parts.add('${method ?? 'GET'} $url');
    if (status != null) parts.add('HTTP $status');
    return parts.join(' → ');
  }

  @override
  String toString() => message;
}

class ClipApi {
  ClipApi(this.store);
  final AuthStore store;
  String? token;
  String base = AuthStore.defaultBase;

  Future<void> load() async {
    base = AuthStore.normalizeBaseUrl(await store.getBaseUrl());
    token = await store.getToken();
  }

  /// 用输入框的值立即更新（并持久化）服务器地址，返回规范化结果
  Future<String> setBase(String input) async {
    base = await store.setBaseUrl(input);
    return base;
  }

  /// 只去掉 \r\n（粘贴常带换行），不动其它字符
  static String cleanPassword(String s) => s.replaceAll(RegExp(r'[\r\n]'), '');

  Map<String, String> get _authHeaders => {
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _u(String path, [Map<String, String>? q]) {
    final b = base.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$b$path').replace(queryParameters: q);
  }

  Future<Map<String, dynamic>> _json(http.Response r) async {
    Map<String, dynamic> body = {};
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, dynamic>) body = d;
    } catch (_) {}
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(
        (body['error'] ?? body['detail'] ?? '请求失败 (${r.statusCode})').toString(),
        status: r.statusCode,
        method: r.request?.method,
        url: r.request?.url.toString(),
      );
    }
    return body;
  }

  Future<ClipUser> register(String username, String password) async {
    final r = await http.post(_u('/api/register'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: utf8.encode(jsonEncode({
          'username': username.trim(),
          'password': cleanPassword(password),
        })));
    final j = await _json(r);
    token = j['token'] as String?;
    final user = ClipUser.fromJson(j['user'] as Map<String, dynamic>);
    if (token != null) await store.saveSession(token: token!, username: user.username);
    return user;
  }

  Future<ClipUser> login(String username, String password) async {
    final r = await http.post(_u('/api/login'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: utf8.encode(jsonEncode({
          'username': username.trim(),
          'password': cleanPassword(password),
        })));
    final j = await _json(r);
    token = j['token'] as String?;
    final user = ClipUser.fromJson(j['user'] as Map<String, dynamic>);
    if (token != null) await store.saveSession(token: token!, username: user.username);
    return user;
  }

  Future<void> logout() async {
    try {
      await http.post(_u('/api/logout'), headers: _authHeaders);
    } catch (_) {}
    token = null;
    await store.clearSession();
  }

  Future<ClipUser?> me() async {
    final r = await http.get(_u('/api/me'), headers: _authHeaders);
    final j = await _json(r);
    final u = j['user'];
    if (u == null) return null;
    return ClipUser.fromJson(u as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> config() async {
    final r = await http.get(_u('/api/config'), headers: _authHeaders);
    return _json(r);
  }

  Future<ItemsResult> items({
    String scope = 'public',
    String type = 'all',
    String q = '',
    String tag = '',
    bool starred = false,
  }) async {
    final query = <String, String>{
      'scope': scope,
      if (type != 'all') 'type': type,
      if (q.isNotEmpty) 'q': q,
      if (tag.isNotEmpty) 'tag': tag,
      if (starred) 'starred': '1',
    };
    final r = await http.get(_u('/api/items', query), headers: _authHeaders);
    final j = await _json(r);
    final list = (j['items'] as List? ?? [])
        .map((e) => ClipItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return ItemsResult(
      items: list,
      counts: Map<String, dynamic>.from(j['counts'] as Map? ?? {}),
      tags: (j['tags'] as List?)?.map((e) => '$e').toList() ?? const [],
      needAuth: j['need_auth'] == true,
    );
  }

  Future<String> addText(
    String content, {
    String visibility = 'private',
    int expiresIn = 0,
    List<String>? tags,
  }) async {
    final r = await http.post(_u('/content'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': content,
          'visibility': visibility,
          'expires_in': expiresIn,
          if (tags != null) 'tags': tags,
        }));
    final j = await _json(r);
    return j['uuid'] as String;
  }

  Future<String> uploadFile({
    required Uint8List bytes,
    required String filename,
    String visibility = 'private',
    int expiresIn = 0,
    String? contentType,
  }) async {
    final req = http.MultipartRequest('POST', _u('/upload_file'));
    req.headers.addAll(_authHeaders);
    req.fields['visibility'] = visibility;
    req.fields['expires_in'] = '$expiresIn';
    MediaType? mt;
    if (contentType != null && contentType.contains('/')) {
      final parts = contentType.split('/');
      mt = MediaType(parts[0], parts[1]);
    }
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: mt,
    ));
    final streamed = await req.send();
    final r = await http.Response.fromStream(streamed);
    final j = await _json(r);
    return j['uuid'] as String;
  }

  Future<void> delete(String uuid) async {
    final r = await http.post(_u('/delete'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'uuid': uuid}));
    await _json(r);
  }

  Future<Map<String, dynamic>> createShare(String uuid, {num hours = 168}) async {
    final r = await http.post(_u('/api/items/$uuid/share'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'hours': hours}));
    return _json(r);
  }

  Future<void> revokeShare(String uuid) async {
    final r = await http.delete(_u('/api/items/$uuid/share'), headers: _authHeaders);
    await _json(r);
  }

  Future<bool> toggleFavorite(String uuid) async {
    final r = await http.post(_u('/api/items/$uuid/favorite'), headers: _authHeaders);
    final j = await _json(r);
    return j['favorite'] == true;
  }

  Future<bool> togglePin(String uuid) async {
    final r = await http.post(_u('/api/items/$uuid/pin'), headers: _authHeaders);
    final j = await _json(r);
    return j['pinned'] == true;
  }

  Future<List<String>> setTags(String uuid, List<String> tags) async {
    final r = await http.post(_u('/api/items/$uuid/tags'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'tags': tags}));
    final j = await _json(r);
    return (j['tags'] as List?)?.map((e) => '$e').toList() ?? [];
  }

  Future<Map<String, dynamic>> sharePeek(String shareToken) async {
    final r = await http.get(_u('/api/share/$shareToken'));
    return _json(r);
  }

  String downloadUrl(String filename) {
    final b = base.replaceAll(RegExp(r'/+$'), '');
    return '$b/download/${Uri.encodeComponent(filename)}';
  }

  String sharePageUrl(String shareToken) {
    final b = base.replaceAll(RegExp(r'/+$'), '');
    return '$b/s/$shareToken';
  }

  String wsUrl() {
    final b = base.replaceAll(RegExp(r'/+$'), '');
    final ws = b.startsWith('https') ? b.replaceFirst('https', 'wss') : b.replaceFirst('http', 'ws');
    if (token != null) return '$ws/ws?token=${Uri.encodeQueryComponent(token!)}';
    return '$ws/ws';
  }
}
