import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sync.dart';
import '../utils/sensitive.dart';
import 'api.dart';

/// 多设备剪贴板同步的本机设置（按设备保存在本机）
@immutable
class ClipSyncSettings {
  const ClipSyncSettings({
    this.enabled = false,
    this.direction = 'both',
    this.name = '',
    this.skipSensitive = true,
    this.saveHistory = true,
  });

  final bool enabled;
  final String direction;
  final String name;
  final bool skipSensitive;
  final bool saveHistory;

  ClipSyncSettings copyWith({bool? enabled, String? direction, String? name, bool? skipSensitive, bool? saveHistory}) =>
      ClipSyncSettings(
        enabled: enabled ?? this.enabled,
        direction: direction ?? this.direction,
        name: name ?? this.name,
        skipSensitive: skipSensitive ?? this.skipSensitive,
        saveHistory: saveHistory ?? this.saveHistory,
      );
}

/// 回声抑制 + 去重的纯逻辑（可单测）：
/// * 远端写进本机剪贴板的内容，下一次本机读取到时不能再发回去（lanecho 的 echo suppression）；
/// * 同一内容只发送一次（一次复制只传播一次）。
class EchoGuard {
  String? _lastSeen;
  String? _echo;

  /// 本机读到 [text]：返回是否应当发送
  bool shouldSend(String text) {
    if (text.trim().isEmpty) return false;
    if (text == _lastSeen) return false;
    _lastSeen = text;
    if (text == _echo) {
      _echo = null; // 回声只吞一次
      return false;
    }
    return true;
  }

  /// 远端内容即将写入本机剪贴板
  void markRemote(String text) {
    _echo = text;
    _lastSeen = text;
  }

  /// 是否与本机当前已知内容相同（相同则不必再写）
  bool isCurrent(String text) => text == _lastSeen;
}

/// 现场排查用的同步状态（设置页「同步状态」显示）
class ClipSyncStatus {
  DateTime? registeredAt;
  String? registerError;
  String? registerConfirm;
  DateTime? sentAt;
  String? sentPreview;
  DateTime? receivedAt;
  String? receivedFrom;
  DateTime? polledAt;
  DateTime? resumeReadAt;
  String? resumeRead; // 回到前台时读剪贴板的结果
  String? lastError;
  DateTime? lastErrorAt;
}

/// 多设备剪贴板同步（思路参考 lanecho，MIT；本项目为服务器中转 + WebSocket 的独立实现）。
///
/// * macOS：开启后每秒检查一次系统剪贴板，变化即发送（App 在后台 / 菜单栏也有效）。
/// * Android / iOS：系统限制后台读剪贴板，只在 App 回到前台时检查一次；
///   iOS 16+ 每次读取可能弹出「允许粘贴」，可在 系统设置 → 剪贴板 App → 从其他 App 粘贴 → 允许。
/// * 收到其他设备的复制：WebSocket `clip` 事件 → 写入本机剪贴板（App 在前台 / Mac 常驻时）。
class ClipSync {
  ClipSync._();
  static final ClipSync instance = ClipSync._();

  final ValueNotifier<ClipSyncSettings> settings = ValueNotifier(const ClipSyncSettings());

  /// 收到并已写入本机的远端内容（UI 提示用）
  final ValueNotifier<SyncClip?> lastApplied = ValueNotifier(null);

  /// 最近一次错误（设置页显示）
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  final ClipSyncStatus status = ClipSyncStatus();

  /// 状态有变化时 +1（UI 监听）
  final ValueNotifier<int> statusTick = ValueNotifier(0);
  void _touch() => statusTick.value++;
  void _err(String e) {
    lastError.value = e;
    status.lastError = e;
    status.lastErrorAt = DateTime.now();
    _touch();
  }

  /// 首页把 WebSocket 是否连着告诉这里（决定轮询频率）
  bool Function() wsConnected = () => false;

  ClipApi? _api;
  Timer? _timer;
  Timer? _heartbeat;
  Timer? _pollTimer;
  DateTime _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  double _lastAppliedTs = 0;
  final EchoGuard _guard = EchoGuard();
  bool _loaded = false;

