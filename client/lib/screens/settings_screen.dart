import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/auth_store.dart';

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

  @override
  void initState() {
    super.initState();
    widget.store.getBaseUrl().then((b) => setState(() => _base.text = b));
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
          ListTile(
            title: const Text('平台说明'),
            subtitle: Text(
              isMac
                  ? 'Mac 可在主页开启「监听剪贴板」：每 2 秒轮询系统剪贴板，变化时询问是否上传为私有。需授予辅助功能/粘贴板相关权限。'
                  : isIOS
                      ? 'iOS 不支持后台剪贴板监听。请在打开 App 后使用「从剪贴板导入」，或通过分享面板（未来版本）发送。'
                      : 'Android 客户端规划中。',
            ),
          ),
          const ListTile(
            title: Text('演示账号'),
            subtitle: Text('demo1 / demo123'),
          ),
        ],
      ),
    );
  }
}
