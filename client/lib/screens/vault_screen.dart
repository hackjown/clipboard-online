import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api.dart';
import '../services/clip_sync.dart';
import '../services/clipboard_watch.dart';
import '../services/vault_crypto.dart';
import '../theme/ink_theme.dart';
import '../widgets/ink.dart';

/// 端到端加密密码保险箱（类 1Password，与 Web 端 vault.js 互通）。
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.api, this.clipWatch});
  final ClipApi api;
  final ClipboardWatch? clipWatch;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  static const _autoLockDuration = Duration(minutes: 15);
  static const _clipClearDuration = Duration(seconds: 30);

  bool _loading = true;
  bool _busy = false;
  String? _err;
  VaultEnvelope? _envelope;
  Uint8List? _keyBytes;
  Uint8List? _saltBytes;
  int _iterations = VaultCrypto.defaultIterations;
  int _rev = 0;
  VaultPayload? _data;

  String _q = '';
  String _cat = 'all';
  Timer? _totpTimer;
  Timer? _lockTimer;
  Timer? _clipClearTimer;
  String? _lastSecret;

  final _pw1Ctrl = TextEditingController();
  final _pw2Ctrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchEnvelope();
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    _lockTimer?.cancel();
    _clipClearTimer?.cancel();
    _wipeMemory();
    _pw1Ctrl.dispose();
    _pw2Ctrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _wipeMemory() {
    final k = _keyBytes;
    if (k != null) {
      for (var i = 0; i < k.length; i++) {
        k[i] = 0;
      }
    }
    _keyBytes = null;
    _data = null;
  }

  void _resetAutoLock() {
    _lockTimer?.cancel();
    if (_keyBytes == null) return;
    _lockTimer = Timer(_autoLockDuration, () {
      if (!mounted || _keyBytes == null) return;
      _lockVault(auto: true);
    });
  }

  void _lockVault({bool auto = false}) {
    _totpTimer?.cancel();
    _lockTimer?.cancel();
    _wipeMemory();
    _pw1Ctrl.clear();
    _pw2Ctrl.clear();
    if (mounted) {
      setState(() {});
      _toast(auto ? '长时间未操作，密码库已自动锁定' : '密码库已锁定');
    }
  }

  Future<void> _fetchEnvelope() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final env = await widget.api.getVault();
      if (!mounted) return;
      setState(() {
        _envelope = env;
        _rev = env?.rev ?? 0;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.status == 404 ? '服务器版本过旧，请更新服务端镜像以使用密码库。' : e.message;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<bool> _saveToServer() async {
    final key = _keyBytes;
    final salt = _saltBytes;
    final data = _data;
    if (key == null || salt == null || data == null) return false;
    try {
      final env = await VaultCrypto.encryptPayload(data, key, salt, _iterations);
      final saved = await widget.api.putVault(env, expectedRev: _rev);
      _envelope = saved;
      _rev = saved.rev;
      _resetAutoLock();
      return true;
    } on ApiException catch (e) {
      _toast(e.status == 409 ? '密码库已在其他设备更新，请锁定后重新解锁同步' : e.message);
      return false;
    } catch (e) {
      _toast('保存失败：$e');
      return false;
    }
  }

  Future<void> _createVault() async {
    final p1 = _pw1Ctrl.text;
    final p2 = _pw2Ctrl.text;
    if (p1.length < 8) {
      _toast('主密码至少需要 8 个字符');
      return;
    }
    if (p1 != p2) {
      _toast('两次输入的主密码不一致');
      return;
    }
    setState(() => _busy = true);
    try {
      final salt = VaultCrypto.randomBytes(16);
      final key = await compute(
        deriveVaultKeyIsolate,
        VaultDeriveArgs(password: p1, salt: salt, iterations: VaultCrypto.defaultIterations),
      );
      _keyBytes = key;
      _saltBytes = salt;
      _iterations = VaultCrypto.defaultIterations;
      _rev = 0;
      _data = VaultPayload(items: []);
      if (await _saveToServer()) {
        _pw1Ctrl.clear();
        _pw2Ctrl.clear();
        _startTotpTimer();
        _toast('密码库已创建');
      } else {
        _wipeMemory();
      }
    } catch (e) {
      _wipeMemory();
      _toast('创建失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockVault() async {
    final pw = _pw1Ctrl.text;
    if (pw.isEmpty) {
      _toast('请输入主密码');
      return;
    }
    setState(() => _busy = true);
    try {
      final latest = await widget.api.getVault();
      if (latest == null) {
        if (mounted) {
          setState(() {
            _envelope = null;
            _rev = 0;
          });
        }
        return;
      }
      _envelope = latest;
      _rev = latest.rev;
      final salt = Uint8List.fromList(base64Decode(latest.salt));
      final key = await compute(
        deriveVaultKeyIsolate,
        VaultDeriveArgs(password: pw, salt: salt, iterations: latest.iterations),
      );
      final payload = await VaultCrypto.decryptPayload(latest, key);
      _keyBytes = key;
      _saltBytes = salt;
      _iterations = latest.iterations;
      _data = payload;
      _pw1Ctrl.clear();
      _resetAutoLock();
      _startTotpTimer();
    } catch (e) {
      _wipeMemory();
      _toast(e is FormatException ? e.message : '解锁失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startTotpTimer() {
    _totpTimer?.cancel();
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _data != null) setState(() {});
    });
  }

  Future<void> _copyField(String text, String label, {bool secret = false}) async {
    if (text.isEmpty) return;
    _resetAutoLock();
    if (secret) {
      ClipSync.instance.suppressLocalCopy(text);
      widget.clipWatch?.suppressText(text);
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (secret) {
      _lastSecret = text;
      _clipClearTimer?.cancel();
      _clipClearTimer = Timer(_clipClearDuration, () async {
        try {
          final cur = await Clipboard.getData('text/plain');
          if (cur?.text == _lastSecret) {
            ClipSync.instance.suppressLocalCopy('');
            widget.clipWatch?.suppressText('');
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        } catch (_) {}
        _lastSecret = null;
      });
      _toast('$label已复制 · 30s 后自动清空剪贴板（不同步）');
    } else {
      _toast('$label已复制');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _resetVaultDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置密码库？'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('重置将永久清空云端加密密码库且无法恢复。请输入你的 Clipboard 账号登录密码以确认：'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: '账号登录密码', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认重置')),
        ],
      ),
    );
    final pw = ctrl.text;
    ctrl.dispose();
    if (ok != true || pw.isEmpty) return;
    try {
      await widget.api.deleteVault(pw);
      _wipeMemory();
      if (mounted) {
        setState(() {
          _envelope = null;
          _rev = 0;
        });
        _toast('密码库已重置');
      }
    } catch (e) {
      _toast('重置失败：$e');
    }
  }

  Future<void> _importCsv() async {
    _resetAutoLock();
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    final path = res?.files.single.path;
    if (path == null) return;
    try {
      final raw = await File(path).readAsString();
      final imported = VaultCrypto.importFromCsv(raw);
      if (imported.isEmpty) {
        _toast('未在 CSV 中识别到有效条目');
        return;
      }
      _data!.items.insertAll(0, imported);
      if (await _saveToServer() && mounted) {
        setState(() {});
        _toast('已导入 ${imported.length} 条记录');
      }
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  Future<void> _openGeneratorDialog() async {
    _resetAutoLock();
    var len = 20;
    var symbols = true;
    var pw = VaultCrypto.genPassword(length: len, symbols: symbols);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('随机强密码生成器'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.ink.paper2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.ink.line, width: 1.5),
              ),
              child: SelectableText(pw, style: context.ink.monoStyle(15), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text('长度：$len'),
              Expanded(
                child: Slider(
                  value: len.toDouble(),
                  min: 8,
                  max: 48,
                  divisions: 40,
                  onChanged: (v) => setD(() {
                    len = v.round();
                    pw = VaultCrypto.genPassword(length: len, symbols: symbols);
                  }),
                ),
              ),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('包含符号（!@#\$%…）'),
              value: symbols,
              onChanged: (v) => setD(() {
                symbols = v ?? true;
                pw = VaultCrypto.genPassword(length: len, symbols: symbols);
              }),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => setD(() => pw = VaultCrypto.genPassword(length: len, symbols: symbols)),
              child: const Text('换一个'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _copyField(pw, '生成的密码', secret: true);
              },
              child: const Text('安全复制'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor([VaultItem? existing]) async {
    _resetAutoLock();
    final isNew = existing == null;
    var kind = existing?.kind ?? 'login';
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    final totpCtrl = TextEditingController(text: existing?.totp ?? '');
    final tagsCtrl = TextEditingController(text: (existing?.tags ?? const []).join(', '));
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    String findField(String label) =>
        existing?.fields.where((f) => f.label == label).map((f) => f.value).firstOrNull ?? '';
    final cardExpiryCtrl = TextEditingController(text: findField('有效期'));
    final cardCvvCtrl = TextEditingController(text: findField('CVV / 安全码'));
    final idExpiryCtrl = TextEditingController(text: findField('有效期至'));
    final idIssuerCtrl = TextEditingController(text: findField('签发机关'));

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(isNew ? '新建加密条目' : '编辑条目',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'login', label: Text('登录')),
                  ButtonSegment(value: 'note', label: Text('笔记')),
                  ButtonSegment(value: 'card', label: Text('卡片')),
                  ButtonSegment(value: 'idcard', label: Text('证件')),
                  ButtonSegment(value: 'apikey', label: Text('密钥')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setM(() => kind = s.first),
              ),
              const SizedBox(height: 10),
              if (kind == 'login') ...[
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '名称 *（如 GitHub、Google）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: userCtrl, decoration: const InputDecoration(labelText: '用户名 / 邮箱 / 账号', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(controller: passCtrl, decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder())),
                  ),
                  const SizedBox(width: 8),
                  InkButton(
                    label: '生成',
                    dense: true,
                    onPressed: () => passCtrl.text = VaultCrypto.genPassword(length: 20),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: '登录网址（如 https://github.com）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: totpCtrl, decoration: const InputDecoration(labelText: 'TOTP 密钥或 otpauth://（可选）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: tagsCtrl, decoration: const InputDecoration(labelText: '标签（逗号分隔）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '备注 / 安全笔记', border: OutlineInputBorder())),
              ] else if (kind == 'note') ...[
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '笔记标题 *（如 服务器备忘）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, minLines: 6, maxLines: 12, decoration: const InputDecoration(labelText: '安全笔记内容 *', alignLabelWithHint: true, border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: tagsCtrl, decoration: const InputDecoration(labelText: '标签（逗号分隔）', border: OutlineInputBorder())),
              ] else if (kind == 'card') ...[
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '卡片名称 *（如 招商银行信用卡）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: userCtrl, decoration: const InputDecoration(labelText: '持卡人姓名', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: passCtrl, decoration: const InputDecoration(labelText: '卡号', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(controller: cardExpiryCtrl, decoration: const InputDecoration(labelText: '有效期（如 08/28）', border: OutlineInputBorder())),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(controller: cardCvvCtrl, decoration: const InputDecoration(labelText: 'CVV / 安全码 / PIN', border: OutlineInputBorder())),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(controller: tagsCtrl, decoration: const InputDecoration(labelText: '标签（逗号分隔）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '备注（如 发卡行、客服电话等）', border: OutlineInputBorder())),
              ] else if (kind == 'idcard') ...[
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '证件名称 *（如 居民身份证、护照、驾照）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: userCtrl, decoration: const InputDecoration(labelText: '姓名 / 持有人', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: passCtrl, decoration: const InputDecoration(labelText: '证件号码 *', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(controller: idExpiryCtrl, decoration: const InputDecoration(labelText: '有效期至（如 2040-01-01 或 长期）', border: OutlineInputBorder())),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(controller: idIssuerCtrl, decoration: const InputDecoration(labelText: '签发机关 / 地区（可选）', border: OutlineInputBorder())),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(controller: tagsCtrl, decoration: const InputDecoration(labelText: '标签（逗号分隔）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '备注说明', border: OutlineInputBorder())),
              ] else if (kind == 'apikey') ...[
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '名称 *（如 OpenAI、AWS、GitHub Token）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Key ID / Access Key（可选）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'API 密钥 / Secret Token *', border: OutlineInputBorder())),
                  ),
                  const SizedBox(width: 8),
                  InkButton(
                    label: '生成',
                    dense: true,
                    onPressed: () => passCtrl.text = VaultCrypto.genPassword(length: 32, symbols: false),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: '接口地址 / 服务端点（如 https://api.openai.com）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: tagsCtrl, decoration: const InputDecoration(labelText: '标签（逗号分隔）', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '备注说明（如 权限、配额、到期日等）', border: OutlineInputBorder())),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: InkButton(label: '取消', onPressed: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 10),
                Expanded(
                  child: InkButton(
                    label: '加密保存',
                    variant: InkVariant.accent,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );

    if (saved == true && _data != null) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final tags = tagsCtrl.text
          .split(RegExp(r'[,，;]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(8)
          .toList();

      final customFields = (existing?.fields ?? const [])
          .where((f) => f.label != '有效期' && f.label != 'CVV / 安全码' && f.label != '有效期至' && f.label != '签发机关')
          .toList();
      if (kind == 'card') {
        final exp = cardExpiryCtrl.text.trim();
        final cvv = cardCvvCtrl.text.trim();
        if (exp.isNotEmpty) customFields.add(VaultField(label: '有效期', value: exp, secret: false));
        if (cvv.isNotEmpty) customFields.add(VaultField(label: 'CVV / 安全码', value: cvv, secret: true));
      } else if (kind == 'idcard') {
        final exp = idExpiryCtrl.text.trim();
        final iss = idIssuerCtrl.text.trim();
        if (exp.isNotEmpty) customFields.add(VaultField(label: '有效期至', value: exp, secret: false));
        if (iss.isNotEmpty) customFields.add(VaultField(label: '签发机关', value: iss, secret: false));
      }

      final itemTitle = titleCtrl.text.trim().isEmpty ? '未命名' : titleCtrl.text.trim();
      final itemUser = (kind == 'note') ? '' : userCtrl.text.trim();
      final itemPass = (kind == 'note') ? '' : passCtrl.text;
      final itemUrl = (kind == 'login' || kind == 'apikey') ? urlCtrl.text.trim() : '';
      final itemTotp = (kind == 'login') ? totpCtrl.text.trim() : '';

      if (isNew) {
        _data!.items.insert(
          0,
          VaultItem(
            id: VaultCrypto.randomId(),
            kind: kind,
            title: itemTitle,
            username: itemUser,
            password: itemPass,
            url: itemUrl,
            totp: itemTotp,
            fields: customFields,
            tags: tags,
            notes: notesCtrl.text,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        existing
          ..kind = kind
          ..title = itemTitle
          ..username = itemUser
          ..password = itemPass
          ..url = itemUrl
          ..totp = itemTotp
          ..fields = customFields
          ..tags = tags
          ..notes = notesCtrl.text
          ..updatedAt = now;
      }
      if (await _saveToServer() && mounted) {
        setState(() {});
        _toast(isNew ? '已加密保存' : '已更新');
      }
    }

    titleCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    urlCtrl.dispose();
    totpCtrl.dispose();
    tagsCtrl.dispose();
    notesCtrl.dispose();
    cardExpiryCtrl.dispose();
    cardCvvCtrl.dispose();
    idExpiryCtrl.dispose();
    idIssuerCtrl.dispose();
  }
  }

  Future<void> _showDetail(VaultItem it) async {
    _resetAutoLock();
    var showPw = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final t = context.ink;
          final otp = it.totp.isNotEmpty ? VaultCrypto.totpCode(it.totp) : null;
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(it.title,
                        style: const TextStyle(fontFamilyFallback: InkTokens.serif, fontSize: 21, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    icon: Icon(it.favorite ? Icons.star_rounded : Icons.star_border_rounded),
                    onPressed: () async {
                      it.favorite = !it.favorite;
                      it.updatedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                      setM(() {});
                      if (await _saveToServer() && mounted) setState(() {});
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openEditor(it);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: t.danger),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      _data?.items.removeWhere((x) => x.id == it.id);
                      if (await _saveToServer() && mounted) {
                        setState(() {});
                        _toast('已删除');
                      }
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                if (it.kind == 'note') ...[
                  if (it.notes.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('笔记内容', style: t.monoStyle(12, color: t.muted)),
                        TextButton(
                          onPressed: () => _copyField(it.notes, '笔记内容'),
                          child: const Text('复制全部'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.paper2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.line.withValues(alpha: 0.3)),
                      ),
                      child: SelectableText(it.notes, style: const TextStyle(fontSize: 14.5, height: 1.55)),
                    ),
                  ],
                ] else ...[
                  if (it.username.isNotEmpty)
                    _detailRow(
                      ctx,
                      it.kind == 'card'
                          ? '持卡人姓名'
                          : (it.kind == 'idcard'
                              ? '姓名 / 持有人'
                              : (it.kind == 'apikey' ? 'Key ID / 标识' : '用户名 / 账号')),
                      it.username,
                      onCopy: () => _copyField(
                          it.username,
                          it.kind == 'card'
                              ? '持卡人'
                              : (it.kind == 'idcard' ? '姓名' : '账号')),
                    ),
                  if (it.password.isNotEmpty)
                    _detailRow(
                      ctx,
                      it.kind == 'card'
                          ? '卡号'
                          : (it.kind == 'idcard'
                              ? '证件号码'
                              : (it.kind == 'apikey' ? 'API 密钥 / Secret' : '密码')),
                      showPw ? it.password : '••••••••••••',
                      trailing: TextButton(onPressed: () => setM(() => showPw = !showPw), child: Text(showPw ? '隐藏' : '显示')),
                      onCopy: () => _copyField(
                          it.password,
                          it.kind == 'card'
                              ? '卡号'
                              : (it.kind == 'idcard' ? '证件号码' : '密码'),
                          secret: true),
                    ),
                  if (otp != null)
                    _detailRow(
                      ctx,
                      '两步验证码（剩余 ${otp.remaining}s）',
                      otp.formatted,
                      highlight: true,
                      onCopy: () => _copyField(otp.code, '验证码', secret: true),
                    ),
                  if (it.url.isNotEmpty)
                    _detailRow(
                      ctx,
                      it.kind == 'apikey' ? '接口地址' : '网址',
                      it.url,
                      trailing: TextButton(
                        onPressed: () {
                          final u = Uri.tryParse(it.url.startsWith('http') ? it.url : 'https://${it.url}');
                          if (u != null) launchUrl(u, mode: LaunchMode.externalApplication);
                        },
                        child: const Text('打开'),
                      ),
                      onCopy: () => _copyField(it.url, it.kind == 'apikey' ? '接口地址' : '网址'),
                    ),
                  for (final f in it.fields)
                    _detailRow(
                      ctx,
                      f.label.isEmpty ? '自定义字段' : f.label,
                      f.secret ? '••••••••' : f.value,
                      onCopy: () => _copyField(f.value, f.label.isEmpty ? '字段' : f.label, secret: f.secret),
                    ),
                  if (it.notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('备注', style: t.monoStyle(11.5, color: t.muted)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: t.paper2, borderRadius: BorderRadius.circular(10)),
                      child: SelectableText(it.notes, style: t.monoStyle(13)),
                    ),
                  ],
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    String label,
    String value, {
    Widget? trailing,
    bool highlight = false,
    required VoidCallback onCopy,
  }) {
    final t = context.ink;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: highlight ? t.lime.withValues(alpha: 0.3) : t.paper2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.line.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.monoStyle(11, color: t.muted)),
            const SizedBox(height: 2),
            SelectableText(value, style: t.monoStyle(highlight ? 20 : 14).copyWith(fontWeight: highlight ? FontWeight.w900 : FontWeight.w600)),
          ]),
        ),
        if (trailing != null) trailing,
        IconButton(icon: const Icon(Icons.copy_rounded, size: 20), onPressed: onCopy),
      ]),
    );
  }

  List<VaultItem> _filtered() {
    final items = _data?.items ?? const <VaultItem>[];
    final q = _q.trim().toLowerCase();
    final out = items.where((it) {
      if (_cat == 'fav' && !it.favorite) return false;
      if (_cat == '2fa' && it.totp.isEmpty) return false;
      if (_cat != 'all' && _cat != 'fav' && _cat != '2fa' && it.kind != _cat) return false;
      if (q.isEmpty) return true;
      final hay = '${it.title} ${it.username} ${it.url} ${it.notes} ${it.tags.join(' ')}'.toLowerCase();
      return hay.contains(q);
    }).toList();
    out.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _data != null && _keyBytes != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('密码保险箱（E2EE）'),
        actions: unlocked
            ? [
                InkIconButton(plain: true, size: 40, tooltip: '生成密码', icon: Icons.password_rounded, onPressed: _openGeneratorDialog),
                InkIconButton(plain: true, size: 40, tooltip: '导入 CSV', icon: Icons.file_upload_outlined, onPressed: _importCsv),
                InkIconButton(plain: true, size: 40, tooltip: '锁定', icon: Icons.lock_outline, onPressed: () => _lockVault()),
                const SizedBox(width: 6),
              ]
            : null,
      ),
      floatingActionButton: unlocked
          ? InkButton(label: '新建', icon: Icons.add, variant: InkVariant.accent, onPressed: () => _openEditor())
          : null,
      body: PaperBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err != null
                ? Center(
                    child: InkCard(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(20),
                      child: Text(_err!, textAlign: TextAlign.center, style: TextStyle(color: context.ink.danger)),
                    ),
                  )
                : unlocked
                    ? _buildUnlocked(context)
                    : (_envelope == null ? _buildSetup(context) : _buildUnlock(context)),
      ),
    );
  }

  Widget _buildSetup(BuildContext context) {
    final t = context.ink;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: InkCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(22),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('创建密码保险箱', style: TextStyle(fontFamilyFallback: InkTokens.serif, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('账号密码、2FA 验证码与安全笔记仅在本机通过 PBKDF2-SHA256 + AES-256-GCM 加密，服务器只保存密文。主密码遗忘后无法找回。',
                  style: TextStyle(color: t.muted, fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 16),
              TextField(controller: _pw1Ctrl, obscureText: true, decoration: const InputDecoration(labelText: '设置主密码（至少 8 位）', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: _pw2Ctrl, obscureText: true, decoration: const InputDecoration(labelText: '再次输入主密码', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              InkButton(label: _busy ? '正在派生密钥…' : '创建并解锁', variant: InkVariant.accent, busy: _busy, onPressed: _busy ? null : _createVault),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlock(BuildContext context) {
    final t = context.ink;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: InkCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(22),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('解锁密码保险箱', style: TextStyle(fontFamilyFallback: InkTokens.serif, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('共 ${_envelope?.itemCount ?? 0} 条加密记录 · 仅在本地解密', style: t.monoStyle(12.5, color: t.muted)),
              const SizedBox(height: 16),
              TextField(
                controller: _pw1Ctrl,
                obscureText: true,
                onSubmitted: (_) => _busy ? null : _unlockVault(),
                decoration: const InputDecoration(labelText: '输入主密码', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              InkButton(label: _busy ? '正在解密…' : '解锁', variant: InkVariant.accent, busy: _busy, onPressed: _busy ? null : _unlockVault),
              const SizedBox(height: 8),
              TextButton(onPressed: _busy ? null : _resetVaultDialog, child: Text('忘记主密码？重置密码库', style: TextStyle(color: t.muted))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlocked(BuildContext context) {
    final t = context.ink;
    final items = _filtered();
    const cats = [
      ('all', '全部'),
      ('login', '登录'),
      ('2fa', '2FA'),
      ('note', '笔记'),
      ('card', '卡片'),
      ('idcard', '证件'),
      ('apikey', '密钥'),
      ('fav', '★ 收藏'),
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: '搜索名称、账号、网址、标签…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            fillColor: t.paper,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final (key, label) in cats)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _cat == key,
                  onSelected: (_) => setState(() => _cat = key),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    (_data?.items.isEmpty ?? true) ? '密码库还是空的，点右下角「新建」或右上角导入 1Password CSV。' : '没有匹配的条目',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 88),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final it = items[i];
                  final otp = it.totp.isNotEmpty ? VaultCrypto.totpCode(it.totp) : null;
                  final icon = switch (it.kind) {
                    'note' => Icons.notes_rounded,
                    'card' => Icons.credit_card_outlined,
                    'idcard' => Icons.badge_outlined,
                    'apikey' => Icons.key_rounded,
                    _ => Icons.vpn_key_outlined,
                  };
                  return InkCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    onTap: () => _showDetail(it),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: t.sun,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.line, width: 1.5),
                        ),
                        child: Icon(icon, size: 22, color: InkTokens.onColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${it.favorite ? '★ ' : ''}${it.title}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Builder(builder: (_) {
                            final subtitle = switch (it.kind) {
                              'note' => it.notes.replaceAll(RegExp(r'\s+'), ' ').trim(),
                              'card' => it.username.isNotEmpty ? it.username : (it.password.isNotEmpty ? '••••••••' : ''),
                              'idcard' => it.username.isNotEmpty ? it.username : (it.password.isNotEmpty ? '••••••••' : ''),
                              'apikey' => it.username.isNotEmpty ? it.username : (it.url.isNotEmpty ? it.url : 'API 密钥'),
                              _ => it.username.isNotEmpty ? it.username : it.url,
                            };
                            return subtitle.isNotEmpty
                                ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.monoStyle(12, color: t.muted))
                                : const SizedBox.shrink();
                          }),
                        ]),
                      ),
                      if (otp != null)
                        GestureDetector(
                          onTap: () => _copyField(otp.code, '验证码', secret: true),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: t.lime,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: t.line, width: 1.5),
                            ),
                            child: Text('${otp.formatted} · ${otp.remaining}s',
                                style: t.monoStyle(11.5, color: InkTokens.onColor).copyWith(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      if (it.password.isNotEmpty)
                        InkIconButton(
                          size: 36,
                          icon: Icons.copy_rounded,
                          tooltip: '安全复制密码',
                          onPressed: () => _copyField(it.password, '密码', secret: true),
                        ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}
