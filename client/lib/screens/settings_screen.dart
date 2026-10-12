import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
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
  bool _barkOpenInApp = true;
  bool _barkBusy = false;
  bool? _group;
  String _shareLog = '';

  Future<void> _loadBark() async {
    try {
      final b = await widget.api.getBark();
      if (mounted) setState(() {
        _bark.text = b.url;
        _barkSkip = b.url.isEmpty ? true : b.skipThisDevice;
        _barkOpenInApp = b.openInApp;
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
    widget.api.fetchServerVersion().then((_) {
      if (mounted) setState(() => _verLoaded = true);
    });
  }

  bool _verLoaded = false;

  /// 服务器版本低于 App（或服务器太旧没有 /api/version）→ 红色横幅 + 可复制的更新命令
  Widget _versionBanner() {
    if (!_verLoaded) return const SizedBox.shrink();
    final sv = widget.api.serverVersion;
    final outdated = sv == null || compareVersions(sv, kClientVersion) < 0;
    if (!outdated) return const SizedBox.shrink();
    final msg = sv == null
        ? 'App 连接的服务器版本过旧（早于 0.1.8，缺少 /api/version），低于 App $kClientVersion'
        : 'App 连接的服务器版本 $sv 低于 App $kClientVersion';
    final cmds = serverUpdateCommands();
    final red = Theme.of(context).colorScheme.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.10),
        border: Border.all(color: red, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(msg, style: TextStyle(color: red, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('当前使用的服务器：${widget.api.base}', style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        const Text('Bark 推送、压缩包预览、文本编辑等新功能需要新版服务器。请在服务器上更新镜像：', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Colors.black.withValues(alpha: 0.06),
          child: SelectableText(cmds, style: const TextStyle(fontFamily: 'Menlo', fontSize: 11.5, height: 1.4)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制更新命令'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: cmds));
              _toast('已复制更新命令');
            },
          ),
        ),
      ]),
    );
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
          _versionBanner(),
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
            title: const Text('版本'),
            subtitle: Text(
              '客户端 $kClientVersion\n'
              '服务器地址 ${widget.api.base}\n'
              '服务器 ${!_verLoaded ? '读取中…' : (widget.api.serverVersion ?? '未知（早于 0.1.8，缺少 /api/version）')}'
              '${_verLoaded && widget.api.serverVersion == null ? '\n服务器版本过旧，请更新 Docker 镜像（Bark / 压缩包预览 / 文本编辑等功能需要新版服务器）' : ''}',
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('点击推送打开 App'),
            subtitle: const Text('推送链接用 clipboard://item/…（直达该条内容）；关闭则打开网站链接'),
            value: _barkOpenInApp,
            onChanged: (v) => setState(() => _barkOpenInApp = v),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _barkBusy || _bark.text.trim().isEmpty
                    ? null
                    : () => _barkAction(() => widget.api.testBark(_bark.text, openInApp: _barkOpenInApp), '测试推送已发送，请查看手机'),
                child: const Text('测试'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _barkBusy
                    ? null
                    : () => _barkAction(() => widget.api.putBark(_bark.text, skipThisDevice: _barkSkip, openInApp: _barkOpenInApp),
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
