import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// 取消令牌：调用 [cancel] 会关闭底层 HTTP 连接并让 [MediaCache.fetch] 抛出 [DownloadCancelled]。
class DownloadCancel {
  http.Client? _client;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    _client?.close();
  }
}

class DownloadCancelled implements Exception {
  @override
  String toString() => '已取消';
}

/// 视频 / 音频先用 App 自带的（带 Bearer 的）Dart HTTP 客户端下载到本地缓存，再从本地文件播放。
/// 原因：AVPlayer 走系统 NSURLSession，会受 ATS 限制（局域网 http 报 -1022），且无法稳定带自定义头。
/// 缓存：`<临时目录>/clip_media/<uuid>_<文件名>`，大小与预期一致时直接复用；下载中写 `.part`，完成后改名。
class MediaCache {
  MediaCache(this.api);
  final ClipApi api;

  Future<Directory> _dir() async {
    final base = await getTemporaryDirectory();
    final d = Directory(p.join(base.path, 'clip_media'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _safe(String s) => p.basename(s).replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fff]+'), '_');

  Future<File> cachedFile(String uuid, String filename) async =>
      File(p.join((await _dir()).path, '${uuid}_${_safe(filename)}'));

  /// 返回本地文件。[expectedSize] 用于判断缓存是否完整；[onProgress] 回调 (已收, 总数)，总数未知时为 0。
  Future<File> fetch({
    required String uuid,
    required String filename,
    required String url,
    int expectedSize = 0,
    void Function(int received, int total)? onProgress,
    DownloadCancel? cancel,
  }) async {
    final out = await cachedFile(uuid, filename);
    if (await out.exists()) {
      final len = await out.length();
      if (len > 0 && (expectedSize <= 0 || len == expectedSize)) {
        onProgress?.call(len, len);
        return out;
      }
      await out.delete();
    }
    final part = File('${out.path}.part');
    if (await part.exists()) await part.delete();

    final client = http.Client();
    cancel?._client = client;
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(url))..headers.addAll(api.authHeaders);
      final resp = await client.send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('下载失败 (HTTP ${resp.statusCode})');
      }
      final total = resp.contentLength ?? expectedSize;
      var got = 0;
      sink = part.openWrite();
      await for (final chunk in resp.stream) {
        if (cancel?.cancelled ?? false) throw DownloadCancelled();
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(got, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (cancel?.cancelled ?? false) throw DownloadCancelled();
      await part.rename(out.path);
      return out;
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
      if (cancel?.cancelled ?? false) throw DownloadCancelled();
      rethrow;
    } finally {
      client.close();
      cancel?._client = null;
    }
  }
}
