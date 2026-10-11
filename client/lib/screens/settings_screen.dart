import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/auth_store.dart';
import '../services/menubar.dart';
import '../services/share_config.dart';
import '../services/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api, required this.store, required this.onSaved});
  final ClipApi api;
  final AuthStore store;
  final VoidCallback onSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _base = TextEditingController();
  final _bark = TextEditingController();
  bool _barkSkip = true;
  bool _barkBusy = false;
  bool? _group;
  String _shareLog = '';

  Future<void> _loadBark() async {
    try {
      final b = await widget.api.getBark();
      if (mounted) setState(() {
        _bark.text = b.url;
        _barkSkip = b.url.isEmpty ? true : b.skipThisDevice;
      });
    } catch (_) {}
  }

  void _toast(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _barkAction(Future<void> Function() f, String ok) async {
    setState(() => _barkBusy = true);
    try {
      await f();
      _toast(ok);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _barkBusy = false);
    }
  }

  Future<void> _loadShare() async {
    final g = await ShareConfig.groupAvailable();
    final l = await ShareConfig.readLog();
    if (mounted) setState(() {
      _group = g;
      _shareLog = l;
    });
  }

  @override
  void initState() {
    super.initState();
    widget.store.getBaseUrl().then((b) => setState(() => _base.text = b));
    if (ShareConfig.supported) _loadShare();
    _loadBark();
  }

  @override
  Widget build(BuildContext context) {
    final isMac = !kIsWeb && Platform.isMacOS;
    final isIOS = !kIsWeb && Platform.isIOS;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _base,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              helperText: '例如 http://192.168.1.8:8099 或 https://clip.example.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await widget.store.setBaseUrl(_base.text.trim());
              await widget.api.load();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
                widget.onSaved();
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
          const Divider(height: 32),
          const Text('外观主题', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.instance.mode,
            builder: (_, m, __) => SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {m},
              onSelectionChanged: (s) => ThemeController.instance.set(s.first),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            title: const Text('平台说明'),
            subtitle: Text(
              isMac
                  ? 'Mac：首页「快传」按钮进入快传页，支持拖放；可监听剪贴板；文件可「在访达中显示」。'
                  : isIOS
                      ? 'iOS：首页「快传」按钮进入快传页选文件，或从微信/相册/文件「分享到剪贴板」（Share Extension）。条目「分享」可转出到微信。不支持后台剪贴板监听。'
                      : 'Android：快传选文件；其它 App「分享到剪贴板」；条目「分享」可转出到微信等。',
            ),
          ),
          const Divider(height: 32),
          const Text('Bark 推送', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('在 iPhone 安装 Bark，复制设备地址粘贴到这里；私有区有新内容时推送到手机（侧载 / TrollStore 的 iPhone 同样可用，Bark 走自己的 APNs）。留空并保存即关闭。',
              style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 8),
          TextField(
            controller: _bark,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Bark 推送地址', hintText: 'https://api.day.app/你的Key'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('不推送本设备发出的内容'),
            value: _barkSkip,
            onChanged: (v) => setState(() => _barkSkip = v),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _barkBusy || _bark.text.trim().isEmpty
                    ? null
                    : () => _barkAction(() => widget.api.testBark(_bark.text), '测试推送已发送，请查看手机'),
                child: const Text('测试'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _barkBusy
                    ? null
                    : () => _barkAction(() => widget.api.putBark(_bark.text, skipThisDevice: _barkSkip),
                        _bark.text.trim().isEmpty ? 'Bark 已关闭' : 'Bark 已保存'),
                child: const Text('保存'),
              ),
            ),
          ]),
          const Divider(height: 32),
          if (ShareConfig.supported) ...[
            ListTile(
              title: const Text('分享扩展（从微信 / 相册 / 文件分享到本 App）'),
              subtitle: Text(_group == null
                  ? '检测中…'
                  : _group!
                      ? 'App Group 可用：扩展直接使用本 App 的登录信息上传到私有区。'
                      : 'App Group 不可用（免费 Apple ID / 重签名）：扩展会在分享面板里让你登录一次，之后直接上传。'),
              trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _loadShare),
            ),
            if (_group == true)
              ListTile(
                title: const Text('扩展日志'),
                subtitle: SelectableText(_shareLog.isEmpty ? '（暂无）' : _shareLog,
                    style: const TextStyle(fontFamily: 'Menlo', fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await ShareConfig.clearLog();
                    _loadShare();
                  },
                ),
              ),
          ],
          if (MenuBarController.supported) ...[
            ValueListenableBuilder<bool>(
              valueListenable: MenuBarController.instance.showDock,
              builder: (_, v, __) => SwitchListTile(
                title: const Text('在 Dock 显示图标'),
                subtitle: const Text('关闭后仅在菜单栏显示；关闭窗口不会退出 App'),
                value: v,
                onChanged: (x) => MenuBarController.instance.setShowDock(x),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: MenuBarController.instance.launchAtLogin,
              builder: (_, v, __) => SwitchListTile(
                title: const Text('开机自启'),
                subtitle: const Text('登录 Mac 后自动在菜单栏运行（macOS 13+，未签名 App 可能被系统拒绝）'),
                value: v,
                onChanged: (x) async {
                  final err = await MenuBarController.instance.setLaunchAtLogin(x);
                  if (err != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
