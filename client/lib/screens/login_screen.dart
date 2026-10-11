import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.store, required this.onLoggedIn});
  final ClipApi api;
  final AuthStore store;
  final ValueChanged<ClipUser> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 不再预填 demo 账号：预填内容与手输内容拼接会导致「用户名或密码不正确」
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _base = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showPass = false;
  String? _err;
  String? _detail;

  @override
  void initState() {
    super.initState();
    widget.store.getBaseUrl().then((b) {
      if (mounted) setState(() => _base.text = b);
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _err = null;
      _detail = null;
    });
    final username = _user.text.trim();
    final password = ClipApi.cleanPassword(_pass.text);
    String? requestUrl;
    try {
      // 先规范化并持久化输入框中的服务器地址，再发请求（不读旧偏好）
      final base = await widget.api.setBase(_base.text);
      if (mounted) _base.text = base;
      requestUrl = '$base/api/${_register ? 'register' : 'login'}';
      final user = _register
          ? await widget.api.register(username, password)
          : await widget.api.login(username, password);
      if (mounted) widget.onLoggedIn(user);
    } on ApiException catch (e) {
      setState(() {
        _err = e.message;
        _detail = e.requestInfo.isNotEmpty ? e.requestInfo : requestUrl;
      });
    } catch (e) {
      setState(() {
        _err = '无法连接服务器：$e';
        _detail = requestUrl != null ? 'POST $requestUrl' : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 24),
                Text('剪贴板', style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                Text('Clipboard Online', style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor)),
                const SizedBox(height: 28),
                TextField(
                  controller: _base,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'http://192.168.1.8:8099',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: !_showPass,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: '密码',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _showPass ? '隐藏密码' : '显示密码',
                      icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Text(_err!, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
                  if (_detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText(
                        _detail!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11.5),
                      ),
                    ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
