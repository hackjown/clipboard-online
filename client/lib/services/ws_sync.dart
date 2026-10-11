import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

/// WebSocket 实时同步，失败时由外部轮询兜底
class WsSync {
  WsSync(this.api);
  final ClipApi api;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _reconnect;
  void Function()? onEvent;
  bool connected = false;

  void start() {
    stop();
    try {
      _ch = WebSocketChannel.connect(Uri.parse(api.wsUrl()));
      connected = true;
      _sub = _ch!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data is String ? data : utf8.decode(data as List<int>));
            if (msg is Map && msg['type'] != 'hello') {
              onEvent?.call();
            }
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      connected = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    connected = false;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 4), start);
  }

  void stop() {
    _reconnect?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    _ch = null;
    connected = false;
  }
}
