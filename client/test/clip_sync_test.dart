import 'package:clipboard_client/models/sync.dart';
import 'package:clipboard_client/services/api.dart';
import 'package:clipboard_client/services/auth_store.dart';
import 'package:clipboard_client/services/clip_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EchoGuard：本机新复制只发送一次', () {
    final g = EchoGuard();
    expect(g.shouldSend('a'), isTrue);
    expect(g.shouldSend('a'), isFalse);
    expect(g.shouldSend('b'), isTrue);
    expect(g.shouldSend('  '), isFalse);
  });

  test('EchoGuard：远端写入的内容不回传（回声抑制），之后本机再复制同内容以外的照常发送', () {
    final g = EchoGuard();
    g.markRemote('来自 Mac');
    expect(g.isCurrent('来自 Mac'), isTrue);
    expect(g.shouldSend('来自 Mac'), isFalse);
    expect(g.shouldSend('本机新复制'), isTrue);
  });

  test('方向', () {
    expect(directionSends('both') && directionReceives('both'), isTrue);
    expect(directionSends('send') && !directionReceives('send'), isTrue);
    expect(!directionSends('recv') && directionReceives('recv'), isTrue);
    expect(!directionSends('off') && !directionReceives('off'), isTrue);
  });

  test('模型解析', () {
    final d = SyncDevice.fromJson({'device_id': 'abc12345', 'name': 'Mac', 'platform': 'macos', 'direction': 'recv', 'online': true, 'current': false, 'last_seen': 1.5});
    expect(d.name, 'Mac');
    expect(d.online, isTrue);
    expect(d.lastSeen, 1.5);
    final c = SyncClip.fromJson({'text': 'hi', 'ts': 10, 'origin': 'x', 'origin_name': 'Phone'});
    expect(c.ts, 10.0);
    expect(c.originName, 'Phone');
  });

  test('wsUrl 带上 device 参数（服务器据此显示在线设备）', () {
    final api = ClipApi(AuthStore());
    api.base = 'http://192.168.1.2:8100/';
    api.token = 'tok en';
    api.deviceId = 'abcdef0123456789';
    expect(api.wsUrl(), 'ws://192.168.1.2:8100/ws?token=tok+en&device=abcdef0123456789');
  });
}