  static String get platformTag {
    if (kIsWeb) return 'web';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  static String get defaultName => const {
        'macos': '我的 Mac',
        'ios': '我的 iPhone',
        'android': '我的 Android',
        'windows': '我的 Windows',
        'linux': '我的 Linux',
      }[platformTag] ??
      '我的设备';

  /// Mac 可以持续监听；手机只能前台检查
  static bool get canPoll => !kIsWeb && Platform.isMacOS;

  Future<void> load() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    settings.value = ClipSyncSettings(
      enabled: sp.getBool('clipsync_enabled') ?? false,
      direction: sp.getString('clipsync_direction') ?? 'both',
      name: sp.getString('clipsync_name') ?? defaultName,
      skipSensitive: sp.getBool('clipsync_skip_sensitive') ?? true,
      saveHistory: sp.getBool('clipsync_history') ?? true,
    );
    _loaded = true;
  }

  Future<void> update(ClipSyncSettings s) async {
    settings.value = s;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('clipsync_enabled', s.enabled);
    await sp.setString('clipsync_direction', s.direction);
    await sp.setString('clipsync_name', s.name);
    await sp.setBool('clipsync_skip_sensitive', s.skipSensitive);
    await sp.setBool('clipsync_history', s.saveHistory);
    await _register();
    _restart();
  }

  /// 登录后由首页调用
  Future<void> attach(ClipApi api) async {
    _api = api;
    await load();
    await _register();
    _restart();
    if (settings.value.enabled) unawaited(onResume());
  }

  void detach() {
    _timer?.cancel();
    _timer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _api = null;
  }

  /// WebSocket 重新连上：可能错过了断线期间的推送，补拉一次最新内容
  Future<void> onReconnect() async {
    await _register();
    await _pollOnce();
  }

  Future<void> _pollOnce() async {
    final api = _api;
    final s = settings.value;
    if (api == null || !s.enabled || !directionReceives(s.direction)) return;
    _lastPoll = DateTime.now();
    try {
      final c = await api.getClip();
      status.polledAt = DateTime.now();
      _touch();
      if (c != null && c.origin != api.deviceId) await _apply(c);
    } catch (e) {
      _err('拉取最新同步内容失败：$e');
    }
  }

  Future<void> _register() async {
    final api = _api;
    if (api == null || api.token == null) return;
    final s = settings.value;
    // 关闭同步时也上报（方向 off），设备列表里能看到这台设备的状态
    try {
      await api.putDevice(
        name: s.name.trim().isEmpty ? defaultName : s.name.trim(),
        platform: platformTag,
        direction: s.enabled ? s.direction : 'off',
      );
      lastError.value = null;
      status.registeredAt = DateTime.now();
      status.registerError = null;
      // 回读确认：服务器上确实有这台设备，并记下服务器上一共几台（与其他设备对比）
      try {
        final l = await api.listDevices();
        final mine = l.devices.any((d) => d.id == api.deviceId);
        status.registerConfirm = '${mine ? '服务器已确认' : '服务器列表里没有本机！'}，共 ${l.devices.length} 台：'
            '${l.devices.map((d) => d.name).join('、')}';
      } catch (e) {
        status.registerConfirm = '回读设备列表失败：$e';
      }
      _touch();
    } catch (e) {
      status.registerError = '$e';
      _err('设备登记失败：$e');
    }
  }

