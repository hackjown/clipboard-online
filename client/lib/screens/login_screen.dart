import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_store.dart';
import '../services/deep_link.dart';
import '../theme/ink_theme.dart';
import '../widgets/ink.dart';

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

  Future<void> _pairLoginDialog() async {
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('扫码 / 配对码登录'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('在网页端「账号菜单 → 扫码配对客户端」中复制配对链接（clipboard://pair?...）或配对码粘贴到下方：'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '配对链接或配对码', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('配对登录')),
        ],
      ),
    );
    ctrl.dispose();
    if (raw == null || raw.isEmpty) return;
    setState(() {
      _busy = true;
      _err = null;
      _detail = null;
    });
    try {
      String code = raw;
      final uri = Uri.tryParse(raw);
      final dl = uri != null ? parseDeepLink(uri) : null;
      if (dl is PairLink) {
        final b = await widget.api.setBase(dl.server);
        if (mounted) _base.text = b;
        code = dl.code;
      } else {
        final b = await widget.api.setBase(_base.text);
        if (mounted) _base.text = b;
      }
      final user = await widget.api.claimPair(code);
      if (mounted) widget.onLoggedIn(user);
    } catch (e) {
      if (mounted) setState(() => _err = '配对失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 24, 8, 24),
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Row(children: [const BrandTitle(big: true)]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Text('纸与墨 · 跨设备剪贴板', style: t.monoStyle(12.5, color: t.muted)),
                  ),
                  InkCard(
                    margin: const EdgeInsets.fromLTRB(14, 10, 21, 14),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_register ? '注册' : '登录', style: t.serifStyle(24)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _base,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.none,
                          decoration: const InputDecoration(
                            labelText: '服务器地址',
                            hintText: 'http://192.168.1.8:8099',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _user,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.none,
                          keyboardType: TextInputType.visiblePassword,
                          decoration: const InputDecoration(labelText: '用户名'),
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
                          Text(_err!, style: TextStyle(color: t.danger, fontWeight: FontWeight.w700)),
                          if (_detail != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: SelectableText(_detail!, style: t.monoStyle(11.5, color: t.muted)),
                            ),
                        ],
                        const SizedBox(height: 18),
                        InkButton(
                          label: _busy ? '请稍候…' : (_register ? '注册并登录' : '登录'),
                          variant: InkVariant.accent,
                          block: true,
                          busy: _busy,
                          onPressed: _busy ? null : _submit,
                        ),
                        const SizedBox(height: 8),
                        InkButton(
                          label: '配对码一键登录',
                          icon: Icons.qr_code_scanner,
                          block: true,
                          onPressed: _busy ? null : _pairLoginDialog,
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: _busy ? null : () => setState(() => _register = !_register),
                          child: Text(_register ? '已有账号？去登录' : '没有账号？去注册'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
