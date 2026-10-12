import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

/// WebSocket 实时同步，失败时由外部轮询兜底。
///
/// v0.1.14：
/// * 只有收到服务器 `hello` 才算「已连接」（以前 connect() 一调用就标记已连接，连不上也显示正常）；
/// * 每 20 秒发 `ping`，50 秒内没有任何消息（含 pong）就判定为半开连接并重连——
///   NAT / 代理 / Wi-Fi 休眠后 TCP 可能「看似连着、实际已断」，之前这种情况下推送会静默丢失。
class WsSync {
  WsSync(this.api);
  final ClipApi api;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _reconnect;
  Timer? _ping;
  DateTime _lastMsg = DateTime.now();
  bool _stopped = false;
  void Function(Map<String, dynamic> msg)? onEvent;
  VoidCallback? onHello;

  /// 连接状态文本（设置页「同步状态」显示）
  static final ValueNotifier<String> status = ValueNotifier('未连接');
  bool connected = false;

  void start() {
    _stopped = false;
    _close();
    status.value = '连接中…';
    try {
      _ch = WebSocketChannel.connect(Uri.parse(api.wsUrl()));
      _lastMsg = DateTime.now();
      _sub = _ch!.stream.listen(
        (data) {
          _lastMsg = DateTime.now();
          try {
            final msg = jsonDecode(data is String ? data : utf8.decode(data as List<int>));
            if (msg is! Map) return;
            final type = msg['type'];
            if (type == 'hello') {
              connected = true;
              status.value = '已连接';
              onHello?.call();
              return;
            }
            if (type == 'pong') return;
            onEvent?.call(Map<String, dynamic>.from(msg));
          } catch (_) {}
        },
        onDone: () => _scheduleReconnect('连接被关闭'),
        onError: (e) => _scheduleReconnect('$e'),
        cancelOnError: true,
      );
      _ping = Timer.periodic(const Duration(seconds: 20), (_) {
        if (DateTime.now().difference(_lastMsg) > const Duration(seconds: 50)) {
          _scheduleReconnect('50 秒无响应（半开连接）');
          return;
        }
        try {
          _ch?.sink.add('ping');
        } catch (_) {}
      });
    } catch (e) {
      _scheduleReconnect('$e');
    }
  }

  void _scheduleReconnect(String why) {
    connected = false;
    _close();
    if (_stopped) return;
    final s = why.length > 80 ? '${why.substring(0, 80)}…' : why;
    status.value = '未连接（$s），4 秒后重试';
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 4), start);
  }

  void _close() {
    _ping?.cancel();
    _ping = null;
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
  }

  void stop() {
    _stopped = true;
    _reconnect?.cancel();
    _close();
    connected = false;
    status.value = '未连接';
  }
}
