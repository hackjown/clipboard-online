import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/sync.dart';
import '../services/api.dart';
import '../services/clip_sync.dart';
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
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final d = await widget.api.listDevices();
      if (mounted) setState(() { _devices = d; _err = null; });
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
        const Text('一台设备上复制，你的其他设备上直接粘贴（经由本服务器中转，只在你自己的设备之间；同内容只传一次；同步记录进「我的私有」）。',
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
          title: const Text('同步内容记入「我的私有」'),
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
                    '${d.platform} · ${kDirectionLabels[d.direction] ?? d.direction}${d.online ? ' · 在线' : (d.lastSeen != null ? ' · ${_ago(d.lastSeen)}' : '')}',
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
