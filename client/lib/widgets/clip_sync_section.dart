import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/sync.dart';
import '../services/api.dart';
import '../services/clip_sync.dart';
import '../services/ws_sync.dart';
import '../theme/ink_theme.dart';

/// 设置页：多设备剪贴板同步（本机开关 / 方向 / 名称 + 我的设备列表）
class ClipSyncSection extends StatefulWidget {
  const ClipSyncSection({super.key, required this.api});
  final ClipApi api;

  @override
  State<ClipSyncSection> createState() => _ClipSyncSectionState();
}

class _ClipSyncSectionState extends State<ClipSyncSection> {
  final _name = TextEditingController();
  List<SyncDevice>? _devices;
  String _user = '';
  String _instance = '';
  Timer? _auto;
  String? _err;
  bool _busy = false;

  ClipSync get _cs => ClipSync.instance;

  @override
  void initState() {
    super.initState();
    _cs.load().then((_) {
      if (!mounted) return;
      _name.text = _cs.settings.value.name;
      setState(() {});
    });
    _loadDevices();
    _auto = Timer.periodic(const Duration(seconds: 10), (_) => _loadDevices()); // 设备列表自动刷新
  }

  @override
  void dispose() {
    _auto?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final d = await widget.api.listDevices();
      if (mounted) setState(() { _devices = d.devices; _user = d.user; _instance = d.instance; _err = null; });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _save(ClipSyncSettings s) async {
    setState(() => _busy = true);
    await _cs.update(s);
    await _loadDevices();
    if (mounted) setState(() => _busy = false);
  }

  String get _platformHint {
    if (kIsWeb) return '';
    if (Platform.isMacOS) return 'Mac：开启后每秒检查剪贴板，复制即同步；App 在菜单栏常驻时也有效。收到其他设备的复制会直接写入本机剪贴板。';
    if (Platform.isIOS) {
      return 'iOS 限制：App 不能在后台读写剪贴板。只在打开 / 回到 App 时同步一次（发送本机新复制、接收其他设备最新复制）；'
          'iOS 16+ 读取时可能弹「允许粘贴」，可在 系统设置 → 本 App → 从其他 App 粘贴 → 允许。也可以点下面「立即发送」。';
    }
    if (Platform.isAndroid) return 'Android 10+ 限制：只有前台 App 能读剪贴板，因此回到 App 时同步一次；App 在前台时实时接收。';
    return '';
  }

  String _t(DateTime? d) {
    if (d == null) return '—';
    String two(int x) => x.toString().padLeft(2, '0');
    final ago = DateTime.now().difference(d);
    final rel = ago.inSeconds < 60 ? '${ago.inSeconds} 秒前' : (ago.inMinutes < 60 ? '${ago.inMinutes} 分钟前' : '${ago.inHours} 小时前');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}（$rel）';
  }

