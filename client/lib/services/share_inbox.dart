import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'file_transfer.dart';

/// 系统分享 / Share Extension → 待上传队列（私有快传）
class ShareInbox {
  StreamSubscription? _sub;
  void Function(List<PendingTransfer> items)? onShared;

  bool get supported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<void> start() async {
    if (!supported) return;
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        final items = await _convert(initial);
        if (items.isNotEmpty) onShared?.call(items);
        await ReceiveSharingIntent.instance.reset();
      }
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen((list) async {
        final items = await _convert(list);
        if (items.isNotEmpty) onShared?.call(items);
        await ReceiveSharingIntent.instance.reset();
      });
    } catch (e) {
      debugPrint('ShareInbox start failed: $e');
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<List<PendingTransfer>> _convert(List<SharedMediaFile> media) async {
    final out = <PendingTransfer>[];
    for (final m in media) {
      try {
        if (m.type == SharedMediaType.text || m.type == SharedMediaType.url) {
          final text = m.path.trim();
          if (text.isEmpty) continue;
          out.add(FileTransferService.fromText(text));
          continue;
        }
        // file / image / video — path is local file path
        final path = m.path;
        if (path.isEmpty) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final name = m.path.split(Platform.pathSeparator).last;
        out.add(FileTransferService.fromBytes(
          bytes,
          name.isNotEmpty ? name : 'shared-${DateTime.now().millisecondsSinceEpoch}',
          contentType: m.mimeType,
        ));
      } catch (e) {
        debugPrint('ShareInbox convert skip: $e');
      }
    }
    return out;
  }
}
