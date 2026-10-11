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
                  ? 'Mac：主页「快传」支持拖放；可监听剪贴板；文件可「在访达中显示」。'
                  : isIOS
                      ? 'iOS：快传选文件，或从微信/相册/文件「分享到剪贴板」（Share Extension）。条目「分享」可转出到微信。不支持后台剪贴板监听。'
                      : 'Android：快传选文件；其它 App「分享到剪贴板」；条目「分享」可转出到微信等。',
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
