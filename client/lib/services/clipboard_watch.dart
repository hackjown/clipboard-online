import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

/// Mac：可选轮询系统剪贴板；iOS：仅提供一次性「从剪贴板导入」，不做后台监听。
class ClipboardWatch {
  Timer? _timer;
  String? _lastText;
  int _lastImageLen = -1;
  bool enabled = false;

  void Function(String text)? onText;
  void Function(Uint8List bytes, String filename)? onImage;

  bool get supportsWatch => !kIsWeb && Platform.isMacOS;

  /// 一次性读取（iOS / 手动按钮）
  Future<void> importOnce() async {
    final text = await Pasteboard.text;
    if (text != null && text.trim().isNotEmpty) {
      onText?.call(text);
      return;
    }
    final image = await Pasteboard.image;
    if (image != null && image.isNotEmpty) {
      final name = 'screenshot-${DateTime.now().millisecondsSinceEpoch}.png';
      onImage?.call(Uint8List.fromList(image), name);
    }
  }

  void startWatch({Duration interval = const Duration(seconds: 2)}) {
    if (!supportsWatch) return;
    enabled = true;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void stopWatch() {
    enabled = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (!enabled) return;
    try {
      final text = await Pasteboard.text;
      if (text != null && text.trim().isNotEmpty && text != _lastText) {
        _lastText = text;
        onText?.call(text);
        return;
      }
      final image = await Pasteboard.image;
      if (image != null && image.isNotEmpty && image.length != _lastImageLen) {
        _lastImageLen = image.length;
        final name = 'screenshot-${DateTime.now().millisecondsSinceEpoch}.png';
        onImage?.call(Uint8List.fromList(image), name);
      }
    } catch (_) {
      // 权限未授予时静默失败
    }
  }

  /// 写入系统剪贴板
  Future<void> copyText(String text) => Clipboard.setData(ClipboardData(text: text));
}
