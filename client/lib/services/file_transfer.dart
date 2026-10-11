import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';

class PendingTransfer {
  PendingTransfer({
    required this.bytes,
    required this.filename,
    this.contentType,
    this.isText = false,
    this.textContent,
  });

  final Uint8List bytes;
  final String filename;
  final String? contentType;
  final bool isText;
  final String? textContent;

  int get size => isText ? utf8ByteLen(textContent) : bytes.length;

  static int utf8ByteLen(String? s) {
    if (s == null) return 0;
    return s.length; // display approx; upload uses real string
  }
}

/// 下载到本地缓存，供「分享」与「在访达中显示」使用
class FileTransferService {
  FileTransferService(this.api);
  final ClipApi api;

  Future<File> downloadToCache({
    required String filename,
    required String remoteUrl,
  }) async {
    final dir = await getTemporaryDirectory();
    final safe = p.basename(filename).replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fff]+'), '_');
    final out = File(p.join(dir.path, 'clip_$safe'));
    final headers = <String, String>{};
    if (api.token != null) headers['Authorization'] = 'Bearer ${api.token}';
    final r = await http.get(Uri.parse(remoteUrl), headers: headers);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('下载失败 (${r.statusCode})');
    }
    await out.writeAsBytes(r.bodyBytes, flush: true);
    return out;
  }

  Future<void> shareText(String text) async {
    await Share.share(text, subject: '剪贴板');
  }

  Future<void> shareFile(File file, {String? text}) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: text,
      subject: p.basename(file.path),
    );
  }

  /// macOS：在访达中显示；iOS：走系统分享；其它尝试打开
  Future<void> revealOrOpen(File file) async {
    if (!kIsWeb && Platform.isMacOS) {
      await Process.run('open', ['-R', file.path]);
      return;
    }
    if (!kIsWeb && Platform.isIOS) {
      await shareFile(file);
      return;
    }
    try {
      await Process.run('xdg-open', [file.path]);
    } catch (_) {}
  }

  static String? guessMime(String filename, [Uint8List? bytes]) {
    return lookupMimeType(filename, headerBytes: bytes);
  }

  static PendingTransfer fromText(String text) {
    return PendingTransfer(
      bytes: Uint8List(0),
      filename: 'note.txt',
      contentType: 'text/plain',
      isText: true,
      textContent: text,
    );
  }

  static PendingTransfer fromBytes(Uint8List bytes, String filename, {String? contentType}) {
    return PendingTransfer(
      bytes: bytes,
      filename: filename,
      contentType: contentType ?? guessMime(filename, bytes),
    );
  }
}
