import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/auth_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.store, required this.onLoggedIn});
  final ClipApi api;
  final AuthStore store;
  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController(text: 'demo1');
  final _pass = TextEditingController(text: 'demo123');
  final _base = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    widget.store.getBaseUrl().then((b) => setState(() => _base.text = b));
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _err = null; });
    try {
      await widget.store.setBaseUrl(_base.text.trim());
      await widget.api.load();
      if (_register) {
        await widget.api.register(_user.text.trim(), _pass.text);
      } else {
        await widget.api.login(_user.text.trim(), _pass.text);
      }
      if (mounted) widget.onLoggedIn();
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 24),
                Text('剪贴板', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                Text('Clipboard Online', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).hintColor)),
                const SizedBox(height: 28),
                TextField(
                  controller: _base,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'http://127.0.0.1:8099',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(controller: _user, decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? '请稍候…' : (_register ? '注册并登录' : '登录')),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _register = !_register),
                  child: Text(_register ? '已有账号？去登录' : '没有账号？去注册'),
                ),
                const SizedBox(height: 8),
                Text('演示账号 demo1 / demo123', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
