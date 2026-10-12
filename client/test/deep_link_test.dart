import 'package:clipboard_client/services/deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clipboard://item/<uuid>', () {
    final d = parseDeepLink(Uri.parse('clipboard://item/0123456789abcdef0123456789abcdef'));
    expect(d, isA<ItemLink>());
    expect((d as ItemLink).uuid, '0123456789abcdef0123456789abcdef');
  });

  test('clipboard://home/private | public | 缺省', () {
    expect((parseDeepLink(Uri.parse('clipboard://home/private')) as HomeLink).scope, 'private');
    expect((parseDeepLink(Uri.parse('clipboard://home/public')) as HomeLink).scope, 'public');
    expect((parseDeepLink(Uri.parse('clipboard://home')) as HomeLink).scope, 'private');
  });

  test('分享链接：clipboard://s/<token> 与 https://host/s/<token>', () {
    expect((parseDeepLink(Uri.parse('clipboard://s/AbC_123-xyz')) as ShareLink).token, 'AbC_123-xyz');
    expect((parseDeepLink(Uri.parse('https://clip.example.com/s/tok_ABC123')) as ShareLink).token, 'tok_ABC123');
  });

  test('非法 / 无关链接返回 null', () {
    expect(parseDeepLink(Uri.parse('clipboard://item/')), isNull);
    expect(parseDeepLink(Uri.parse('clipboard://item/a b')), isNull);
    expect(parseDeepLink(Uri.parse('clipboard://item/../../etc')), isNull);
    expect(parseDeepLink(Uri.parse('clipboard://unknown/x')), isNull);
    expect(parseDeepLink(Uri.parse('https://example.com/other')), isNull);
  });

  test('DeepLinkBus：先 post 后 take（冷启动挂起）；take 后清空', () {
    final bus = DeepLinkBus.instance;
    bus.post(const ItemLink('abcd1234'));
    expect(bus.pending.value, isA<ItemLink>());
    expect(bus.take(), isA<ItemLink>());
    expect(bus.take(), isNull);
  });

  test('重复 post 同一链接也会通知监听者', () {
    final bus = DeepLinkBus.instance;
    var n = 0;
    void l() {
      if (bus.pending.value != null) n++;
    }
    bus.pending.addListener(l);
    bus.post(const HomeLink('private'));
    bus.post(const HomeLink('private'));
    bus.pending.removeListener(l);
    bus.take();
    expect(n, 2);
  });
}
