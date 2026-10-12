import 'package:flutter/foundation.dart';

/// 应用内深链：
///  * `clipboard://s/<token>`        打开分享页
///  * `clipboard://item/<uuid>`      打开 App → 「我的私有」→ 定位 / 高亮该条（图片、视频、PDF、压缩包自动打开预览）
///  * `clipboard://home/private`     打开 App → 「我的私有」（`clipboard://home/public` → 公共）
///  * `https://host/s/<token>`       （App Links）同分享页
/// Bark 推送的 `url` 参数用 `clipboard://item/<uuid>`，点推送直接进 App。
sealed class DeepLink {
  const DeepLink();
}

class ShareLink extends DeepLink {
  const ShareLink(this.token);
  final String token;
}

class ItemLink extends DeepLink {
  const ItemLink(this.uuid);
  final String uuid;
}

class HomeLink extends DeepLink {
  const HomeLink(this.scope);
  final String scope; // private | public
}

final _idRe = RegExp(r'^[A-Za-z0-9_-]{4,128}$');

DeepLink? parseDeepLink(Uri uri) {
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (uri.scheme == 'clipboard') {
    switch (uri.host) {
      case 's':
        if (seg.isNotEmpty && _idRe.hasMatch(seg.first)) return ShareLink(seg.first);
      case 'item':
        if (seg.isNotEmpty && _idRe.hasMatch(seg.first)) return ItemLink(seg.first);
      case 'home':
        return HomeLink(seg.isNotEmpty && seg.first == 'public' ? 'public' : 'private');
    }
    // clipboard:///s/<token> 之类（host 为空）
    final i = seg.indexOf('s');
    if (uri.host.isEmpty && i >= 0 && i + 1 < seg.length && _idRe.hasMatch(seg[i + 1])) return ShareLink(seg[i + 1]);
    return null;
  }
  final i = seg.indexOf('s');
  if (i >= 0 && i + 1 < seg.length && _idRe.hasMatch(seg[i + 1])) return ShareLink(seg[i + 1]);
  return null;
}

/// 深链待处理队列：冷启动时 HomeScreen 还没出现 / 用户还没登录，先挂起，Home 出现后取走。
class DeepLinkBus {
  DeepLinkBus._();
  static final DeepLinkBus instance = DeepLinkBus._();

  final ValueNotifier<DeepLink?> pending = ValueNotifier<DeepLink?>(null);

  void post(DeepLink link) {
    pending.value = null; // 同一链接重复投递也要触发监听
    pending.value = link;
  }

  DeepLink? take() {
    final v = pending.value;
    pending.value = null;
    return v;
  }
}