  /// 同步状态：现场排查用（截图发给开发者即可）
  Widget _statusBox(InkTokens t) {
    return AnimatedBuilder(
      animation: Listenable.merge([_cs.statusTick, WsSync.status]),
      builder: (context, _) {
        final st = _cs.status;
        final dev = widget.api.deviceId;
        final rows = <(String, String)>[
          ('服务器', widget.api.base),
          ('账号', _user.isEmpty ? '—' : _user),
          ('服务器实例', _instance.isEmpty ? '—（服务器早于 0.1.14）' : _instance),
          ('本机设备 ID', dev.length > 8 ? '${dev.substring(0, 8)}…' : dev),
          ('实时连接', WsSync.status.value),
          ('设备登记', st.registerError != null ? '失败：${st.registerError}' : '${_t(st.registeredAt)} ${st.registerConfirm ?? ''}'),
          ('上次发送', st.sentAt == null ? '—' : '${_t(st.sentAt)} ${st.sentPreview ?? ''}'),
          ('上次接收', st.receivedAt == null ? '—' : '${_t(st.receivedAt)} 来自 ${st.receivedFrom ?? ''}'),
          ('上次拉取', _t(st.polledAt)),
          if (st.resumeReadAt != null) ('回前台读剪贴板', '${_t(st.resumeReadAt)} ${st.resumeRead ?? ''}'),
          ('最近错误', st.lastError == null ? '无' : '${_t(st.lastErrorAt)} ${st.lastError}'),
        ];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.paper2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.line, width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('同步状态', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${r.$1}：', style: TextStyle(color: t.muted)),
                    TextSpan(text: r.$2),
                  ]),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            const SizedBox(height: 4),
            Text('几台设备的「服务器实例」和「账号」必须一致，否则彼此看不到、也收不到同步。',
                style: TextStyle(fontSize: 11.5, color: t.muted)),
          ]),
        );
      },
    );
  }

  String _ago(double? ts) {
    if (ts == null) return '';
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch((ts * 1000).round()));
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return ValueListenableBuilder<ClipSyncSettings>(
      valueListenable: _cs.settings,
      builder: (context, s, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('多设备剪贴板同步', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('一台设备上复制，其他已登录设备的系统剪贴板自动更新（经本服务器中转）。\n这与 Mac 首页的「监听剪贴板」无关：监听是本机复制时弹窗询问是否上传到「我的私有」；关掉监听后本机复制不会进列表。',
            style: TextStyle(fontSize: 12.5)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('本设备开启同步'),
          value: s.enabled,
          onChanged: _busy ? null : (v) => _save(s.copyWith(enabled: v)),
        ),
        const Text('同步方向', style: TextStyle(fontSize: 12.5)),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: [
            for (final d in const ['both', 'send', 'recv'])
              ButtonSegment(value: d, label: Text(kDirectionLabels[d]!)),
          ],
          selected: {s.direction == 'off' ? 'both' : s.direction},
          onSelectionChanged: (!s.enabled || _busy) ? null : (v) => _save(s.copyWith(direction: v.first)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '本设备名称'),
          onSubmitted: (v) => _save(s.copyWith(name: v.trim())),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('跳过疑似密码 / 密钥'),
          subtitle: const Text('看起来像令牌、私钥、密码的内容不离开本机'),
          value: s.skipSensitive,
          onChanged: _busy ? null : (v) => _save(s.copyWith(skipSensitive: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('把其他设备同步过来的内容记入「我的私有」'),
          subtitle: const Text('只归档「别人复制、同步到本机」的文本；本机自己复制的不会进列表（本机要用列表请开 Mac「监听剪贴板」并确认上传）'),
          value: s.saveHistory,
          onChanged: _busy ? null : (v) => _save(s.copyWith(saveHistory: v)),
        ),
        if (_platformHint.isNotEmpty) Text(_platformHint, style: TextStyle(fontSize: 12, color: t.muted)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _save(s.copyWith(name: _name.text.trim())),
              child: const Text('保存名称'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: (!s.enabled || !directionSends(s.direction))
                  ? null
                  : () async {
                      final m = await _cs.sendNow();
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
                    },
              child: const Text('立即发送本机剪贴板'),
            ),
          ),
        ]),
        ValueListenableBuilder<String?>(
          valueListenable: _cs.lastError,
          builder: (_, e, __) => e == null
              ? const SizedBox.shrink()
              : Padding(padding: const EdgeInsets.only(top: 6), child: Text(e, style: TextStyle(color: t.accent, fontSize: 12))),
        ),
        const SizedBox(height: 12),
        _statusBox(t),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('我的设备', style: TextStyle(fontWeight: FontWeight.w700))),
          IconButton(onPressed: _loadDevices, icon: const Icon(Icons.refresh), tooltip: '刷新'),
        ]),
        if (_err != null) Text(_err!, style: TextStyle(color: t.accent, fontSize: 12)),
        if (_devices == null && _err == null) const LinearProgressIndicator(),
        if (_devices != null && _devices!.isEmpty) Text('还没有设备', style: TextStyle(color: t.muted)),
        for (final d in _devices ?? const <SyncDevice>[])
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.line, width: 2),
              boxShadow: [BoxShadow(color: t.shadow, offset: const Offset(2, 2))],
            ),
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: d.online ? t.ok : Colors.transparent,
                  border: Border.all(color: t.line, width: 2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${d.name}${d.current ? '（本机）' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '${d.platform} · ${kDirectionLabels[d.direction] ?? d.direction} · ${d.online ? '在线' : '离线${d.lastSeen != null ? '（上次在线 ${_ago(d.lastSeen)}）' : ''}${d.platform == 'ios' || d.platform == 'android' ? ' · 手机只在打开 App 时在线' : ''}'}',
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
                ]),
              ),
              if (!d.current)
                TextButton(
                  onPressed: () async {
                    try {
                      await widget.api.deleteDevice(d.id);
                      _loadDevices();
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                  child: const Text('移除'),
                ),
            ]),
          ),
      ]),
    );
  }
}