  void _restart() {
    _heartbeat?.cancel();
    _pollTimer?.cancel();
    if (_api != null) {
      // 每 60 秒登记一次：刷新「最近在线」时间；登记失败会出现在同步状态里
      _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) => _register());
      // 兜底轮询：WebSocket 断开时每 5 秒、连着时每 30 秒拉一次最新同步内容（防半开连接丢推送）
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        final gap = DateTime.now().difference(_lastPoll);
        if (gap >= (wsConnected() ? const Duration(seconds: 30) : const Duration(seconds: 5))) _pollOnce();
      });
    }
    _timer?.cancel();
    _timer = null;
    final s = settings.value;
    if (_api == null || !s.enabled || !directionSends(s.direction) || !canPoll) return;
    // 先记下当前内容：开启同步那一刻剪贴板里的旧内容不发送
    unawaited(_readLocal().then((t) {
      if (t != null) _guard.shouldSend(t);
    }));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<String?> _readLocal() async {
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      return d?.text;
    } catch (_) {
      return null;
    }
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final t = await _readLocal();
      if (t != null) await _maybeSend(t);
    } finally {
      _busy = false;
    }
  }

  Future<void> _maybeSend(String text) async {
    final api = _api;
    final s = settings.value;
    if (api == null || !s.enabled || !directionSends(s.direction)) return;
    if (!_guard.shouldSend(text)) return;
    if (s.skipSensitive && isSensitive(text)) return; // 疑似密码 / 密钥：不离开本机
    if (text.length > 512 * 1024) return;
    try {
      await api.postClip(text, saveHistory: s.saveHistory);
      lastError.value = null;
      status.sentAt = DateTime.now();
      status.sentPreview = text.length > 30 ? '${text.substring(0, 30)}…' : text;
      _touch();
    } catch (e) {
      _err('发送失败：$e');
    }
  }

  /// WebSocket 事件（type == clip）
  Future<bool> onRemote(Map<String, dynamic> msg) async {
    final s = settings.value;
    if (!s.enabled || !directionReceives(s.direction)) return false;
    final api = _api;
    if (api == null) return false;
    if ((msg['origin'] ?? '') == api.deviceId) return false; // 自己发的
    var clip = SyncClip.fromJson(msg);
    if (clip.text.isEmpty) {
      clip = await api.getClip() ?? clip; // 服务器省略正文时补拉
    }
    return _apply(clip);
  }

  Future<bool> _apply(SyncClip clip) async {
    if (clip.text.isEmpty || clip.ts <= _lastAppliedTs) return false; // LWW：旧的不覆盖新的
    _lastAppliedTs = clip.ts;
    if (_guard.isCurrent(clip.text)) return false;
    _guard.markRemote(clip.text);
    try {
      await Clipboard.setData(ClipboardData(text: clip.text));
      lastApplied.value = clip;
      status.receivedAt = DateTime.now();
      status.receivedFrom = clip.originName;
      _touch();
      return true;
    } catch (e) {
      _err('写入本机剪贴板失败：$e');
      return false;
    }
  }

  /// 回到前台：先看本机有没有新复制（手机在后台时复制的），有就发送；
  /// 否则拉取服务器上最新的同步内容（离线期间其他设备的复制）。
  Future<void> onResume() async {
    final api = _api;
    final s = settings.value;
    if (api == null || !s.enabled) return;
    if (directionSends(s.direction) && !canPoll) {
      // Android 10+ 只有拿到窗口焦点后才能读剪贴板；resumed 回调往往早于焦点 → 稍等再读，读不到再试一次
      await Future<void>.delayed(const Duration(milliseconds: 600));
      var t = await _readLocal();
      if (t == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        t = await _readLocal();
      }
      status.resumeReadAt = DateTime.now();
      status.resumeRead = t == null
          ? '读不到（系统拒绝或剪贴板为空${!kIsWeb && Platform.isIOS ? '；iOS 请在「允许粘贴」中选允许' : ''}）'
          : (_guard.isCurrent(t) ? '无新内容' : '有新内容 → 发送');
      _touch();
      if (t != null && !_guard.isCurrent(t)) {
        await _maybeSend(t);
        return; // 本机的复制是最新的
      }
    }
    if (directionReceives(s.direction)) {
      try {
        final c = await api.getClip();
        if (c != null && c.origin != api.deviceId) await _apply(c);
      } catch (_) {}
    }
  }

  /// 手动：立即把本机剪贴板发送到其他设备（iOS / Android 前台按钮）
  Future<String> sendNow() async {
    final api = _api;
    if (api == null) return '未登录';
    final t = await _readLocal();
    if (t == null || t.trim().isEmpty) return '本机剪贴板里没有文本';
    try {
      final sent = await api.postClip(t, saveHistory: settings.value.saveHistory);
      _guard.markRemote(t);
      return sent ? '已同步到你的其他设备' : '内容与当前同步剪贴板相同';
    } catch (e) {
      return '$e';
    }
  }
}
