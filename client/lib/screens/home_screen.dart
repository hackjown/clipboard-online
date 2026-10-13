import 'dart:async';
import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/item.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/clipboard_watch.dart';
import '../services/deep_link.dart';
import '../services/clip_sync.dart';
import '../widgets/expiry_picker.dart';
import '../services/ws_sync.dart';
import '../utils/sensitive.dart';
import '../services/file_transfer.dart';
import '../services/menubar.dart';
import '../services/notifier.dart';
import '../services/share_inbox.dart';
import '../theme/ink_theme.dart';
import '../widgets/ink.dart';
import '../widgets/item_card.dart';
import 'edit_text_screen.dart';
import 'media_preview_screen.dart';
import 'quick_transfer_screen.dart';
import 'share_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
    required this.onOpenSettings,
  });

  final ClipApi api;
  final ClipUser user;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs;
  late final WsSync _ws;
  bool _resumed = true;
  final Set<String> _notified = <String>{};
  late final ClipboardWatch _clip;
  late final FileTransferService _xfer;
  late final ShareInbox _inbox;
  Timer? _poll;
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  String? _highlight;
  Future<void>? _restored;

  List<ClipItem> _items = [];
  Map<String, dynamic> _counts = {};
  String _q = '';
  /// 类型筛选（与 Web 一致）：0 全部 · 1 文本 · 2 文件 · 3 收藏
  int _filter = 0;
  bool _loading = true;
  String? _err;
  bool _watchOn = false;

  String get _tabKey => 'last_tab_${widget.user.username}';

  Future<void> _restoreTab() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getInt(_tabKey);
      if (v != null && v != _tabs.index && mounted) _tabs.index = v;
    } catch (_) {}
  }

  Future<void> _saveTab() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_tabKey, _tabs.index);
    } catch (_) {}
  }

  String get _scope => _tabs.index == 0 ? 'public' : 'private';

  @override
  void initState() {
    super.initState();
    // 登录后默认进「我的私有」，并记住上次选择
    _tabs = TabController(length: 2, vsync: this, initialIndex: 1);
    _restored = _restoreTab();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        _saveTab();
        _refresh();
        if (_tabs.index == 1) Notifier.instance.clearUnread();
      }
    });
    _ws = WsSync(widget.api)
      ..onEvent = _onWsEvent
      ..onHello = () {
        _refresh(silent: true); // 断线期间可能错过事件
        ClipSync.instance.onReconnect();
      };
    ClipSync.instance.wsConnected = () => _ws.connected;
    WidgetsBinding.instance.addObserver(this);
    Notifier.instance.clearUnread();
    _ws.start();
    if (MenuBarController.supported) MenuBarController.instance.onToggleWatch = _toggleWatch;
    _clip = ClipboardWatch();
    _xfer = FileTransferService(widget.api);
    _clip.onText = (t) { _confirmClipboardText(t); };
    _clip.onImage = (b, n) { _confirmClipboardImage(b, n); };
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_ws.connected) _refresh(silent: true);
    });
    _inbox = ShareInbox();
    _inbox.onShared = (items) => _offerQuickSend(items);
    _inbox.start();
    _refresh();
    DeepLinkBus.instance.pending.addListener(_onDeepLink);
    ClipSync.instance.attach(widget.api); // 多设备剪贴板同步（按本机设置决定是否工作）
    ClipSync.instance.lastApplied.addListener(_onClipApplied);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onDeepLink()); // 冷启动：链接可能早于首页到达
  }

  // ---- 深链：clipboard://item/<uuid> · clipboard://home/private ----
  Future<void> _onDeepLink() async {
    if (DeepLinkBus.instance.pending.value == null) return;
    final link = DeepLinkBus.instance.take();
    if (link == null) return;
    await _restored; // 先等「记住上次标签」恢复完，避免它把标签又改回去
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    final wantIndex = (link is HomeLink && link.scope == 'public') ? 0 : 1;
    if (_tabs.index != wantIndex) _tabs.index = wantIndex;
    Notifier.instance.clearUnread();
    if (link is ItemLink) {
      await _locateItem(link.uuid);
    } else {
      await _refresh(silent: true);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  GlobalKey _keyFor(String uuid) => _itemKeys.putIfAbsent(uuid, () => GlobalKey());

  Future<void> _locateItem(String uuid) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await _refresh(silent: true);
      if (!mounted) return;
      final i = _items.indexWhere((e) => e.uuid == uuid);
      if (i >= 0) {
        await _revealItem(i);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 800)); // 新内容可能还在落库
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有找到这条内容（可能已删除或已过期）')));
    }
  }

  Future<void> _revealItem(int i) async {
    final it = _items[i];
    setState(() => _highlight = it.uuid);
    await WidgetsBinding.instance.endOfFrame;
    var ctx = _keyFor(it.uuid).currentContext;
    if (ctx == null && _scroll.hasClients) {
      // 列表是懒加载的：先按估算高度跳到附近，再精确定位
      _scroll.jumpTo((i * 240.0).clamp(0.0, _scroll.position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
      ctx = _keyFor(it.uuid).currentContext;
    }
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.1);
    }
    Timer(const Duration(milliseconds: 3000), () {
      if (mounted && _highlight == it.uuid) setState(() => _highlight = null);
    });
    // 图片 / 视频 / PDF / 压缩包：直接打开预览
    const auto = {MediaKind.image, MediaKind.video, MediaKind.pdf, MediaKind.archive};
    if (it.isFile && auto.contains(it.mediaKind) && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaPreviewScreen(api: widget.api, item: it)));
    }
  }

  Future<void> _offerQuickSend(List<PendingTransfer> items) async {
    if (!mounted || items.isEmpty) return;
    final summary = items.map((e) {
      if (e.isText) return '文本 ${(e.textContent?.length ?? 0)} 字';
      return e.filename;
    }).join('、');
    final exp = await confirmWithExpiry(
      context,
      title: '发送到我的设备？',
      message: '收到系统分享：\n$summary\n\n将上传到本账号「私有」区，其他已登录设备会实时同步。',
      okLabel: '发送到我的设备',
    );
    if (exp == null || !mounted) return;
    try {
      for (final item in items) {
        if (item.isText && (item.textContent?.trim().isNotEmpty ?? false)) {
          await widget.api.addText(item.textContent!, visibility: 'private', expiresIn: exp);
        } else {
          await widget.api.uploadFile(
            bytes: item.bytes,
            filename: item.filename,
            visibility: 'private',
            expiresIn: exp,
            contentType: item.contentType,
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(items.length > 1 ? '已发送 ${items.length} 项，其他设备将同步' : '已发送，其他设备将同步')),
      );
      if (_tabs.index != 1) _tabs.index = 1;
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败：$e')));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      // 回到前台即视为已读
      Notifier.instance.clearUnread();
      _refresh(silent: true);
      ClipSync.instance.onResume();
    }
  }

  void _onClipApplied() {
    final c = ClipSync.instance.lastApplied.value;
    if (c == null || !mounted) return;
    final preview = c.text.replaceAll('\n', ' ');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已同步「${c.originName}」的剪贴板：${preview.length > 40 ? '${preview.substring(0, 40)}…' : preview}'),
      duration: const Duration(seconds: 2),
    ));
  }

  void _onWsEvent(Map<String, dynamic> msg) {
    if (msg['type'] == 'clip') {
      ClipSync.instance.onRemote(msg);
      return;
    }
    if (msg['type'] == 'devices') return;
    _refresh(silent: true);
    MenuBarController.instance.pulse.value++;
    // 剪贴板自动同步产生的历史不弹通知（每复制一次就响一次太吵）
    if (msg['type'] == 'create' && msg['visibility'] == 'private' && msg['source'] != 'clipsync') {
      final uuid = msg['uuid'] as String?;
      if (uuid != null) _maybeNotify(uuid);
    }
  }

  /// 其他设备上传的新私有内容 → 本地通知 + 角标（跳过本设备自己上传的）
  Future<void> _maybeNotify(String uuid) async {
    // 等本机上传请求返回并登记 uuid，避免把自己发的当成「别人发的」
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted || widget.api.ownUuids.contains(uuid) || !_notified.add(uuid)) return;
    final mb = MenuBarController.instance;
    // 正看着私有列表（主窗口可见且在前台）无需打扰；窗口隐藏在菜单栏时照常通知
    final watching = _resumed && _tabs.index == 1 && !(MenuBarController.supported && (!mb.visible || !mb.focused));
    if (watching) return;
    try {
      final r = await widget.api.items(scope: 'private');
      final it = r.items.where((e) => e.uuid == uuid).firstOrNull;
      if (it == null) return;
      final detail = it.isFile
          ? (it.filename ?? '文件')
          : ((it.content ?? '').length > 80 ? '${it.content!.substring(0, 80)}…' : (it.content ?? ''));
      await Notifier.instance.notifyIncoming(isFile: it.isFile, detail: detail);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _ws.stop();
    _clip.stopWatch();
    _inbox.stop();
    if (MenuBarController.supported) MenuBarController.instance.onToggleWatch = null;
    DeepLinkBus.instance.pending.removeListener(_onDeepLink);
    ClipSync.instance.lastApplied.removeListener(_onClipApplied);
    ClipSync.instance.detach();
    _scroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _err = null; });
    try {
      final r = await widget.api.items(
        scope: _scope,
        q: _q,
        type: _filter == 1 ? 'text' : (_filter == 2 ? 'file' : 'all'),
        starred: _filter == 3,
      );
      if (!mounted) return;
      setState(() {
        _items = r.items;
        _counts = r.counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _err = e.toString(); _loading = false; });
    }
  }

  Future<void> _confirmClipboardText(String text) async {
    if (!mounted) return;
    final exp = await confirmWithExpiry(
      context,
      title: '检测到剪贴板文本',
      message: text.length > 200 ? '${text.substring(0, 200)}…' : text,
      okLabel: '上传为私有',
    );
    if (exp != null) {
      await widget.api.addText(text, visibility: 'private', expiresIn: exp);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已上传到私有区')));
        _refresh();
      }
    }
  }

  Future<void> _confirmClipboardImage(Uint8List bytes, String name) async {
    if (!mounted) return;
    final exp = await confirmWithExpiry(
      context,
      title: '检测到剪贴板图片',
      message: '大小 ${(bytes.length / 1024).toStringAsFixed(1)} KB，上传为私有？',
    );
    if (exp != null) {
      await widget.api.uploadFile(bytes: bytes, filename: name, visibility: 'private', expiresIn: exp, contentType: 'image/png');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片已上传')));
        _refresh();
      }
    }
  }

  Future<void> _showAdd() async {
    final textCtrl = TextEditingController();
    // 默认跟随当前标签：在「公共」里添加就默认公共（之前固定私有，导致公共区“传不上去”）
    var visibility = _scope;
    var expiresIn = defaultExpiryFor(visibility);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          return Padding(
            padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, top: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('添加文本', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'private', label: Text('私有'), icon: Icon(Icons.lock_outline)),
                    ButtonSegment(value: 'public', label: Text('公共'), icon: Icon(Icons.public)),
                  ],
                  selected: {visibility},
                  onSelectionChanged: (s) => setS(() {
                    visibility = s.first;
                    expiresIn = defaultExpiryFor(visibility);
                  }),
                ),
                const SizedBox(height: 10),
                ExpiryPicker(value: expiresIn, onChanged: (v) => setS(() => expiresIn = v)),
                if (visibility == 'public')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('公共默认 1 天后自动删除，可改选', style: Theme.of(ctx).textTheme.bodySmall),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: textCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: '输入或粘贴文本…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('添加'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        });
      },
    );
    if (ok != true) return;
    final content = textCtrl.text;
    if (content.trim().isEmpty) return;

    var vis = visibility;
    if (vis == 'public' && isSensitive(content)) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('检测到可能是密钥/密码'),
          content: const Text('内容看起来像密钥、令牌或密码。建议改为私有，避免泄露。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'private'), child: const Text('改为私有')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'public'), child: const Text('仍要公开')),
          ],
        ),
      );
      if (choice == null) return;
      vis = choice;
      if (vis == 'private') expiresIn = 0;
    }

    await widget.api.addText(content, visibility: vis, expiresIn: expiresIn);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加')));
      _tabs.index = vis == 'public' ? 0 : 1;
      _refresh();
    }
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    if (f.bytes == null) return;
    final opt = await askUploadOptions(context, title: '上传 ${f.name}', initialVisibility: _scope);
    if (opt == null || !mounted) return;
    final vis = opt.visibility;
    await widget.api.uploadFile(
      bytes: f.bytes!,
      filename: f.name,
      visibility: vis,
      expiresIn: opt.expiresIn,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已上传 ${f.name}（${vis == 'public' ? '公共' : '私有'}）')));
      _tabs.index = vis == 'public' ? 0 : 1;
      _refresh();
    }
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    final opt = await askUploadOptions(context, title: '上传图片', initialVisibility: _scope);
    if (opt == null || !mounted) return;
    final vis = opt.visibility;
    await widget.api.uploadFile(
      bytes: bytes,
      filename: x.name,
      visibility: vis,
      expiresIn: opt.expiresIn,
      contentType: x.mimeType,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('图片已上传（${vis == 'public' ? '公共' : '私有'}）')));
      _tabs.index = vis == 'public' ? 0 : 1;
      _refresh();
    }
  }

  void _openQuickTransfer() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuickTransferScreen(
        api: widget.api,
        onSent: () {
          if (_tabs.index != 1) _tabs.index = 1;
          _refresh();
        },
      ),
    ));
  }

  Future<void> _toggleWatch(bool on) async {
    setState(() => _watchOn = on);
    MenuBarController.instance.setWatch(on);
    if (on) {
      _clip.startWatch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已开启「监听剪贴板」：本机复制时会询问是否上传到私有（与「多设备同步」是两回事；关掉后本机复制不会自动进列表）')),
        );
      }
    } else {
      _clip.stopWatch();
    }
  }

  Future<void> _systemShare(ClipItem it) async {
    try {
      if (it.isText) {
        await _xfer.shareText(it.content ?? '');
        return;
      }
      if (it.filename == null) return;
      final url = widget.api.downloadUrl(it.filename!);
      final file = await _xfer.downloadToCache(filename: it.filename!, remoteUrl: url);
      await _xfer.shareFile(file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分享失败：$e')));
    }
  }

  Future<void> _reveal(ClipItem it) async {
    try {
      if (it.filename == null) return;
      final url = widget.api.downloadUrl(it.filename!);
      final file = await _xfer.downloadToCache(filename: it.filename!, remoteUrl: url);
      await _xfer.revealOrOpen(file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打开失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMac = !kIsWeb && Platform.isMacOS;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        title: BrandTitle(suffix: '@${widget.user.username}'),
        actions: [
          if (isMac)
            InkIconButton(
              plain: true,
              size: 40,
              tooltip: _watchOn ? '关闭监听（本机复制不再询问上传）' : '监听剪贴板（本机复制时询问是否上传私有）',
              onPressed: () => _toggleWatch(!_watchOn),
              icon: _watchOn ? Icons.content_paste_go : Icons.content_paste,
            ),
          InkIconButton(plain: true, size: 40, tooltip: '从剪贴板导入', onPressed: () => _clip.importOnce(), icon: Icons.paste),
          InkIconButton(plain: true, size: 40, tooltip: '设置', onPressed: widget.onOpenSettings, icon: Icons.settings_outlined),
          InkIconButton(plain: true, size: 40, tooltip: '退出', onPressed: widget.onLogout, icon: Icons.logout),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AnimatedBuilder(
                    animation: _tabs,
                    builder: (_, __) => InkSegment(
                      labels: const ['公共', '我的私有'],
                      counts: ['${_counts['public'] ?? ''}', '${_counts['private'] ?? ''}'],
                      index: _tabs.index,
                      onChanged: (i) => _tabs.animateTo(i),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 「快传」入口：与标签并排，点开独立页面
              InkButton(
                label: '快传',
                icon: Icons.bolt,
                variant: InkVariant.accent,
                onPressed: _openQuickTransfer,
              ),
            ]),
          ),
        ),
      ),
      floatingActionButton: InkButton(
        label: '添加',
        icon: Icons.add,
        variant: InkVariant.accent,
        onPressed: () async {
          final a = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text('图片 / 文件将上传到：${_scope == 'public' ? '公共区（24 小时后过期）' : '我的私有'}',
                        style: Theme.of(ctx).textTheme.bodySmall),
                  ),
                  ListTile(leading: const Icon(Icons.notes), title: const Text('添加文本'), onTap: () => Navigator.pop(ctx, 'text')),
                  ListTile(leading: const Icon(Icons.image), title: const Text('选图片'), onTap: () => Navigator.pop(ctx, 'image')),
                  ListTile(leading: const Icon(Icons.attach_file), title: const Text('选文件'), onTap: () => Navigator.pop(ctx, 'file')),
                  ListTile(leading: const Icon(Icons.paste), title: const Text('从剪贴板导入'), onTap: () => Navigator.pop(ctx, 'paste')),
                ],
              ),
            ),
          );
          if (a == 'text') _showAdd();
          if (a == 'image') _pickImage();
          if (a == 'file') _pickFile();
          if (a == 'paste') _clip.importOnce();
        },
      ),
      body: PaperBackground(child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '搜索文本、文件名或用户名',
              ),
              onChanged: (v) {
                _q = v.trim();
                _refresh(silent: true);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: InkSegment(
                  key: const ValueKey('typeFilter'),
                  labels: const ['全部', '文本', '文件', '收藏'],
                  counts: [
                    '${_counts['total'] ?? ''}',
                    '${_counts['text'] ?? ''}',
                    '${_counts['file'] ?? ''}',
                    '${_counts['starred'] ?? ''}',
                  ],
                  index: _filter,
                  onChanged: (i) {
                    if (i == _filter) return;
                    setState(() => _filter = i);
                    _refresh(silent: true);
                  },
                ),
              ),
            ),
          ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(),
              child: _loading && _items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _items.isEmpty ? 1 : _items.length,
                      itemBuilder: (ctx, i) {
                        if (_items.isEmpty) {
                          return SizedBox(
                            height: 240,
                            child: Center(child: Text('暂无内容，下拉刷新或点击添加', style: TextStyle(color: context.ink.muted))),
                          );
                        }
                        final it = _items[i];
                        final card = ItemCard(
                          item: it,
                          imageUrl: it.mediaKind == MediaKind.image && it.filename != null
                              ? widget.api.downloadUrl(it.filename!)
                              : null,
                          headers: widget.api.authHeaders,
                          onOpen: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => MediaPreviewScreen(api: widget.api, item: it)),
                          ),
                          onCopy: () async {
                            if (it.isText) {
                              await _clip.copyText(it.content ?? '');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
                              }
                            } else if (it.filename != null) {
                              final url = widget.api.downloadUrl(it.filename!);
                              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                            }
                          },
                          onDelete: it.mine
                              ? () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('删除这条内容？'),
                                      content: const Text('删除后无法恢复。'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await widget.api.delete(it.uuid);
                                    _refresh();
                                  }
                                }
                              : null,
                          onShareLink: it.mine
                              ? () => showShareSheet(context, api: widget.api, item: it)
                              : null,
                          onEdit: it.mine && it.isText
                              ? () async {
                                  final saved = await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(builder: (_) => EditTextScreen(api: widget.api, item: it)),
                                  );
                                  if (saved == true) _refresh(silent: true);
                                }
                              : null,
                          onSystemShare: () => _systemShare(it),
                          onReveal: (!kIsWeb && Platform.isMacOS && it.isFile && it.filename != null)
                              ? () => _reveal(it)
                              : null,
                          onFavorite: () async {
                            await widget.api.toggleFavorite(it.uuid);
                            _refresh(silent: true);
                          },
                          onPin: it.mine
                              ? () async {
                                  await widget.api.togglePin(it.uuid);
                                  _refresh(silent: true);
                                }
                              : null,
                        );
                        final hl = _highlight == it.uuid;
                        return KeyedSubtree(
                          key: _keyFor(it.uuid),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: hl ? context.ink.accent : Colors.transparent, width: 3),
                            ),
                            child: card,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      )),
    );
  }
}
